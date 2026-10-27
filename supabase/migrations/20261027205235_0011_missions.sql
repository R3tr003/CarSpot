-- CarSpot — 0011: missioni giornaliere, settimanali, mensili e comuni.
--
-- Perché (ADR 0002):
--   * Le missioni sono regole-dati in JSON, gemelle di `MissionRule` (Swift): il server
--     ricalcola il progresso dalle carte al riscatto, invece di fidarsi del telefono (0004).
--   * Il telefono sceglie le missioni (offline/ospite); il server accetta qualsiasi modello
--     del periodo ma con progresso reale, tetti 3/3/2, importo deciso qui.
--   * Finestre all'ora del telefono: l'inizio del periodo deve stare entro il fuso possibile
--     (−14 h / +12 h dalla mezzanotte UTC della data) e si riscatta fino a 2 giorni dopo la fine.
-- Gemelli lato client: MissionRule, MissionCatalog, MissionPeriod. Si cambiano in coppia.
-- `challenge_rewards` / `challenge_claims` (0004) restano ma non sono più usate dall'app.

-- ---------------------------------------------------------------------------
-- 1. Tabelle
-- ---------------------------------------------------------------------------
create table public.mission_templates (
    id              text primary key,
    period          text not null check (period in ('day', 'week', 'month')),
    rule            jsonb not null,
    goal_min        integer not null check (goal_min > 0),
    goal_max        integer not null,
    reward_base     integer not null check (reward_base >= 0),
    reward_per_unit integer not null check (reward_per_unit >= 0),
    reward_max      integer not null check (reward_max > 0),
    badge           boolean not null default false,
    param           text check (param in ('decade', 'make')),
    active          boolean not null default true,
    check (goal_max >= goal_min)
);

create table public.community_missions (
    id        text primary key,
    scope     text not null,                 -- 'world' | 'europe' | codice ISO ('IT')
    title_it  text not null,
    title_en  text not null,
    starts_on date not null,
    ends_on   date not null,
    rule      jsonb not null,
    goal      integer not null check (goal > 0),
    reward    integer not null check (reward > 0),
    badge_id  text,
    check (ends_on >= starts_on)
);

create table public.mission_claims (
    owner_id     text not null default (auth.jwt() ->> 'sub')
                 references public.profiles(id) on delete cascade,
    period       text not null check (period in ('day', 'week', 'month', 'community')),
    period_start date not null,
    mission_id   text not null,
    goal         integer not null,
    params       jsonb,
    window_start timestamptz,
    reward       integer not null default 0,   -- deciso dal trigger
    created_at   timestamptz not null default now(),
    primary key (owner_id, period, period_start, mission_id)
);

create table public.player_badges (
    owner_id  text not null references public.profiles(id) on delete cascade,
    badge_id  text not null,
    earned_at timestamptz not null default now(),
    primary key (owner_id, badge_id)
);

-- Conteggio delle carte per finestra di cattura.
create index cards_owner_captured_idx on public.cards(owner_id, captured_at);

-- ---------------------------------------------------------------------------
-- 2. Permessi e RLS (niente anon; il client inserisce solo i propri riscatti)
-- ---------------------------------------------------------------------------
revoke all on public.mission_templates, public.community_missions,
              public.mission_claims, public.player_badges from anon, authenticated;
grant select on public.mission_templates, public.community_missions to authenticated;
grant select on public.mission_claims, public.player_badges to authenticated;
grant insert (owner_id, period, period_start, mission_id, goal, params, window_start)
      on public.mission_claims to authenticated;

alter table public.mission_templates  enable row level security;
alter table public.community_missions enable row level security;
alter table public.mission_claims     enable row level security;
alter table public.player_badges      enable row level security;

create policy "modelli di missione: lettura" on public.mission_templates for select to authenticated
    using (true);
create policy "missioni comuni: lettura" on public.community_missions for select to authenticated
    using (true);
create policy "riscatti missioni: leggi i propri" on public.mission_claims for select to authenticated
    using (owner_id = ((select auth.jwt()) ->> 'sub'));
