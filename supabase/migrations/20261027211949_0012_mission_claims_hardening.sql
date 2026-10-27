-- CarSpot — 0012: riscatti delle missioni più robusti (review della 0011).
--
-- Perché:
--   * Il premio si pagava in un trigger BEFORE: con `INSERT … ON CONFLICT DO NOTHING` il premio
--     partiva e la riga veniva scartata, all'infinito. Ora BEFORE valida e basta; il pagamento
--     (PE, valuta, badge) è in un trigger AFTER, che non scatta per le righe scartate.
--   * La fine del periodo si calcolava `window_start + 1 month` in UTC: per i fusi UTC+ tagliava
--     uno o più giorni (ottobre a Roma: fino al 30) e sbagliava di un'ora nei cambi d'ora.
--     Ora il client manda anche `window_end` (mezzanotte locale della fine) e il server controlla
--     che entrambi gli estremi siano mezzanotti plausibili e la durata coerente (±1 h per l'ora legale).
--   * Finestre dello stesso tipo di periodo che si sovrappongono (fusi scelti ad arte per contare
--     due volte le stesse carte) sono rifiutate; tetti e sovrapposizioni sotto lock per proprietario.
--   * Il vecchio endpoint `challenge_claims` (0004) pagava senza verificare: chiuso.
--
-- Cosa resta fidato dal telefono (ADR 0002): quale modello di missione riscattare (non verifichiamo
-- l'assegnazione), il fuso orario entro UTC−12…UTC+14 (coerente tra inizio e fine), le carte stesse.

-- ---------------------------------------------------------------------------
-- 1. Vecchi obiettivi del giorno: niente più insert né premi
-- ---------------------------------------------------------------------------
drop trigger if exists challenge_claims_award on public.challenge_claims;
drop function if exists private.award_claim();
drop policy if exists "riscatti: crea i propri" on public.challenge_claims;
revoke insert on public.challenge_claims from authenticated;

-- ---------------------------------------------------------------------------
-- 2. Colonne nuove
-- ---------------------------------------------------------------------------
alter table public.mission_claims
    add column window_end timestamptz,
    add column badge_id   text;              -- deciso dal server
grant insert (window_end) on public.mission_claims to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Finestra del periodo all'ora del telefono
-- ---------------------------------------------------------------------------
-- Inizio e fine devono essere mezzanotti locali plausibili (UTC−12…UTC+14) delle date del periodo
-- e la durata quella del calendario ±1 h (cambio d'ora).
create function private.mission_window_ok(p_period text, p_start date,
                                          p_ws timestamptz, p_we timestamptz)
returns boolean
language sql immutable set search_path = '' as $$
    with b as (
        select p_start::timestamp at time zone 'UTC' as m0,
               (case p_period when 'day'  then p_start + 1
                              when 'week' then p_start + 7
                              else (p_start + interval '1 month')::date
                end)::timestamp at time zone 'UTC' as m1
    )
    select coalesce(
               p_ws between b.m0 - interval '14 hours' and b.m0 + interval '12 hours'
           and p_we between b.m1 - interval '14 hours' and b.m1 + interval '12 hours'
           and (p_we - p_ws) between (b.m1 - b.m0) - interval '1 hour'
                                 and (b.m1 - b.m0) + interval '1 hour',
           false)
      from b
$$;

-- ---------------------------------------------------------------------------
-- 4. Riscatto: BEFORE valida (nessun effetto), AFTER paga
-- ---------------------------------------------------------------------------
drop trigger if exists mission_claims_award on public.mission_claims;
drop function if exists private.award_mission();

create function private.check_mission_claim() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
    t        public.mission_templates%rowtype;
    cm       public.community_missions%rowtype;
    v_rule   jsonb;
    v_decade integer;
    v_make   text;
begin
    -- Un riscatto alla volta per proprietario e tipo di periodo: tetti e sovrapposizioni senza corse.
    perform pg_advisory_xact_lock(
        hashtextextended('mission_claims|' || new.owner_id || '|' || new.period, 0));

    -- Già registrato: stesso errore di una chiave duplicata (il retry dopo una risposta persa
    -- dev'essere un successo, non un rifiuto del tetto).
    if exists (select 1 from public.mission_claims
                where owner_id = new.owner_id and period = new.period
                  and period_start = new.period_start and mission_id = new.mission_id) then
        raise exception 'riscatto già registrato' using errcode = 'unique_violation';
    end if;

    if new.period = 'community' then
        select * into cm from public.community_missions where id = new.mission_id;
        if not found or new.period_start <> cm.starts_on then
            raise exception 'missione comune sconosciuta' using errcode = 'P0001';
        end if;
        -- Tutto dalla riga del server, nulla dal client.
        new.params       := null;
        new.goal         := cm.goal;
        new.window_start := cm.starts_on::timestamp at time zone 'UTC' - interval '14 hours';
        new.window_end   := (cm.ends_on + 1)::timestamp at time zone 'UTC' + interval '12 hours';
        new.reward       := cm.reward;
        new.badge_id     := cm.badge_id;
        v_rule           := cm.rule;
    else
        select * into t from public.mission_templates
         where id = new.mission_id and period = new.period;
        if not found then
            raise exception 'modello di missione sconosciuto' using errcode = 'P0001';
        end if;
        if (new.period = 'week' and extract(isodow from new.period_start) <> 1)
           or (new.period = 'month' and extract(day from new.period_start) <> 1) then
            raise exception 'inizio periodo non valido' using errcode = 'P0001';
        end if;
        if not private.mission_window_ok(new.period, new.period_start,
                                         new.window_start, new.window_end) then
            raise exception 'finestra del periodo non valida' using errcode = 'P0001';
        end if;
        if exists (select 1 from public.mission_claims c
                    where c.owner_id = new.owner_id and c.period = new.period
                      and c.period_start <> new.period_start
                      and c.window_end is not null
                      and tstzrange(c.window_start, c.window_end)
                          && tstzrange(new.window_start, new.window_end)) then
            raise exception 'finestra sovrapposta a un altro periodo' using errcode = 'P0001';
        end if;
        if new.goal < t.goal_min or new.goal > t.goal_max then
            raise exception 'obiettivo fuori misura' using errcode = 'P0001';
        end if;

        v_rule := t.rule;
        if t.param is null then
            if new.params is not null and new.params <> '{}'::jsonb and new.params <> 'null'::jsonb then
                raise exception 'parametri non ammessi' using errcode = 'P0001';
            end if;
            new.params := null;
        else
            if new.params is null or jsonb_typeof(new.params) <> 'object'
               or exists (select 1 from jsonb_object_keys(new.params) as k where k <> t.param) then
                raise exception 'parametri non validi' using errcode = 'P0001';
            end if;
            if t.param = 'decade' then
                if jsonb_typeof(new.params -> 'decade') <> 'number' then
                    raise exception 'decennio non valido' using errcode = 'P0001';
                end if;
                v_decade := (new.params ->> 'decade')::integer;
                if v_decade not between 1950 and 2010 or v_decade % 10 <> 0 then
                    raise exception 'decennio non valido' using errcode = 'P0001';
                end if;
                v_rule := v_rule || jsonb_build_object('year_from', v_decade, 'year_to', v_decade + 9);
            else
                v_make := private.norm(new.params ->> 'make');
                if v_make = '' or length(v_make) > 40 then
                    raise exception 'marca non valida' using errcode = 'P0001';
                end if;
                v_rule := v_rule || jsonb_build_object('makes', jsonb_build_array(v_make));
            end if;
        end if;

        if (select count(*) from public.mission_claims
             where owner_id = new.owner_id and period = new.period
               and period_start = new.period_start)
           >= (case new.period when 'month' then 2 else 3 end) then
            raise exception 'tetto di riscatti del periodo raggiunto' using errcode = 'P0001';
        end if;

        new.reward   := least(t.reward_max, t.reward_base + t.reward_per_unit * new.goal);
        new.badge_id := case when t.badge
                             then 'month:' || to_char(new.period_start, 'YYYY-MM') || '|' || t.id end;
    end if;

    -- Dall'inizio a 2 giorni dopo la fine (5 minuti di tolleranza sull'orologio).
    if now() < new.window_start - interval '5 minutes'
       or now() > new.window_end + interval '2 days' then
        raise exception 'riscatto fuori finestra' using errcode = 'P0001';
    end if;
    if private.mission_progress(new.owner_id, v_rule, new.window_start, new.window_end) < new.goal then
        raise exception 'missione non completata' using errcode = 'P0001';
    end if;
    return new;
end $$;

-- Paga solo le righe davvero inserite.
create function private.pay_mission_claim() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    perform private.grant_reward(new.owner_id, new.reward);
    if new.badge_id is not null then
        insert into public.player_badges (owner_id, badge_id)
        values (new.owner_id, new.badge_id)
        on conflict do nothing;
    end if;
    return null;
end $$;

revoke all on all functions in schema private from public, anon, authenticated;

create trigger mission_claims_check before insert on public.mission_claims
    for each row execute function private.check_mission_claim();
create trigger mission_claims_pay after insert on public.mission_claims
    for each row execute function private.pay_mission_claim();
