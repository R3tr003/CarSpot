# Sync cloud carte e profilo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carte e progressi di un utente loggato persistono su Supabase (righe + foto) e si
ricaricano dopo una reinstallazione, con SwiftData come cache locale sempre letta per prima.

**Architecture:** DB: migration 0004 (colonna cursore, claims, trigger premi in schema
`private`, bucket `spots`). App: `CloudStore` (protocollo) + `SupabaseCloudStore`; `SyncService`
`@MainActor @Observable` unico scrittore di SwiftData per conto del cloud, iniettato via
`.environment`. Ospite rimosso dalla UI.

**Tech Stack:** SwiftUI iOS 26, Swift 6 strict, SwiftData, supabase-swift 2.55 (PostgREST +
Storage), Postgres 17 + RLS, MCP Supabase (ref `rdezjqbxqekteextolvh`).

**Spec:** `docs/superpowers/specs/2026-10-20-cloud-sync-design.md`

## Global Constraints

- Non editare `project.pbxproj` (synchronized root group). Il progetto **non ha un target di
  test**: la verifica è build + prova end-to-end sul simulatore + query SQL (aggiungere un
  target di test è un follow-up separato).
- `@MainActor` espliciti; tipi che attraversano isolation `Sendable`; `@Observable`; `Logger`
  (subsystem `com.carspot.andrea.app`, category `sync`), mai `print`.
