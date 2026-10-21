-- CarSpot — 0005: onboarding del profilo dopo la registrazione.
--
-- * onboarded_at: null finché l'utente non ha scelto il nome da spotter e visto i
--   permessi; l'app mostra il setup solo in quel caso (anche dopo reinstallazione).
-- * username: formato unico per classifiche e ricerca (minuscole, cifre, _ e .,
--   3–20 caratteri). Il default "spotter_xxxxxx" creato al primo login è conforme.
-- * Il client può aggiornare solo username e onboarded_at del proprio profilo
--   (la policy "profili: aggiorna il proprio" limita già le righe).

alter table public.profiles add column if not exists onboarded_at timestamptz;

alter table public.profiles drop constraint if exists profiles_username_check;
alter table public.profiles
    add constraint profiles_username_format check (username ~ '^[a-z0-9_.]{3,20}$');

grant update (onboarded_at) on public.profiles to authenticated;
