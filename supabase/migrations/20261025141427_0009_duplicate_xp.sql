-- 0009 — Doppioni e "stessa auto".
-- * XP decrescente per i doppioni dello stesso modello: piena, poi 25%, e dimezza fino a 0.
-- * Ripetizione della stessa auto (stesso modello nello stesso quartiere nelle 24 ore
--   precedenti, contando anche le ripetizioni): carta salvata con is_repeat = true, 0 premi.
-- Gemelli lato client: CardCopies (xp, isRepeatByPlace). Le costanti vanno cambiate in coppia.

-- 1. Colonna: il client può segnalarla true (foto quasi identica: abbassa solo i propri
--    punti); il server la mette a true per la regola del posto. Mai riportata a false.
alter table public.cards add column is_repeat boolean not null default false;
grant insert (is_repeat) on public.cards to authenticated;

-- 2. Chiave normalizzata: minuscole, spazi ai lati tolti, interni ridotti a uno.
create function private.norm(p text) returns text
language sql immutable set search_path = '' as $$
    select lower(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g'))
$$;

-- 3. Prima dell'insert: stessa auto nello stesso posto nelle 24 ore precedenti.
create function private.mark_repeat() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    if new.is_repeat then
        return new;
    end if;
    if private.norm(new.spotted_area) <> '' and exists (
        select 1 from public.cards c
        where c.owner_id = new.owner_id
          and c.id <> new.id
          and private.norm(c.make) = private.norm(new.make)
          and private.norm(c.model) = private.norm(new.model)
          and private.norm(c.spotted_area) = private.norm(new.spotted_area)
          and c.captured_at < new.captured_at
          and c.captured_at >= new.captured_at - interval '24 hours'
    ) then
        new.is_repeat := true;
    end if;
    return new;
end $$;

create trigger cards_mark_repeat before insert on public.cards
    for each row execute function private.mark_repeat();

-- 4. Premio: 0 per le ripetizioni; per i doppioni 25% e poi dimezza (arrotondato per difetto).
create or replace function private.award_card() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
    v_base integer;
    v_copy integer;
    v_xp integer;
begin
    if new.is_repeat then
        return null;
    end if;
    v_base := case new.rarity
        when 'Comune'      then 20
        when 'Rara'        then 55
        when 'Epica'       then 130
        when 'Leggendaria' then 260
        else 0 end;
    select 1 + count(*) into v_copy
      from public.cards c
     where c.owner_id = new.owner_id
       and c.id <> new.id
       and not c.is_repeat
       and private.norm(c.make) = private.norm(new.make)
       and private.norm(c.model) = private.norm(new.model);
    v_xp := case when v_copy <= 1 then v_base
                 else floor(v_base * 0.25 / power(2, v_copy - 2))::integer end;
    perform private.grant_reward(new.owner_id, greatest(v_xp, 0));
    return null;
end $$;

revoke all on all functions in schema private from public, anon, authenticated;
