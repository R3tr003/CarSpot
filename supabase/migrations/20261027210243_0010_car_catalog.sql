-- 0010 — Catalogo dei modelli (Marca → Modello → Versione) per la Collezione album.
-- Dati pubblici di riferimento, uguali per tutti: lettura per gli utenti autenticati, scrittura solo
-- dal service role (pipeline tools/catalog). Nessuna policy di insert/update/delete.
-- Le righe tolte restano con deleted_at (la sync dell'app per updated_at le vede).
-- ADR: docs/adr/0001-catalogo-modelli.md.

-- 1. updated_at automatico.
create function private.touch_updated_at() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
    new.updated_at := now();
    return new;
end $$;

-- 2. Marche.
create table public.car_makes (
    id          text primary key,
    name        text not null,
    country     text check (country is null or country ~ '^[A-Z]{2}$'),
    aliases     text[] not null default '{}',
    wikidata_id text,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    deleted_at  timestamptz
);

-- 3. Modelli (la casella dell'album).
create table public.car_models (
    id          text primary key,
    make_id     text not null references public.car_makes (id) on update cascade,
    name        text not null,
    body_type   text not null check (body_type in ('utilitaria', 'berlina', 'station_wagon', 'suv',
                    'monovolume', 'coupe', 'cabrio', 'sportiva', 'pickup', 'furgone')),
    year_start  smallint,
    year_end    smallint,
    popularity  integer not null default 0,
    aliases     text[] not null default '{}',
    wikidata_id text,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    deleted_at  timestamptz
);
create index car_models_make_id_idx on public.car_models (make_id);

-- 4. Versioni (la carta collezionabile dentro il modello), con immagine standard e attribuzione.
create table public.car_variants (
    id                text primary key,
    model_id          text not null references public.car_models (id) on update cascade,
    name              text not null,
    is_base           boolean not null default false,
    year_start        smallint,
    year_end          smallint,
    aliases           text[] not null default '{}',
    image_path        text,
    image_width       integer,
    image_height      integer,
    image_title       text,
    image_author      text,
    image_license     text,
    image_license_url text,
    image_source_url  text,
    image_modified    boolean not null default false,
    wikidata_id       text,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);
create index car_variants_model_id_idx on public.car_variants (model_id);

-- 5. Sync incrementale dell'app: righe cambiate dopo una data.
create index car_makes_updated_at_idx on public.car_makes (updated_at);
create index car_models_updated_at_idx on public.car_models (updated_at);
create index car_variants_updated_at_idx on public.car_variants (updated_at);

create trigger car_makes_touch before update on public.car_makes
    for each row execute function private.touch_updated_at();
create trigger car_models_touch before update on public.car_models
    for each row execute function private.touch_updated_at();
create trigger car_variants_touch before update on public.car_variants
    for each row execute function private.touch_updated_at();

-- 6. RLS: sola lettura per gli autenticati (utenti Clerk); niente anon.
alter table public.car_makes enable row level security;
alter table public.car_models enable row level security;
alter table public.car_variants enable row level security;

revoke all on public.car_makes, public.car_models, public.car_variants from anon;
revoke insert, update, delete, truncate on public.car_makes, public.car_models, public.car_variants
    from authenticated;
grant select on public.car_makes, public.car_models, public.car_variants to authenticated;

create policy "car_makes: lettura" on public.car_makes
    for select to authenticated using (true);
create policy "car_models: lettura" on public.car_models
    for select to authenticated using (true);
create policy "car_variants: lettura" on public.car_variants
    for select to authenticated using (true);

-- 7. Bucket pubblico delle immagini standard (contenuti con licenza libera, nessun dato utente).
--    Lettura via URL pubblico; nessuna policy di scrittura: carica solo il service role.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('car-models', 'car-models', true, 204800, array['image/webp']);
