-- CarSpot — 0006: immagine profilo (avatar).
--
-- * profiles.avatar_path: percorso nel bucket `avatars` ("<id>/avatar.jpg"), null = nessuna foto.
--   Il check impedisce di puntare al file di un altro utente.
-- * profiles.avatar_updated_at: versione per invalidare la cache dell'app. Null = mai toccato:
--   l'app importa la foto dell'account (Google) solo in quel caso.
-- * Bucket `avatars` PRIVATO (regola del progetto: niente accesso anon; un avatar è spesso un
--   volto). Lo legge qualunque utente loggato (classifiche); ognuno scrive solo il proprio
--   "<sub>/avatar.jpg". 200 KB max, solo JPEG (l'app invia ~512 px, < 100 KB).

alter table public.profiles add column if not exists avatar_path text;
alter table public.profiles add column if not exists avatar_updated_at timestamptz;

alter table public.profiles drop constraint if exists profiles_avatar_path_own;
alter table public.profiles
    add constraint profiles_avatar_path_own
    check (avatar_path is null or avatar_path = id || '/avatar.jpg');

grant update (avatar_path, avatar_updated_at) on public.profiles to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 204800, array['image/jpeg'])
on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "avatars: lettura" on storage.objects;
create policy "avatars: lettura" on storage.objects
    for select to authenticated
    using (bucket_id = 'avatars');

drop policy if exists "avatars: carica il proprio" on storage.objects;
create policy "avatars: carica il proprio" on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = (select auth.jwt() ->> 'sub')
        and storage.filename(name) = 'avatar.jpg'
    );

-- L'upsert dell'app (stesso percorso) passa da UPDATE.
drop policy if exists "avatars: aggiorna il proprio" on storage.objects;
create policy "avatars: aggiorna il proprio" on storage.objects
    for update to authenticated
    using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = (select auth.jwt() ->> 'sub')
    )
    with check (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = (select auth.jwt() ->> 'sub')
        and storage.filename(name) = 'avatar.jpg'
    );

drop policy if exists "avatars: elimina il proprio" on storage.objects;
create policy "avatars: elimina il proprio" on storage.objects
    for delete to authenticated
    using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = (select auth.jwt() ->> 'sub')
    );
