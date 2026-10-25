-- CarSpot — 0008: policy esplicita "nessun accesso" su private.recognition_usage.
-- La tabella è già inaccessibile ai client (schema non esposto, nessun grant); la policy
-- rende l'intento esplicito e silenzia l'advisor `rls_enabled_no_policy`.
-- La service role / la funzione security definer bypassano la RLS.

create policy "recognition_usage: nessun accesso client" on private.recognition_usage
    for all to anon, authenticated
    using (false) with check (false);