create policy "riscatti missioni: crea i propri" on public.mission_claims for insert to authenticated
    with check (owner_id = ((select auth.jwt()) ->> 'sub'));
create policy "badge: leggi i propri" on public.player_badges for select to authenticated
    using (owner_id = ((select auth.jwt()) ->> 'sub'));

-- ---------------------------------------------------------------------------
-- 3. Regola (gemella di MissionRule.progress)
-- ---------------------------------------------------------------------------
create function private.rarity_rank(p text) returns integer
language sql immutable set search_path = '' as $$
    select case p when 'Comune' then 0 when 'Rara' then 1 when 'Epica' then 2
                  when 'Leggendaria' then 3 else -1 end
$$;

-- Carte non ripetizione del proprietario in [p_from, p_to) che rispettano la regola.
-- `fresh`: solo chiavi mai viste prima di p_from. `count`: cards | models | makes | areas.
create function private.mission_progress(p_owner text, p_rule jsonb,
                                         p_from timestamptz, p_to timestamptz)
returns integer
language plpgsql stable security definer set search_path = '' as $$
declare
    v_count  text := coalesce(p_rule ->> 'count', 'cards');
    v_fresh  text := p_rule ->> 'fresh';
    v_makes  jsonb := case when jsonb_typeof(p_rule -> 'makes') = 'array' then p_rule -> 'makes' end;
    v_models jsonb := case when jsonb_typeof(p_rule -> 'models') = 'array' then p_rule -> 'models' end;
    v_result integer;
begin
    with base as (
        select private.norm(c.make) as make_key,
               private.norm(c.make) || '|' || private.norm(c.model) as model_key,
               private.norm(c.spotted_area) as area_key
          from public.cards c
         where c.owner_id = p_owner
           and not c.is_repeat
           and c.captured_at >= p_from and c.captured_at < p_to
           and (p_rule ->> 'min_rarity' is null
                or private.rarity_rank(c.rarity) >= private.rarity_rank(p_rule ->> 'min_rarity'))
           and (p_rule ->> 'year_from' is null
                or (coalesce(c.year, 0) > 0 and c.year >= (p_rule ->> 'year_from')::integer))
           and (p_rule ->> 'year_to' is null
                or (coalesce(c.year, 0) > 0 and c.year <= (p_rule ->> 'year_to')::integer))
           and (p_rule ->> 'min_power' is null or c.power >= (p_rule ->> 'min_power')::integer)
           and (v_makes is null or private.norm(c.make) in (select jsonb_array_elements_text(v_makes)))
           and (v_models is null or exists (
                   select 1 from jsonb_array_elements_text(v_models) as t(v)
                    where private.norm(c.make) || '|' || private.norm(c.model) = t.v
                       or starts_with(private.norm(c.make) || '|' || private.norm(c.model), t.v || ' ')))
    ), earlier as (
        select private.norm(e.make) as make_key,
               private.norm(e.make) || '|' || private.norm(e.model) as model_key,
               private.norm(e.spotted_area) as area_key
          from public.cards e
         where v_fresh is not null
           and e.owner_id = p_owner
           and not e.is_repeat
           and e.captured_at < p_from
    ), filtered as (
        select b.* from base b
         where v_fresh is null
            or (v_fresh = 'model' and not exists (select 1 from earlier e where e.model_key = b.model_key))
            or (v_fresh = 'make'  and b.make_key <> ''
                                  and not exists (select 1 from earlier e where e.make_key = b.make_key))
            or (v_fresh = 'area'  and b.area_key <> ''
                                  and not exists (select 1 from earlier e where e.area_key = b.area_key))
    )
    select case v_count
               when 'models' then count(distinct model_key)
               when 'makes'  then count(distinct make_key) filter (where make_key <> '')
               when 'areas'  then count(distinct area_key) filter (where area_key <> '')
               else count(*)
           end::integer
      into v_result
      from filtered;
    return coalesce(v_result, 0);
end $$;

