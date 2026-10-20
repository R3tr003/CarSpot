-- CarSpot — 0002: auth Clerk (third-party) + PostGIS fuori da public + RLS rifatta.
--
-- Perché:
--   * Clerk emette JWT con `sub` = "user_xxx" (text, non uuid) e non crea righe in
--     auth.users → id utente = auth.jwt()->>'sub', niente FK verso auth.users,
--     niente auth.uid() (fa il cast a uuid e fallisce).
--   * PostGIS in `public` esponeva spatial_ref_sys senza RLS e funzioni
--     SECURITY DEFINER via /rest/v1/rpc (advisor ERROR/WARN).
--   * Policy con `(select ...)` per evitare la rivalutazione per riga, `to authenticated`,
--     UPDATE con USING + WITH CHECK, indici sulle FK.
--
-- Il DB era vuoto (0 righe nelle tabelle dell'app): le tabelle vengono ricreate.

-- ---------------------------------------------------------------------------
-- 1. Via lo schema 0001 e PostGIS da public
-- ---------------------------------------------------------------------------
drop view  if exists public.neighborhood_leaderboard;  -- era un placeholder con join fittizio
drop table if exists public.sightings, public.owned_vehicles, public.cards,
                     public.neighborhoods, public.profiles cascade;

drop extension if exists postgis;
create schema if not exists extensions;
create extension postgis with schema extensions;

-- ---------------------------------------------------------------------------
-- 2. Tabelle (id utente = Clerk user id, text)
-- ---------------------------------------------------------------------------
create table public.profiles (
    id          text primary key default (auth.jwt() ->> 'sub'),
    username    text unique not null check (char_length(username) between 3 and 30),
    xp          integer not null default 0,
    level       integer not null default 1,
    currency    integer not null default 0,
    created_at  timestamptz not null default now()
);

create table public.cards (
    id           uuid primary key default gen_random_uuid(),
    owner_id     text not null default (auth.jwt() ->> 'sub')
                 references public.profiles(id) on delete cascade,
    make         text not null,
    model        text not null,
    year         integer,
    rarity       text not null check (rarity in ('Comune','Rara','Epica','Leggendaria')),
    color_name   text,
    power        integer not null,
    agility      integer not null,
    presence     integer not null,
    photo_path   text,                        -- Storage path dell'immagine anonimizzata
    spotted_area text,                        -- solo etichetta di zona, mai coordinate precise
    captured_at  timestamptz not null default now()
);
create index cards_owner_idx on public.cards(owner_id);

create table public.owned_vehicles (
    id          uuid primary key default gen_random_uuid(),
    owner_id    text not null default (auth.jwt() ->> 'sub')
                references public.profiles(id) on delete cascade,
    make        text not null,
    model       text not null,
    year        integer,
    verified    boolean not null default false,  -- lo imposta solo il backend
    created_at  timestamptz not null default now()
);
create index owned_vehicles_owner_idx on public.owned_vehicles(owner_id);

create table public.neighborhoods (
    id     uuid primary key default gen_random_uuid(),
    name   text not null,
    area   extensions.geography(Polygon, 4326) not null
);
create index neighborhoods_area_idx on public.neighborhoods using gist(area);

-- Avvistamenti: collegano chi scansiona con il proprietario.
-- La posizione è troncata a livello di quartiere (no pedinamento).
create table public.sightings (
    id               uuid primary key default gen_random_uuid(),
    spotter_id       text not null default (auth.jwt() ->> 'sub')
                     references public.profiles(id) on delete cascade,
    owned_vehicle_id uuid references public.owned_vehicles(id) on delete set null,
    neighborhood_id  uuid references public.neighborhoods(id) on delete set null,
    approx_point     extensions.geography(Point, 4326),   -- centroide di zona, non posizione reale
    reaction         text check (reaction in ('like','fire','eyes','flame')),
    created_at       timestamptz not null default now()
);
create index sightings_spotter_idx      on public.sightings(spotter_id);
create index sightings_vehicle_idx      on public.sightings(owned_vehicle_id);
create index sightings_neighborhood_idx on public.sightings(neighborhood_id);
create index sightings_point_idx        on public.sightings using gist(approx_point);

-- ---------------------------------------------------------------------------
-- 3. Privilegi: l'app è sempre loggata → niente accesso anon.
--    Le colonne di gioco (xp/level/currency, verified) non sono scrivibili dal client:
--    le aggiornerà il backend (Edge Function anti-cheat) con la service role.
-- ---------------------------------------------------------------------------
revoke all on public.profiles, public.cards, public.owned_vehicles,
              public.neighborhoods, public.sightings from anon, authenticated;

grant select                 on public.profiles to authenticated;
grant insert (id, username)  on public.profiles to authenticated;
grant update (username)      on public.profiles to authenticated;

grant select, insert, update, delete on public.cards to authenticated;

grant select, delete                     on public.owned_vehicles to authenticated;
grant insert (owner_id, make, model, year) on public.owned_vehicles to authenticated;
grant update (make, model, year)          on public.owned_vehicles to authenticated;

grant select on public.neighborhoods to authenticated;

grant select on public.sightings to authenticated;
grant insert (spotter_id, owned_vehicle_id, neighborhood_id, approx_point)
      on public.sightings to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles        enable row level security;
alter table public.cards           enable row level security;
alter table public.owned_vehicles  enable row level security;
alter table public.neighborhoods   enable row level security;
alter table public.sightings       enable row level security;

-- Profili: leggibili da tutti i loggati (classifiche), ognuno crea/modifica il proprio.
create policy "profili: lettura" on public.profiles for select to authenticated
    using (true);
create policy "profili: crea il proprio" on public.profiles for insert to authenticated
    with check (id = (select auth.jwt() ->> 'sub'));
create policy "profili: aggiorna il proprio" on public.profiles for update to authenticated
    using (id = (select auth.jwt() ->> 'sub'))
    with check (id = (select auth.jwt() ->> 'sub'));

-- Carte: solo le proprie.
create policy "carte: leggi le proprie" on public.cards for select to authenticated
    using (owner_id = (select auth.jwt() ->> 'sub'));
create policy "carte: crea le proprie" on public.cards for insert to authenticated
    with check (owner_id = (select auth.jwt() ->> 'sub'));
create policy "carte: aggiorna le proprie" on public.cards for update to authenticated
    using (owner_id = (select auth.jwt() ->> 'sub'))
    with check (owner_id = (select auth.jwt() ->> 'sub'));
create policy "carte: elimina le proprie" on public.cards for delete to authenticated
    using (owner_id = (select auth.jwt() ->> 'sub'));

-- Veicoli registrati: solo i propri.
create policy "veicoli: leggi i propri" on public.owned_vehicles for select to authenticated
    using (owner_id = (select auth.jwt() ->> 'sub'));
create policy "veicoli: crea i propri" on public.owned_vehicles for insert to authenticated
    with check (owner_id = (select auth.jwt() ->> 'sub'));
create policy "veicoli: aggiorna i propri" on public.owned_vehicles for update to authenticated
    using (owner_id = (select auth.jwt() ->> 'sub'))
    with check (owner_id = (select auth.jwt() ->> 'sub'));
create policy "veicoli: elimina i propri" on public.owned_vehicles for delete to authenticated
    using (owner_id = (select auth.jwt() ->> 'sub'));

-- Quartieri: dati di riferimento, sola lettura (li scrive il backend).
create policy "quartieri: lettura" on public.neighborhoods for select to authenticated
    using (true);

-- Avvistamenti: lo spotter li crea; li leggono spotter e proprietario dell'auto.
create policy "avvistamenti: crea come spotter" on public.sightings for insert to authenticated
    with check (spotter_id = (select auth.jwt() ->> 'sub'));
create policy "avvistamenti: leggi se coinvolto" on public.sightings for select to authenticated
    using (
        spotter_id = (select auth.jwt() ->> 'sub')
        or owned_vehicle_id in (
            select v.id from public.owned_vehicles v
            where v.owner_id = (select auth.jwt() ->> 'sub')
        )
    );
