-- CarSpot — 0007: rate limit per utente della Edge Function `recognize`.
--
-- * private.recognition_usage: contatore (utente, giorno UTC). Schema `private` NON esposto da
--   PostgREST; RLS attiva senza policy (nessun ruolo client la legge). user_id = sub di Clerk.
-- * public.consume_recognition_quota(user, limite): `security definer`, incrementa in modo
--   atomico (un solo upsert) e restituisce true se la richiesta è entro il limite. Sopra il
--   limite non incrementa più. È in `public` solo perché serve a supabase-js via rpc();
--   eseguibile ESCLUSIVAMENTE dalla service role (la chiama la Edge Function dopo aver
--   verificato il JWT Clerk). Mai da anon/authenticated.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.recognition_usage (
    user_id text not null,
    day     date not null,
    count   integer not null default 0,
    primary key (user_id, day)
);
alter table private.recognition_usage enable row level security;
revoke all on private.recognition_usage from public, anon, authenticated;

create or replace function public.consume_recognition_quota(p_user_id text, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_count integer;
begin
    if p_user_id is null or p_user_id = '' or p_limit is null or p_limit < 1 then
        return false;
    end if;

    -- Upsert atomico: la clausola where blocca l'incremento oltre il limite
    -- (in quel caso non viene restituita nessuna riga).
    insert into private.recognition_usage as u (user_id, day, count)
    values (p_user_id, (now() at time zone 'utc')::date, 1)
    on conflict (user_id, day)
    do update set count = u.count + 1
        where u.count < p_limit
    returning u.count into v_count;

    return v_count is not null;
end;
$$;

revoke all on function public.consume_recognition_quota(text, integer) from public, anon, authenticated;
grant execute on function public.consume_recognition_quota(text, integer) to service_role;