-- ---------------------------------------------------------------------------
-- 4. Riscatto: verifica e premio (prima dell'insert, così `reward` resta nella riga)
-- ---------------------------------------------------------------------------
create function private.award_mission() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
    t          public.mission_templates%rowtype;
    cm         public.community_missions%rowtype;
    v_rule     jsonb;
    v_from     timestamptz;
    v_to       timestamptz;
    v_midnight timestamptz := new.period_start::timestamp at time zone 'UTC';
    v_reward   integer;
    v_badge    text;
    v_decade   integer;
    v_make     text;
begin
    if new.period = 'community' then
        select * into cm from public.community_missions where id = new.mission_id;
        if not found then
            raise exception 'missione comune sconosciuta' using errcode = 'P0001';
        end if;
        if new.period_start <> cm.starts_on or new.goal <> cm.goal then
            raise exception 'missione comune non coerente' using errcode = 'P0001';
        end if;
        v_from   := v_midnight - interval '14 hours';
        v_to     := (cm.ends_on + 1)::timestamp at time zone 'UTC' + interval '12 hours';
        v_rule   := cm.rule;
        v_reward := cm.reward;
        v_badge  := cm.badge_id;
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
        -- Mezzanotte locale della data, in qualsiasi fuso (UTC−12 … UTC+14).
        if new.window_start is null
           or new.window_start < v_midnight - interval '14 hours'
           or new.window_start > v_midnight + interval '12 hours' then
            raise exception 'inizio finestra non valido' using errcode = 'P0001';
        end if;
        if new.goal < t.goal_min or new.goal > t.goal_max then
            raise exception 'obiettivo fuori misura' using errcode = 'P0001';
        end if;

        v_rule := t.rule;
        if t.param is null then
            if new.params is not null and new.params <> '{}'::jsonb and new.params <> 'null'::jsonb then
                raise exception 'parametri non ammessi' using errcode = 'P0001';
            end if;
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

        v_from   := new.window_start;
        v_to     := new.window_start + case new.period when 'day'  then interval '1 day'
                                                       when 'week' then interval '7 days'
                                                       else interval '1 month' end;
        v_reward := least(t.reward_max, t.reward_base + t.reward_per_unit * new.goal);
        v_badge  := case when t.badge
                         then 'month:' || to_char(new.period_start, 'YYYY-MM') || '|' || t.id end;
    end if;

    -- Finestra di riscatto: dall'inizio a 2 giorni dopo la fine (5 minuti di tolleranza sull'orologio).
    if now() < v_from - interval '5 minutes' or now() > v_to + interval '2 days' then
        raise exception 'riscatto fuori finestra' using errcode = 'P0001';
    end if;
    if private.mission_progress(new.owner_id, v_rule, v_from, v_to) < new.goal then
        raise exception 'missione non completata' using errcode = 'P0001';
    end if;

    new.reward := v_reward;
    perform private.grant_reward(new.owner_id, v_reward);
    if v_badge is not null then
        insert into public.player_badges (owner_id, badge_id)
        values (new.owner_id, v_badge)
        on conflict do nothing;
    end if;
    return new;
end $$;

revoke all on all functions in schema private from public, anon, authenticated;

create trigger mission_claims_award before insert on public.mission_claims
    for each row execute function private.award_mission();

