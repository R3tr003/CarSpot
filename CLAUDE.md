# CLAUDE.md — CarSpot

App iOS nativa (SwiftUI · iOS 26 · Swift 6) che trasforma il car spotting reale in un
gioco di carte collezionabili. Concept e roadmap: [PROGETTO.md](PROGETTO.md). Stato e
storico: [docs/agents/status.md](docs/agents/status.md).

## Build e verifica

Progetto Xcode con **synchronized root group**: i file dentro `CarSpot/` e `CarSpotTests/`
entrano da soli nei target — **non editare `project.pbxproj`** per aggiungere/spostare file.

```bash
# Verifica (unica permessa): compila app + test, senza simulatore né installazione
xcodebuild -project CarSpot.xcodeproj -scheme CarSpot -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  build-for-testing 2>&1 | grep -E "error:|TEST BUILD SUCCEEDED|BUILD FAILED"
```

- **L'utente prova tutto sul suo iPhone e installa da Xcode.** Niente simulatori (neanche
  per `xcodebuild test`: accenderli blocca il suo Xcode), niente install/launch. Finito un
  lavoro: build verde → riepilogo con cosa provare sul telefono.
- Sessioni parallele: nella **stessa cartella** (niente worktree), ognuna sui suoi file,
  con `-derivedDataPath` proprio, senza commit (li fa la sessione principale).

### Gotcha verificati
- **Bundle id = `com.carspot.andrea.app`** (Personal Team). `com.carspot.app` è di un altro
  team Apple: non cambiarlo senza chiedere (va aggiornato anche nei Native applications di
  Clerk). Leggilo da `PRODUCT_BUNDLE_IDENTIFIER`; mai `uninstall`/`erase` per "riparare".
- **Run da Xcode che compila ma non avvia:** il target deve avere `productReference` →
  `CarSpot.app` e lo schema condiviso un `BuildableProductRunnable` con
  `BuildableName = "CarSpot.app"` (sistemato il 2026-10-20).
- **Personal Team gratuito:** niente Sign in with Apple, Push/APNs, Associated Domains.
  Aggiungerle rompe il provisioning: fino all'Apple Developer Program nessun
  `CODE_SIGN_ENTITLEMENTS` con quelle capability.
- **Xcode fermo su "Preparing Editor Functionality"** o `simctl` che non risponde:
  CoreSimulator appeso → `killall -9 com.apple.CoreSimulator.CoreSimulatorService`, poi
  `xcrun simctl shutdown all`. Non cancella nulla; mai `erase`.
- **Naming:** niente tipi propri chiamati `Tab` (collide con `SwiftUI.Tab`).
- **Launch arguments di debug:** `-skipAuth YES` (salta onboarding+login, ospite),
  `-showLogin YES`, `-resetAuth YES`, `-startTab today|collection|capture|map|profile`,
  `-autoCapture YES` (+ `-autoSave YES`) per la pipeline con immagine sintetica.

## Architettura e convenzioni

- **Dipendenze esterne dietro protocollo**, con implementazione `Mock`/locale (default,
  offline) e remota (Supabase) scelta in `AppConfig`. Niente endpoint o chiavi nelle view.
- **Niente chiavi API nell'app:** il riconoscimento passa SEMPRE dalla Edge Function
  `recognize` (cartella `supabase/`), che riceve solo l'immagine già anonimizzata.
- **Privacy:** volti e targhe sfocati **on-device** (Vision) PRIMA di qualsiasi invio o
  salvataggio, fail-closed. Al cloud va solo l'area/quartiere, mai coordinate.
- **Concurrency:** Swift 6 strict, **senza** Default Actor Isolation = MainActor: i
  `@MainActor` sono espliciti (non cambiare il build setting senza chiedere). Tipi che
  attraversano isolation `Sendable`, servizi `async`, UI `@MainActor`, `@Observable`.
  Lavoro CPU pesante → `@concurrent`.
- **Persistenza:** SwiftData (`@Model`), le view leggono via `@Query`; sync con Supabase in
  `SyncService` (campi nuovi con default: migrazione leggera).
