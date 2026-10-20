-- CarSpot — schema iniziale (Postgres + PostGIS)
-- Eseguito da `supabase db push` o dalla dashboard SQL editor.

create extension if not exists postgis;

-- ---------------------------------------------------------------------------
-- Profili utente (1:1 con auth.users)
-- ---------------------------------------------------------------------------
create table if not exists profiles (
    id          uuid primary key references auth.users on delete cascade,
    username    text unique not null,
    xp          integer not null default 0,
    level       integer not null default 1,
    currency    integer not null default 0,
    created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Carte collezionate (un avvistamento convalidato dall'utente)
-- ---------------------------------------------------------------------------
create table if not exists cards (
    id           uuid primary key default gen_random_uuid(),
    owner_id     uuid not null references profiles(id) on delete cascade,
    make         text not null,
    model        text not null,
    year         integer,
    rarity       text not null check (rarity in ('Comune','Rara','Epica','Leggendaria')),
    color_name   text,
    power        integer not null,
    agility      integer not null,
    presence     integer not null,
    photo_path   text,                       -- Storage path dell'immagine anonimizzata
    spotted_area text,                        -- solo etichetta di zona, mai coordinate precise
    captured_at  timestamptz not null default now()
);
create index if not exists cards_owner_idx on cards(owner_id);

-- ---------------------------------------------------------------------------
-- Auto registrate dai proprietari (la "scheda principale")
-- ---------------------------------------------------------------------------
create table if not exists owned_vehicles (
    id          uuid primary key default gen_random_uuid(),
    owner_id    uuid not null references profiles(id) on delete cascade,
    make        text not null,
    model       text not null,
    year        integer,
    verified    boolean not null default false,
    created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Quartieri (poligoni) per controllo territorio e classifiche
-- ---------------------------------------------------------------------------
create table if not exists neighborhoods (
    id     uuid primary key default gen_random_uuid(),
    name   text not null,
    area   geography(Polygon, 4326) not null
);
create index if not exists neighborhoods_area_idx on neighborhoods using gist(area);

-- ---------------------------------------------------------------------------
-- Avvistamenti: collegano chi scansiona con il proprietario.
-- La posizione è troncata a livello di quartiere (no pedinamento).
-- ---------------------------------------------------------------------------
create table if not exists sightings (
    id              uuid primary key default gen_random_uuid(),
    spotter_id      uuid not null references profiles(id) on delete cascade,
    owned_vehicle_id uuid references owned_vehicles(id) on delete set null,
    neighborhood_id uuid references neighborhoods(id) on delete set null,
    approx_point    geography(Point, 4326),   -- centroide di zona, non posizione reale
    reaction        text check (reaction in ('like','fire','eyes','flame')),
    created_at      timestamptz not null default now()
);
create index if not exists sightings_owner_idx on sightings(owned_vehicle_id);
create index if not exists sightings_point_idx on sightings using gist(approx_point);

-- ---------------------------------------------------------------------------
-- Classifica quartieri: chi ha più auto uniche per zona diventa Supervisore.
-- ---------------------------------------------------------------------------
create or replace view neighborhood_leaderboard as
select n.id as neighborhood_id, n.name, c.owner_id,
       count(distinct (c.make || c.model || coalesce(c.year::text,''))) as unique_spots
from cards c
join neighborhoods n
  on st_contains(n.area::geometry, st_point(0,0)::geometry) -- placeholder: join reale via sighting point
group by n.id, n.name, c.owner_id;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table profiles        enable row level security;
alter table cards           enable row level security;
alter table owned_vehicles  enable row level security;
alter table sightings       enable row level security;

create policy "profili: lettura pubblica"        on profiles for select using (true);
create policy "profili: aggiorna il proprio"     on profiles for update using (auth.uid() = id);

create policy "carte: solo le proprie"           on cards for all
    using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

create policy "veicoli: solo i propri"           on owned_vehicles for all
    using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- Lo spotter crea l'avvistamento; il proprietario lo legge come notifica.
create policy "avvistamenti: crea come spotter"  on sightings for insert
    with check (auth.uid() = spotter_id);
create policy "avvistamenti: leggi se coinvolto" on sightings for select
    using (
        auth.uid() = spotter_id
        or auth.uid() in (select owner_id from owned_vehicles where id = owned_vehicle_id)
    );