-- ---------------------------------------------------------------------------
-- 5. Repertorio (gemello di MissionCatalog.pool) e missioni comuni di prova
-- ---------------------------------------------------------------------------
insert into public.mission_templates
    (id, period, rule, goal_min, goal_max, reward_base, reward_per_unit, reward_max, badge, param) values
    ('d_cards',    'day', '{"count":"cards"}',                         1, 6,  40, 20, 160, false, null),
    ('d_rare',     'day', '{"count":"cards","min_rarity":"Rara"}',      1, 2,  60, 40, 140, false, null),
    ('d_epic',     'day', '{"count":"cards","min_rarity":"Epica"}',     1, 1, 130,  0, 130, false, null),
    ('d_vintage',  'day', '{"count":"cards","year_to":1989}',           1, 2,  70, 40, 150, false, null),
    ('d_newarea',  'day', '{"count":"cards","fresh":"area"}',           1, 2,  60, 40, 140, false, null),
    ('d_makes',    'day', '{"count":"makes"}',                          2, 3,  40, 30, 130, false, null),
    ('d_newmodel', 'day', '{"count":"models","fresh":"model"}',         1, 2,  60, 40, 140, false, null),
    ('d_power',    'day', '{"count":"cards","min_power":80}',           1, 2,  70, 40, 150, false, null),

    ('w_cards',     'week', '{"count":"cards"}',                        5, 40, 150,  10, 500, false, null),
    ('w_makes',     'week', '{"count":"makes"}',                        3,  8, 150,  30, 400, false, null),
    ('w_areas',     'week', '{"count":"areas"}',                        2,  6, 150,  40, 400, false, null),
    ('w_newmodels', 'week', '{"count":"models","fresh":"model"}',       2, 10, 150,  30, 450, false, null),
    ('w_rare',      'week', '{"count":"cards","min_rarity":"Rara"}',    2,  8, 150,  30, 400, false, null),
    ('w_epic',      'week', '{"count":"cards","min_rarity":"Epica"}',   1,  3, 200, 100, 500, false, null),
    ('w_vintage',   'week', '{"count":"cards","year_to":1989}',         1,  5, 150,  50, 400, false, null),
    ('w_decade',    'week', '{"count":"cards"}',                        1,  3, 200,  80, 450, false, 'decade'),
    ('w_make',      'week', '{"count":"cards"}',                        2,  6, 150,  40, 400, false, 'make'),

    ('m_list_icons', 'month',
     '{"count":"models","models":["ferrari|f40","ferrari|testarossa","lamborghini|countach","porsche|959","bmw|m1","lancia|delta integrale","audi|quattro"]}',
     1, 2, 750, 250, 1250, true, null),
    ('m_list_hothatch', 'month',
     '{"count":"models","models":["volkswagen|golf gti","abarth|595","peugeot|205 gti","renault|clio rs","ford|fiesta st","honda|civic type r","mini|cooper s"]}',
     1, 3, 600, 200, 1200, true, null),
    ('m_list_italian', 'month',
     '{"count":"models","models":["alfa romeo|giulia quadrifoglio","alfa romeo|4c","maserati|mc20","lamborghini|huracan","ferrari|296","ferrari|roma"]}',
     1, 2, 750, 250, 1250, true, null),
    ('m_list_german', 'month',
     '{"count":"models","models":["porsche|911","bmw|m3","bmw|m4","audi|rs","mercedes-benz|amg"]}',
     1, 3, 600, 200, 1200, true, null),
    ('m_newmodels', 'month', '{"count":"models","fresh":"model"}',      8, 50, 600,  15, 1500, true, null),
    ('m_areas',     'month', '{"count":"areas"}',                       4, 15, 600,  50, 1500, true, null),
    ('m_legend',    'month', '{"count":"cards","min_rarity":"Leggendaria"}', 1, 2, 900, 300, 1500, true, null),
    ('m_vintage',   'month', '{"count":"cards","year_to":1989}',        3, 15, 600,  40, 1200, true, null),
    ('m_makes',     'month', '{"count":"makes"}',                       6, 20, 600,  40, 1400, true, null);

insert into public.community_missions
    (id, scope, title_it, title_en, starts_on, ends_on, rule, goal, reward, badge_id) values
    ('2026-11-world-legend', 'world', 'Una Leggendaria', 'A Legendary',
     '2026-11-01', '2026-11-30', '{"count":"cards","min_rarity":"Leggendaria"}', 1, 800,
     'community:2026-11-legend'),
    ('2026-11-it-hothatch', 'IT', 'Piccole cattive italiane', 'Italian hot hatches',
     '2026-10-26', '2026-11-30',
     '{"count":"models","models":["abarth|595","fiat|panda 100hp","lancia|delta integrale","alfa romeo|mito"]}',
     1, 600, 'community:2026-11-it-hothatch');
