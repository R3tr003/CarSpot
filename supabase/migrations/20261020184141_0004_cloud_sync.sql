-- CarSpot — 0004: sync cloud carte/profilo.
--
-- Perché:
--   * Pull incrementale dal telefono: serve un cursore impostato dal server
--     (`cards.created_at`), non `captured_at` che viene dal telefono.
--   * Le carte sono append-only: niente update dal client; insert idempotente sull'id
--     generato dal telefono (`on conflict do nothing`).
--   * XP/valuta/livello li assegna il DB con trigger (nessuna richiesta extra dal client):
--     funzioni SECURITY DEFINER nello schema `private`, non esposto da PostgREST.
--   * Foto anonimizzate nel bucket privato `spots`, path `<sub>/<card_id>.jpg`.

-- ---------------------------------------------------------------------------
-- 1. Carte: cursore, immutabilità, valori plausibili
-- ---------------------------------------------------------------------------
alter table public.cards
    add column created_at timestamptz not null default now(),
    add constraint cards_power_range    check (power    between 0 and 100),
    add constraint cards_agility_range  check (agility  between 0 and 100),
    add constraint cards_presence_range check (presence between 0 and 100);

-- L'indice composto copre anche la FK su owner_id.
create index cards_owner_created_idx on public.cards(owner_id, created_at);
drop index public.cards_owner_idx;

-- Insert solo sulle colonne del client (created_at lo decide il server); niente update.
revoke insert, update on public.cards from authenticated;
grant insert (id, owner_id, make, model, year, rarity, color_name, power, agility,
              presence, photo_path, spotted_area, captured_at)
      on public.cards to authenticated;
drop policy "carte: aggiorna le proprie" on public.cards;

-- ---------------------------------------------------------------------------
-- 2. Obiettivi del giorno: importi sul server, riscatti per utente
-- ---------------------------------------------------------------------------
create table public.challenge_rewards (
    challenge_id text primary key,
    reward       integer not null check (reward > 0)
);
insert into public.challenge_rewards (challenge_id, reward) values
    ('today2', 120), ('vintage', 200), ('rarePlus', 90),
    ('epic', 160), ('trio', 110), ('powerful', 130);

create table public.challenge_claims (
    owner_id     text not null default (auth.jwt() ->> 'sub')
                 references public.profiles(id) on delete cascade,
    day          date not null,
    challenge_id text not null references public.challenge_rewards(challenge_id),
    created_at   timestamptz not null default now(),
    primary key (owner_id, day, challenge_id)
);
create index challenge_claims_challenge_idx on public.challenge_claims(challenge_id);

revoke all on public.challenge_rewards, public.challenge_claims from anon, authenticated;
grant select on public.challenge_rewards to authenticated;
grant select on public.challenge_claims to authenticated;
grant insert (owner_id, day, challenge_id) on public.challenge_claims to authenticated;

alter table public.challenge_rewards enable row level security;
alter table public.challenge_claims  enable row level security;

create policy "premi obiettivi: lettura" on public.challenge_rewards for select to authenticated
    using (true);
create policy "riscatti: leggi i propri" on public.challenge_claims for select to authenticated
    using (owner_id = ((select auth.jwt()) ->> 'sub'));
create policy "riscatti: crea i propri" on public.challenge_claims for insert to authenticated
    with check (owner_id = ((select auth.jwt()) ->> 'sub'));

-- ---------------------------------------------------------------------------
-- 3. Premi lato server (schema privato, non raggiungibile via /rest/v1/rpc)
-- ---------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Stessa curva di LevelSystem: step(l) = 100 + (l-1)*60,
-- xp per arrivare al livello l+1 = 100*l + 30*l*(l-1).
create function private.level_for_xp(p_xp integer) returns integer
language plpgsql immutable set search_path = '' as $$
declare
    l integer := 1;
begin
    while p_xp >= 100 * l + 30 * l * (l - 1) loop
        l := l + 1;
    end loop;
    return l;
end $$;

create function private.grant_reward(p_owner text, p_xp integer) returns void
language plpgsql security definer set search_path = '' as $$
begin
    update public.profiles
       set xp       = xp + p_xp,
           currency = currency + p_xp / 4,
           level    = private.level_for_xp(xp + p_xp)
     where id = p_owner;
end $$;

create function private.award_card() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    perform private.grant_reward(new.owner_id, case new.rarity
        when 'Comune'      then 20
        when 'Rara'        then 55
        when 'Epica'       then 130
        when 'Leggendaria' then 260
        else 0 end);
    return null;
end $$;

-- Si fida del client sul completamento, ma: finestra di ±1 giorno (fusi orari),
-- massimo 3 riscatti al giorno, importo deciso dal server.
create function private.award_claim() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
    v_reward integer;
begin
    if new.day not between current_date - 1 and current_date + 1 then
        raise exception 'riscatto fuori finestra: %', new.day using errcode = 'P0001';
    end if;
    if (select count(*) from public.challenge_claims
         where owner_id = new.owner_id and day = new.day) > 3 then
        raise exception 'massimo 3 riscatti al giorno' using errcode = 'P0001';
    end if;
    select reward into v_reward from public.challenge_rewards
     where challenge_id = new.challenge_id;
    perform private.grant_reward(new.owner_id, v_reward);
    return null;
end $$;

revoke all on all functions in schema private from public, anon, authenticated;

create trigger cards_award after insert on public.cards
    for each row execute function private.award_card();
create trigger challenge_claims_award after insert on public.challenge_claims
    for each row execute function private.award_claim();

-- ---------------------------------------------------------------------------
-- 4. Storage: foto anonimizzate, solo il proprietario
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('spots', 'spots', false, 1048576, array['image/jpeg']);

create policy "spots: leggi le proprie" on storage.objects for select to authenticated
    using (bucket_id = 'spots'
           and (storage.foldername(name))[1] = ((select auth.jwt()) ->> 'sub'));
create policy "spots: carica le proprie" on storage.objects for insert to authenticated
    with check (bucket_id = 'spots'
                and (storage.foldername(name))[1] = ((select auth.jwt()) ->> 'sub'));
create policy "spots: elimina le proprie" on storage.objects for delete to authenticated
    using (bucket_id = 'spots'
           and (storage.foldername(name))[1] = ((select auth.jwt()) ->> 'sub'));
