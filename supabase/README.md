# CarSpot — Backend Supabase

Backend per riconoscimento, persistenza cloud, avvistamenti e territorio.
Finché `AppConfig.useRemoteRecognition == false` (default) il riconoscimento usa il mock e
l'app gira senza la Edge Function `recognize`. Auth utente = **Clerk** (third-party auth).

## Setup

1. Progetto remoto: `rdezjqbxqekteextolvh`. `Project URL` e publishable key
   (`sb_publishable_…`) stanno in `CarSpot/Services/Secrets.swift` (gitignored, letto da
   `AppConfig`); niente anon key.
2. Applica lo schema (le migration sono già allineate alla cronologia remota; la CLI non è
   installata, in questo progetto si applicano via MCP Supabase):
   ```bash
   supabase link --project-ref rdezjqbxqekteextolvh
   supabase db push          # esegue migrations/<versione>_*.sql
   ```
3. Configura i secret e fai il deploy della Edge Function `recognize`:
   ```bash
   supabase secrets set RECOGNITION_API_URL=https://api.carnet.ai/... \
                        RECOGNITION_API_KEY=***** \
                        CLERK_DOMAIN=<dominio Frontend API Clerk>
   supabase functions deploy recognize
   ```
   `CLERK_DOMAIN` è lo stesso di `[auth.third_party.clerk] domain` in `config.toml`; se manca
   la function usa il dominio dell'istanza di sviluppo, quindi **in produzione va impostato**.
   `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` sono già nell'env delle Edge Functions.
4. Attiva il riconoscimento reale: `AppConfig.useRemoteRecognition = true`.
5. Crea un bucket Storage privato `spots` per le foto anonimizzate.

## Sicurezza di `recognize`

`verify_jwt = false` in `config.toml` (la publishable key non è un JWT), ma la function
non è aperta: verifica da sé l'identità.

1. Solo `POST`.
2. `Authorization: Bearer <token Clerk>`: firma RS256 via JWKS di
   `https://<CLERK_DOMAIN>/.well-known/jwks.json`, `iss` ed `exp` controllati; l'utente è il
   `sub`. Assente o non valido → **401**. L'app chiede il token a ogni richiesta
   (`sessionToken()`, dura ~1 minuto) e invia anche `apikey` con la publishable key.
3. Corpo oltre 3 MB → **413**; JSON non valido o `imageBase64` mancante → **400**.
4. Rate limit per utente: `DAILY_LIMIT` (30/giorno UTC, costante in cima a `index.ts`),
   contatore atomico in `private.recognition_usage` tramite
   `public.consume_recognition_quota(user, limite)` (`security definer`, eseguibile solo dalla
   service role). Oltre il limite → **429**. Se il contatore è in errore la richiesta è
   rifiutata (fail closed). La quota si consuma anche se il provider poi fallisce.
5. Gli errori 500 sono generici verso il client; il dettaglio va in `console.error`
   (log della function).

Da provare dopo il deploy (sostituisci `<jwt>` con un token di sessione Clerk valido):
```bash
URL=https://rdezjqbxqekteextolvh.supabase.co/functions/v1/recognize
curl -s -o /dev/null -w "%{http_code}\n" -X POST $URL -d '{}'                                   # 401
curl -s -o /dev/null -w "%{http_code}\n" -X POST $URL -H "Authorization: Bearer x.y.z" -d '{}'   # 401
curl -s -o /dev/null -w "%{http_code}\n" -X POST $URL -H "Authorization: Bearer <jwt>" -d '{}'   # 400
curl -s -o /dev/null -w "%{http_code}\n" -X GET  $URL -H "Authorization: Bearer <jwt>"           # 405
```

## Contenuto

- `migrations/…_0002_clerk_postgis_cleanup.sql` — schema attuale: profili, carte, auto
  dei proprietari, quartieri (poligoni), avvistamenti (punto approssimato a livello di
  zona) e Row Level Security. Utente = **Clerk** (`auth.jwt()->>'sub'`, id `text`, niente
  FK verso `auth.users`, niente `auth.uid()`). PostGIS nello schema `extensions`. Niente
  accesso `anon`; xp/level/currency e `verified` non sono scrivibili dal client (li
  aggiornerà il backend con la service role).
- `migrations/…_0003_rls_initplan_form.sql` — policy nella forma `(select auth.jwt())`.
- `legacy/0001_init.sql` — schema originale (uuid + Supabase Auth), superato dalla 0002:
  non è nella cronologia remota, non va applicato.
- `migrations/…_0007_recognition_rate_limit.sql` (+ `0008`, policy deny-all) — contatore
  giornaliero per utente (`private.recognition_usage`) e `public.consume_recognition_quota`,
  usati da `recognize`.
- `functions/recognize/` — Edge Function che fa da proxy al provider di
  riconoscimento (la chiave API resta server-side) e normalizza la risposta nei
  `VehicleCandidate` attesi dall'app.

## Note privacy
- L'app invia **solo immagini già anonimizzate** (volti/targhe offuscati on-device).
- Gli avvistamenti memorizzano un punto **approssimato** (centroide di quartiere), mai
  la posizione reale: nessun pedinamento possibile.
- Le RLS garantiscono che ognuno veda solo le proprie carte/veicoli; il proprietario
  riceve gli avvistamenti che lo riguardano come notifiche.
