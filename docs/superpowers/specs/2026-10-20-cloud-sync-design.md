# Sync cloud carte e profilo (SwiftData ↔ Supabase) — design

Data: 2026-10-20 · Stato: bozza da approvare (builder check fatto)

## Perché

Oggi carte e progressi vivono solo in SwiftData: se reinstalli o cambi telefono perdi tutto.
L'auth reale (Clerk → JWT → Supabase) è pronta, il DB ha già `public.cards` e `public.profiles`
con RLS per owner. Manca il collegamento.

**Priorità dell'utente:** poco carico sul server e caricamento veloce. Il telefono deve avere
una cache: l'app legge *sempre* da SwiftData (istantaneo) e sincronizza in background solo le
differenze. Mai "mille richieste".

## Obiettivi

1. Una carta salvata da un utente loggato finisce in `public.cards`, la sua foto anonimizzata nel
   bucket privato `spots`.
2. Dopo una reinstallazione, al login la collezione si ricarica dal cloud (le foto si scaricano
   solo quando servono e restano in cache).
3. XP, valuta e livello li assegna il server; il client non li può scrivere.
4. Build verde su simulatore iOS 27, advisor Supabase (security + performance) a zero.

## Non-obiettivi

- Modalità ospite: **eliminata** (decisione dell'utente: serve un account).
- Modifica/eliminazione carte: oggi non esistono nella UI → le carte sono *append-only*.
- Anti-cheat vero (verifica server della rarità): arriverà col riconoscimento lato server
  (`verified`). Qui il server si fida della rarità inviata, ma decide lui gli importi.
- Sync dello streak: resta locale per ora.
- Indicatore UI dello stato di sync, realtime/push tra dispositivi.

## Anti-obiettivi (sarebbe un fallimento anche se "funziona")

- La collezione aspetta la rete per mostrarsi.
- Riscaricare a ogni avvio carte o foto già in cache.
- Il client che scrive xp/level/currency, o chiavi/endpoint nelle view.
- Carte di due account mescolate sullo stesso telefono.

## Decisioni prese con l'utente

| Tema | Decisione |
|---|---|
| Ospite | Rimosso: niente "Continua senza account". |
| Logout / cambio account | Le carte dell'account (e il profilo locale) si tolgono dal telefono; al login si riscaricano. |
| Logout con dati in attesa | Prima si prova a inviarli; se restano carte/riscatti non inviati (offline) l'app chiede conferma ("Hai N carte non sincronizzate, uscendo le perdi"). Se la sessione scade da sola **non** si cancella nulla. |
| Carte già sul telefono (demo + catture col riconoscimento finto) | Cancellate al primo login dopo l'aggiornamento: dati di test, l'account riparte pulito. |
| Foto dopo reinstallazione | Download *lazy*: solo quando la carta appare a schermo, poi salvata in SwiftData (mai riscaricata). |
| Premi | Nessuna richiesta extra: li calcola il DB (vedi sotto). Cache locale obbligatoria. |

## Design

### Flusso dati

```
Salva carta ──► SwiftData (subito, UI aggiornata, XP ottimistici in locale)
                    │  syncState = pending
                    ▼
              upload foto (Storage) ──► insert riga (PostgREST, on conflict do nothing)
                    │                         │
                    │                    trigger DB: +xp/+currency/level sul profilo
                    ▼
              syncState = synced

Avvio app / login / ritorno in primo piano (max 1 volta ogni 15 min)
   1. ritenta le carte pending
   2. pull incrementale carte (solo righe nuove dal cursore)  ┐ in parallelo,
   3. pull profilo (xp, currency, level)                      │ 3 richieste leggere
   4. pull riscatti obiettivi recenti                          ┘
```

**Budget richieste:** avvio ≤ 3 GET piccole (di solito risposte vuote); cattura = 2 (upload +
insert); foto = 1 download per carta *nella vita dell'installazione*; riscatto obiettivo = 1 insert.

### Database (migration `0004_cloud_sync`)

- `cards`:
  - aggiungere `created_at timestamptz not null default now()` (impostato dal server, è il
    cursore del pull incrementale; `captured_at` resta quello del telefono) + indice
    `(owner_id, created_at)`.
  - `id` = UUID generato dal telefono (`StoredCard.id`): l'insert è idempotente
    (`on conflict (id) do nothing`), i retry non duplicano e il trigger non scatta due volte.
  - **Revocare `update`** al ruolo `authenticated` (carte immutabili). `delete` resta.
  - Grant di `insert` **per colonna** (tutte tranne `created_at`): il client non può falsare il
    cursore. `owner_id` resta inseribile ma la RLS impone `= sub`.
- `challenge_claims (owner_id text default sub, day date, challenge_id text, created_at)`,
  PK `(owner_id, day, challenge_id)`, FK verso `profiles`, RLS: select/insert solo propri.
- `challenge_rewards (challenge_id text pk, reward int)` — tabella di riferimento con gli
  importi (gli stessi di `ChallengeEngine`: today2 120, vintage 200, rarePlus 90, epic 160,
  trio 110, powerful 130). Leggibile, non scrivibile dal client.
- Trigger `AFTER INSERT` su `cards` e su `challenge_claims`, con funzioni `SECURITY DEFINER`
  nello schema **`private`** (non esposto da PostgREST → niente RPC chiamabili, niente lint):
  - carta: xp += reward per rarità (Comune 20, Rara 55, Epica 130, Leggendaria 260),
    currency += reward/4, `level` ricalcolato con la stessa curva di `LevelSystem`
    (step(l) = 100 + (l−1)·60).
  - riscatto: rifiuta se `day` non è entro ±1 giorno da oggi (fusi orari) o se ci sono già 3
    riscatti per quel giorno; importo da `challenge_rewards` (il client non manda numeri);
    xp += reward, currency += reward/4, level ricalcolato.
  - funzioni con `set search_path = ''`.
- Storage: bucket privato `spots` (limite 1 MB, solo `image/jpeg`). Path
  `<sub>/<card_id>.jpg`. Policy su `storage.objects` `to authenticated` con
  `bucket_id = 'spots' and (storage.foldername(name))[1] = (select auth.jwt()->>'sub')`
  per select, insert, delete. Niente update: un retry di un upload già riuscito dà
  "già esistente" e va trattato come successo.
- Il profilo deve esistere prima della prima carta (FK): il sync aspetta `ensureProfile`.
- File in `supabase/migrations/<versione>_0004_cloud_sync.sql` allineato a `list_migrations`;
  dopo il DDL `get_advisors` security + performance a zero.

### App (Swift)

**Modello locale** (migrazione leggera automatica, solo campi con default):
- `StoredCard`: `ownerId: String = ""`, `photoPath: String?`, `syncStateRaw: String = "pending"`
  (`pending` | `synced`).
- `PlayerProfile`: invariato nei campi; per gli utenti loggati xp/currency vengono sovrascritti
  dal server a ogni pull. `claimedChallenges` riempito anche dai riscatti scaricati.
- Foto: alla cattura si ridimensiona a lato lungo max 1280 px, JPEG 0.75 (~150–250 KB); lo
  stesso dato va in SwiftData e su Storage.

**Servizi** (convenzione: dipendenze esterne dietro protocollo):
- `CloudStore` (protocollo, `Sendable`, async): `upsertCard`, `uploadPhoto`, `downloadPhoto`,
  `fetchCards(since:)`, `fetchProfile`, `insertClaim`, `fetchClaims(since:)`. Impl
  `SupabaseCloudStore` sopra `SupabaseBackend.client` (mai `client.auth`).
- `SyncService` `@MainActor @Observable`, unico che scrive SwiftData per conto del cloud.
  Riceve `ModelContainer` + `CloudStore`. Operazioni: `didSave(card)`, `syncNow(reason)` (con
  throttle 15 min, ignorato se non `signedIn`), `loadPhotoIfNeeded(cardId)` (dedup delle
  richieste in volo, max 3 download contemporanei), `signedIn(userId)`, `signedOut()`.
- Cursore pull per utente in `UserDefaults` (chiave con l'id Clerk): `max(created_at)` visto,
  con 5 minuti di sovrapposizione; i duplicati si scartano per `id`. Paginazione 500 righe.
- Si sincronizzano solo utenti `signedIn` con `SupabaseBackend.shared` presente.

**Ciclo di vita** (in `RootGate.handle`, già punto unico per i cambi di auth):
- login → `ensureProfile` → `sync.signedIn(id)`: se le carte locali appartengono a un altro
  owner (o sono senza owner) si cancellano (con loro `PlayerProfile` e i riscatti in attesa),
  poi pull completo. Stesso owner (es. sessione scaduta e rientro) → si tiene tutto.
- logout **esplicito** (bottone in `ProfileView`, non il semplice cambio di stato in
  `RootGate`) → `sync.flushPending()`; se restano elementi in attesa → alert di conferma; poi
  `signOut` e cancellazione di `StoredCard`, `PlayerProfile` e cursore. Senza backend
  (`SupabaseBackend.shared == nil`, solo debug) non si cancella nulla.
- avvio e `scenePhase == .active` → `syncNow`. Il throttle di 15 min vale solo per i *pull*:
  il reinvio degli elementi in attesa avviene a ogni `syncNow` e a ogni nuova cattura (se non
  c'è nulla in attesa non parte nessuna richiesta).
- Ordine dentro `syncNow`: prima si inviano carte e riscatti in attesa, **poi** si scarica il
  profilo, così i valori del server includono già i premi ottimistici. Se l'invio fallisce si
  salta il pull del profilo (i valori locali ottimistici restano finché non va a buon fine).
- `CaptureViewModel.save` → dopo il salvataggio locale chiama `sync.didSave(card)`;
  `PlayerStore.award` resta come valore ottimistico locale (stessa tabella del server).
- `TodayView.claim` → locale come oggi + riscatto messo in coda (`pendingClaims` in
  `PlayerProfile`, chiavi `yyyy-MM-dd|id`) e inviato con `insertClaim` (PK duplicata = già
  fatto = successo).
- Collezione/dettaglio: `.task(id:)` sulla carta visibile → `loadPhotoIfNeeded`.

**Rimozione ospite:**
- Via il bottone "Continua senza account" da `LoginView` e l'evento analytics `guest`.
- `AuthState.guest` e `continueAsGuest` restano **solo per il debug `-skipAuth YES`**
  (screenshot su simulatore): in release lo stato ospite persistito diventa `signedOut`.
- `CardSeeder` (6 carte demo) gira solo nel percorso debug `-skipAuth`: gli account reali
  partono con la collezione vuota o con le loro carte cloud.

### Test

Swift Testing, `ModelContainer` in memoria + `FakeCloudStore`:
- salvataggio → upsert chiamato una volta, stato `synced`; errore → resta `pending`, ritentato
  al `syncNow` successivo.
- pull incrementale: nessun duplicato, cursore avanza; throttle rispettato.
- logout esplicito cancella le carte; login con altro owner cancella quelle del precedente;
  login con lo stesso owner le tiene.
- riscatto fallito resta in coda e il pull del profilo non sovrascrive i valori ottimistici.
- `loadPhotoIfNeeded` scarica una sola volta anche con chiamate concorrenti.
Verifica reale: login sul simulatore, cattura con `-autoCapture YES -autoSave YES`, riga in
`public.cards` + oggetto in `storage.objects`, profilo con xp aggiornati; reinstallazione →
collezione ricaricata.

## Decisioni mie (da controllare)

- Premi via trigger DB invece di RPC/Edge Function: zero richieste in più, atomico, niente
  funzioni esposte.
- Revoca dell'`update` sulle carte (append-only).
- Cap 3 riscatti/giorno e finestra ±1 giorno; nessun ricalcolo server dei progressi
  (si fida del client, come per la rarità).
- Migration applicata direttamente al progetto `rdezjqbxqekteextolvh` (unico, app non
  pubblicata, 0 carte nel DB).
- Coda dei riscatti in attesa in `PlayerProfile.pendingClaims`; profilo scaricato solo dopo
  aver svuotato le code.
- Throttle 15 min sul ritorno in primo piano; foto 1280 px / JPEG 0.75.
- Streak solo locale.

## Lasciato a chi implementa

Nomi dei tipi interni, struttura dei file in `Services/Sync/`, dettagli di paginazione e
logging (`Logger`), gestione degli errori di rete (retry semplice al prossimo `syncNow`,
niente backoff complicato).
