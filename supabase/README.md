# CarSpot — Backend Supabase

Backend per riconoscimento, persistenza cloud, avvistamenti e territorio.
Finché `AppConfig.recognitionMode == .mock`, l'app gira senza questo backend.

## Setup

1. Crea un progetto su [supabase.com](https://supabase.com) e prendi `Project URL` e
   `anon key` (Settings → API).
2. Inseriscili in `CarSpot/Services/AppConfig.swift` e imposta `recognitionMode = .remote`.
3. Applica lo schema:
   ```bash
   supabase link --project-ref <ref>
   supabase db push          # esegue migrations/0001_init.sql
   ```
4. Configura il provider di riconoscimento e fai il deploy della Edge Function:
   ```bash
   supabase secrets set RECOGNITION_API_URL=https://api.carnet.ai/... \
                        RECOGNITION_API_KEY=*****
   supabase functions deploy recognize
   ```
5. Crea un bucket Storage privato `spots` per le foto anonimizzate.

## Contenuto

- `migrations/0001_init.sql` — schema con **PostGIS**: profili, carte, auto dei
  proprietari, quartieri (poligoni), avvistamenti (punto approssimato a livello di
  zona), vista classifica, e Row Level Security.
- `functions/recognize/` — Edge Function che fa da proxy al provider di
  riconoscimento (la chiave API resta server-side) e normalizza la risposta nei
  `VehicleCandidate` attesi dall'app.

## Note privacy
- L'app invia **solo immagini già anonimizzate** (volti/targhe offuscati on-device).
- Gli avvistamenti memorizzano un punto **approssimato** (centroide di quartiere), mai
  la posizione reale: nessun pedinamento possibile.
- Le RLS garantiscono che ognuno veda solo le proprie carte/veicoli; il proprietario
  riceve gli avvistamenti che lo riguardano come notifiche.
