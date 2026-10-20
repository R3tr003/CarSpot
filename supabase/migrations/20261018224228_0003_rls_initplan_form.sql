-- CarSpot — 0003: forma `(select auth.jwt()) ->> 'sub'` nelle policy (lint auth_rls_initplan).
-- Stessa semantica della 0002: il JWT viene valutato una volta per query, non per riga.

alter policy "profili: crea il proprio" on public.profiles
    with check (id = ((select auth.jwt()) ->> 'sub'));

alter policy "profili: aggiorna il proprio" on public.profiles
    using (id = ((select auth.jwt()) ->> 'sub'))
    with check (id = ((select auth.jwt()) ->> 'sub'));

alter policy "carte: leggi le proprie" on public.cards
    using (owner_id = ((select auth.jwt()) ->> 'sub'));

alter policy "carte: crea le proprie" on public.cards
    with check (owner_id = ((select auth.jwt()) ->> 'sub'));

alter policy "carte: aggiorna le proprie" on public.cards
    using (owner_id = ((select auth.jwt()) ->> 'sub'))
    with check (owner_id = ((select auth.jwt()) ->> 'sub'));

alter policy "carte: elimina le proprie" on public.cards
    using (owner_id = ((select auth.jwt()) ->> 'sub'));

alter policy "veicoli: leggi i propri" on public.owned_vehicles
    using (owner_id = ((select auth.jwt()) ->> 'sub'));

alter policy "veicoli: crea i propri" on public.owned_vehicles
    with check (owner_id = ((select auth.jwt()) ->> 'sub'));

alter policy "veicoli: aggiorna i propri" on public.owned_vehicles
    using (owner_id = ((select auth.jwt()) ->> 'sub'))
    with check (owner_id = ((select auth.jwt()) ->> 'sub'));

alter policy "veicoli: elimina i propri" on public.owned_vehicles
    using (owner_id = ((select auth.jwt()) ->> 'sub'));

alter policy "avvistamenti: crea come spotter" on public.sightings
    with check (spotter_id = ((select auth.jwt()) ->> 'sub'));

alter policy "avvistamenti: leggi se coinvolto" on public.sightings
    using (
        spotter_id = ((select auth.jwt()) ->> 'sub')
        or owned_vehicle_id in (
            select v.id from public.owned_vehicles v
            where v.owner_id = ((select auth.jwt()) ->> 'sub')
        )
    );