- **DB Supabase** (ref `rdezjqbxqekteextolvh`, via MCP; CLI non installata): utenti =
  **Clerk** third-party auth → id `text` = `auth.jwt()->>'sub'` (MAI `auth.uid()`, niente
  FK verso `auth.users`). Policy `to authenticated` + `((select auth.jwt()) ->> 'sub')`,
  niente `anon`; colonne di gioco (xp, livello, valuta, `is_repeat` a true) decise dal
  server con trigger. PostGIS nello schema `extensions`. Dopo ogni DDL `get_advisors`
  security + performance; migration in `supabase/migrations/<versione>_<nome>.sql`
  allineate alla cronologia remota.
- **Regole di gioco gemelle client/server:** XP dei doppioni e "stessa auto" vivono in
  `CardCopies` (Swift) e nei trigger `private.award_card` / `private.mark_repeat`:
  si cambiano sempre in coppia.
- **Test:** Swift Testing (`@Test`, `#expect`, `try #require`) in `CarSpotTests/`; XCTest
  solo per UI test. **Logging:** `Logger` di `os`. **Commenti:** in italiano, brevi.
- **Stringhe:** chiavi italiane nel catalogo `Localizable.xcstrings` con traduzione `en`;
  le aggiunge la sessione principale a fine lavoro.
- Struttura di auth/onboarding, servizi esterni (Clerk, Supabase, Mixpanel, Sentry) e
  guscio a tab: [docs/agents/app-structure.md](docs/agents/app-structure.md). Leggilo
  prima di toccare `RootGate`, `RootShellView`, `AppServices` o l'onboarding.

### Guscio (sintesi)
Mappa unica alla radice (`MapHost`) + pannello di sistema `.sheet` sempre presentato con
dentro la **`TabView` nativa** (Liquid Glass autentico: non sostituirla). Tab Oggi,
Collezione, Mappa + Cattura (`role: .search`): la tab Cattura mostra la cronologia e il
tocco apre `CaptureView` in `fullScreenCover`. Profilo dall'avatar dello `SheetHeader`.

## Design system — usalo, non reinventare

Tutto in `CarSpot/DesignSystem/`, regole e motion in [DESIGN.md](DESIGN.md). Nelle
feature niente colori/spaziature hardcoded:
- Colori `CSColor` · font `CSFont` (Dynamic Type; mai `.system(size:)` per testo) +
  `.eyebrow()` · spaziature `CSSpace` / `CSRadius` / `CSSize.minTap` (44).
- Blocchi di contenuto → **`Surface(.hero | .group)`**, `SurfaceDivider`, `KPIStrip`
  (superfici a gradini). Liquid Glass nativo solo su controlli e sopra foto/mappa
  (`GlassPanel`, `.glassEffect`).
- Rarità → `Rarity.color` (un colore) + `Rarity.finish` (materiale). Il colore di rarità
  solo su carte, badge e dati di rarità.
- Pulsanti custom → `.buttonStyle(CSPressStyle())`. Componenti: `SpotCardView`,
  `RarityBadge`, `StatBar`, `PrimaryButton`/`GhostButton`, `CardRevealView`.
- Motion: un solo momento "rumoroso" (il reveal); altrove solo feedback. Reduce Motion
  sempre rispettato.

**Il brief di CarSpot vince sulle skill generiche** (le carte collezionabili SONO il
prodotto, il vetro è quello nativo). L'utente boccia l'"AI slop": aloni colorati,
arcobaleni, bordi neon, numeri che rotolano, card identiche in fila. Non cambiare UI non
richiesta.

## Skill e subagent

- Prima di agire, se la situazione corrisponde, chiama la skill giusta: mappa completa
  (Swift, processo, design, motion, Supabase, web-only da evitare) in
  [docs/agents/skills.md](docs/agents/skills.md).
- Opus decide, progetta, verifica e scrive CLAUDE.md; il lavoro ripetitivo va a subagent
  economici in parallelo. **Sonnet:** `swift-implementer`, `ui-reviewer`,
  `impeccable-finish-reviewer`, `impeccable-documenter`. **Haiku:** `ios-scout`,
  `build-checker`, `researcher`.
- Brief autosufficienti (file, obiettivo, vincoli, "fatto" = ?); writer mai sugli stessi
  file. Il report di un subagent non è una prova: ricontrolla diff e build.