- Mai `client.auth`; il token Clerk lo dà già `SupabaseBackend` (`accessToken`).
- Nessuna chiave/endpoint nelle view. Commenti in italiano brevi.
- Non toccare `CaptureView.swift` e `CameraController.swift` (li sta modificando un'altra sessione).
- Premi carta: Comune 20, Rara 55, Epica 130, Leggendaria 260 XP; currency = xp / 4.
- Premi obiettivi: today2 120, vintage 200, rarePlus 90, epic 160, trio 110, powerful 130.
- Curva livelli: step(l) = 100 + (l−1)·60 → xpToReach(L) = 100(L−1) + 30(L−1)(L−2).
- Path foto: `<clerk_user_id>/<card_uuid_lowercase>.jpg` nel bucket `spots`.
- Throttle pull: 15 min; sovrapposizione cursore: 5 min; pagina: 500 righe; max 3 download foto
  contemporanei. Foto: lato lungo max 1280 px, JPEG 0.75.

## Review Focus

1. Retry di una carta il cui insert era riuscito ma la risposta è andata persa → nessun
   duplicato e niente XP doppi (upsert `ignoreDuplicates` + trigger solo su insert reale).
2. Upload foto ripetuto dopo un successo → "already exists" trattato come successo.
3. Sessione Clerk scaduta (stato `signedOut` non richiesto dall'utente) → nessuna cancellazione
   locale; rientro con lo stesso id tiene tutto.
4. Pull del profilo mentre ci sono carte/riscatti in attesa → i valori locali ottimistici non
   vengono sovrascritti.
5. Prima apertura dopo l'aggiornamento con carte senza owner e profilo con XP vecchi → tutto
   azzerato prima del pull.

Ognuno è verificato nel Task 6 (scenari e2e/SQL).

---

### Task 1: Migration DB `0004_cloud_sync` (Opus — sessione principale)

**Files:**
- Create: `supabase/migrations/<versione>_0004_cloud_sync.sql` (versione = quella restituita
  da `list_migrations` dopo `apply_migration`)

**Produces (contratto per l'app):**
- `public.cards.created_at timestamptz not null default now()`, indice `(owner_id, created_at)`;
  `insert` concesso per colonna (tutte tranne `created_at`), `update` revocato.
- `public.challenge_claims(owner_id text default sub, day date, challenge_id text, created_at)`,
  PK `(owner_id, day, challenge_id)`; client: select + insert `(owner_id, day, challenge_id)`.
- `public.challenge_rewards(challenge_id text pk, reward int)`; client: select.
- `private.award_card()` / `private.award_claim()` trigger `SECURITY DEFINER`,
  `search_path = ''`; `private.level_for_xp(int) returns int`.
- Claim rifiutato (errore `P0001`) se `day` fuori da `current_date ± 1` o se già 3 claim nel giorno.
- Bucket `spots` privato, 1 MB, `image/jpeg`; policy select/insert/delete su `storage.objects`.

- [ ] Step 1: scrivere l'SQL, applicarlo con `apply_migration` (nome `0004_cloud_sync`), salvare
  il file con la versione di `list_migrations`.
- [ ] Step 2: test SQL in transazione con `rollback` (`set local role authenticated;
  set local request.jwt.claims = '{"sub":"<id profilo esistente>","role":"authenticated"}'`):
  insert carta Leggendaria → profilo +260 xp / +65 currency; stesso insert con
  `on conflict do nothing` → xp invariati; update carta → permission denied; claim `trio`
  oggi → +110; 4° claim → errore; claim con `day = current_date - 3` → errore; insert in
  `storage.objects` con path di un altro sub → negato.
- [ ] Step 3: `get_advisors` security e performance → nessun lint nuovo (target zero).

### Task 2: Modello locale + codifica foto (swift-implementer)

**Files:**
- Modify: `CarSpot/Persistence/StoredCard.swift`, `CarSpot/Persistence/PlayerProfile.swift`
- Create: `CarSpot/Services/Sync/PhotoEncoding.swift`
- Modify: `CarSpot/Features/Capture/CaptureViewModel.swift` (solo la riga `photo:`)

**Produces:**
- `StoredCard`: `var ownerId: String = ""`, `var photoPath: String?`,
  `var syncStateRaw: String = SyncState.pending.rawValue`, `var syncState: SyncState { get set }`;
  `enum SyncState: String, Sendable { case pending, synced }`.
- `PlayerProfile`: `var ownerId: String = ""`, `var pendingClaims: [String] = []`
  (chiavi `yyyy-MM-dd|challengeId`), `func resetForOwner(_ id: String)` (xp=0, currency=0,
  streak=1, claimed=[], pending=[], ownerId=id).
- `enum PhotoEncoding { static func jpeg(_ image: UIImage, maxSide: CGFloat = 1280, quality: CGFloat = 0.75) -> Data? }`
  (ridimensiona con `UIGraphicsImageRenderer` scale 1, mai ingrandisce).
- `CaptureViewModel.save`: `photo: anonymizedImage.flatMap { PhotoEncoding.jpeg($0) }`.

- [ ] Step 1: implementare; build verde (comando in CLAUDE.md).

### Task 3: `CloudStore` + `SupabaseCloudStore` (swift-implementer)

**Files:**
- Create: `CarSpot/Services/Sync/CloudStore.swift`, `CarSpot/Services/Sync/SupabaseCloudStore.swift`

**Consumes:** `SupabaseBackend.shared?.client`; schema del Task 1.

**Produces:**
```swift
struct CloudCard: Codable, Sendable {   // snake_case via CodingKeys
    let id: UUID; let ownerId: String; let make, model: String; let year: Int?
    let rarity: String; let colorName: String?; let power, agility, presence: Int
    let photoPath: String?; let spottedArea: String?; let capturedAt: Date
    let createdAt: Date?   // solo in lettura: escluso dall'encode
}
struct CloudProfile: Decodable, Sendable { let xp: Int; let currency: Int; let level: Int }
struct CloudClaim: Codable, Sendable { let day: String; let challengeId: String } // day "yyyy-MM-dd"

protocol CloudStore: Sendable {
    func insertCard(_ card: CloudCard) async throws            // upsert onConflict "id", ignoreDuplicates, returning .minimal
    func uploadPhoto(_ data: Data, path: String) async throws  // contentType image/jpeg, upsert false; "already exists"/409 = successo
    func downloadPhoto(path: String) async throws -> Data
    func fetchCards(createdAfter: Date?, offset: Int, limit: Int) async throws -> [CloudCard] // order created_at asc
    func fetchProfile(userId: String) async throws -> CloudProfile?
    func insertClaim(_ claim: CloudClaim) async throws         // PK duplicata (23505) = successo
    func fetchClaims(sinceDay: String) async throws -> [CloudClaim]
}
```
`SupabaseCloudStore` è `final class … : CloudStore` con `let client: SupabaseClient`
(`SupabaseClient` è `Sendable`); bucket `"spots"`. Per l'encode di `CloudCard` omettere
`created_at` (encode custom). `year == nil` quando il locale è 0.

- [ ] Step 1: implementare; build verde.

### Task 4: `SyncService` (swift-implementer)

**Files:**
- Create: `CarSpot/Services/Sync/SyncService.swift`

**Consumes:** Task 2 (modelli), Task 3 (`CloudStore`).

**Produces:**
```swift
@MainActor @Observable
final class SyncService {
    init(container: ModelContainer, store: (any CloudStore)?)   // store nil = sync spento
    static var shared: SyncService?   // impostato da CarSpotApp.init; usato solo da CaptureViewModel
    private(set) var userId: String?
    func signedIn(userId: String) async      // wipe se owner diverso, poi syncNow(force: true)
    func syncNow(force: Bool = false) async   // push code → (throttle) pull carte + profilo + claim
    func didSave(_ card: StoredCard) async    // assegna ownerId, poi pushPending
    func didClaim(key: String) async          // accoda in pendingClaims, poi pushPending
    func flushPending() async -> Int          // ritorna carte+claim ancora in attesa
    func signedOutExplicitly()                // cancella StoredCard, resetForOwner(""), cursore in memoria; userId = nil
    func loadPhotoIfNeeded(cardId: UUID) async
}
```
Comportamento (dalla spec):
- Nessuna operazione se `store == nil` o `userId == nil`.
- `signedIn`: se `PlayerProfile.ownerId != userId` o esistono `StoredCard` con `ownerId != userId`
  → cancella quelle carte e `resetForOwner(userId)`.
- `pushPending`: per ogni carta `pending` dell'utente: se `photo != nil && photoPath == nil`
  → upload a `"\(userId)/\(id.uuidString.lowercased()).jpg"`, poi `photoPath = path`;
  `insertCard`; `syncState = .synced`; `save()`. Poi `pendingClaims` → `insertClaim` e rimozione
  dalla coda. Errore → log e stop (si ritenta al prossimo `syncNow`/cattura).
- Pull (saltato se non `force` e ultimo pull < 15 min fa): cursore `UserDefaults`
  `"sync.cursor.\(userId)"` (Date); `fetchCards(createdAfter: cursor − 5 min)` a pagine da 500,
  inserisce solo gli `id` assenti (`syncState = .synced`, `photo = nil`), aggiorna il cursore a
  `max(createdAt)`. Profilo: **solo se non restano elementi in attesa**, `xp`/`currency` dal
  server. Claim: `fetchClaims(sinceDay: ieri)` → unione in `claimedChallenges`.
- Un solo sync alla volta (flag `isSyncing`; chiamate concorrenti ritornano subito).
- `loadPhotoIfNeeded`: carta con `photo == nil && photoPath != nil`, non già in volo
  (`Set<UUID>`), max 3 in volo (attesa cooperativa che rispetta la cancellazione) →
  `downloadPhoto` → `photo = data`, `save()`. Errori solo loggati.

- [ ] Step 1: implementare; build verde.

### Task 5: Collegamenti UI + rimozione ospite (swift-implementer)

**Files:**
- Modify: `CarSpot/App/CarSpotApp.swift` — crea `SyncService(container:store:)` con
  `SupabaseBackend.shared.map { SupabaseCloudStore(client: $0.client) }`; `SyncService.shared = sync`;
  `.environment(sync)`;
  `CardSeeder.seedIfNeeded` **non** più chiamato qui.
- Modify: `CarSpot/Features/Root/RootGate.swift` — in `.signedIn`: `Task { try? await
  backend.ensureProfile(userId: id); await sync.signedIn(userId: id) }`; `scenePhase == .active`
  → `Task { await sync.syncNow() }`; nel ramo debug `skipAuth` → `CardSeeder.seedIfNeeded(context)`.
- Modify: `CarSpot/Features/Capture/CaptureViewModel.swift` — firma `save(into:)` invariata
  (così `CaptureView.swift` non si tocca): dopo il salvataggio locale
  `if let sync = SyncService.shared { Task { await sync.didSave(card) } }`.
- Modify: `CarSpot/Features/Today/TodayView.swift` — dopo `PlayerStore.claim` riuscito:
  `Task { await sync.didClaim(key: "\(PlayerProfile.dayKey())|\(challenge.id)") }`.
- Modify: `CarSpot/Features/Collection/CollectionView.swift` — su ogni `SpotCardView` della
  griglia `.task(id: card.id) { await sync.loadPhotoIfNeeded(cardId: card.id) }`.
- Modify: `CarSpot/Features/Profile/ProfileView.swift` — logout: `let left = await
  sync.flushPending()`; se `left > 0` alert titolo `"Dati non sincronizzati"`, messaggio
  `"Hai \(left) elementi non ancora salvati nel cloud. Se esci ora li perdi."`, bottoni
  `"Esci comunque"` (destructive) / `"Annulla"`; poi `try await auth.signOut()` e
  `sync.signedOutExplicitly()`.
- Modify: `CarSpot/Features/Onboarding/LoginView.swift` — rimuovere il bottone
  "Continua senza account".
- Modify: `CarSpot/Services/Auth/ClerkAuthService.swift`, `AuthFactory.swift`,
  `AuthService.swift` — ospite solo in memoria (non più persistito; rimuovere la chiave
  `clerkGuestMode` da `UserDefaults` all'avvio; `LocalAuthService` mappa il vecchio `"guest"` a
  `signedOut`); doc: `.guest`/`continueAsGuest` = solo debug `-skipAuth`.
- Modify: `CarSpot/Services/Analytics/Analytics.swift` — commento `signedIn(method:)` senza "guest".

- [ ] Step 1: implementare; build verde; `grep -rn "Continua senza account" CarSpot` vuoto.

### Task 6: Verifica end-to-end (Opus)

- [ ] Build verde (CLAUDE.md), install + launch sul simulatore iOS 27.
- [ ] Login Google sul simulatore (lo fa l'utente: password non inseribili dall'agente).
- [ ] Al login le carte demo/locali spariscono e il profilo locale si azzera (Review Focus 5).
- [ ] Cattura con `-autoCapture YES -autoSave YES` → riga in `public.cards` con `photo_path`,
  oggetto in `storage.objects`, profilo +xp (SQL via MCP).
- [ ] Rilancio senza rete non necessario: verificare nei log `sync` che il secondo avvio entro
  15 min non faccia pull (throttle) e che le pending vengano ritentate.
- [ ] Reinstallazione (`simctl uninstall` + `install`): la sessione Clerk resta in Keychain →
  collezione ricaricata; le foto compaiono scorrendo (download lazy, una volta sola).
- [ ] `get_advisors` security + performance: zero.
- [ ] Aggiornare CLAUDE.md (Stato, Gate iniziale senza ospite, sync) — non committare senza
  richiesta.
