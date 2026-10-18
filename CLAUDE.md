# CLAUDE.md — CarSpot

App iOS nativa (SwiftUI · iOS 26 · Swift 6) che trasforma il car spotting reale in un
gioco di carte collezionabili. Vedi [PROGETTO.md](PROGETTO.md) per concept e roadmap.

## Build / Run / Verify

Progetto Xcode con **synchronized root group**: i file dentro `CarSpot/` vengono inclusi
automaticamente nel target — **non serve (e non si deve) editare `project.pbxproj`** per
aggiungere/rinominare/spostare file Swift.

```bash
# Build (simulatore iOS 26)
xcodebuild -project CarSpot.xcodeproj -scheme CarSpot -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

# Install + launch
APP=$(find build/Build/Products -name CarSpot.app -maxdepth 3 | head -1)
xcrun simctl install booted "$APP" && xcrun simctl launch booted com.carspot.andrea.app

# Screenshot
xcrun simctl io booted screenshot shot.png
```

Preferire i tool **XcodeBuildMCP** quando disponibili (`build_run_sim`, `snapshot_ui`).
L'automazione UI a tap di XcodeBuildMCP **non è abilitata** in questa configurazione.

### Gotcha verificati (non ripeterli)
- **Bundle id = `com.carspot.andrea.app`** (NON `com.carspot.app`). Usare l'id sbagliato
  con `simctl launch` dà `FBSOpenApplicationServiceErrorDomain code=4` e con `uninstall`
  rimuove l'app vera: non fare `uninstall`/`erase` per "riparare" — ricontrolla l'id.
- **Rilancio:** `simctl launch` su app già in foreground NON rilancia. `simctl terminate`
  PRIMA di `launch` quando serve rivedere lo stato iniziale.
- **Dopo `simctl erase`:** la cache tile di MapKit è azzerata e GeoServices può non avere
  rete per un po' (`geod: TMGetReferenceTime reliable -1`): lo sfondo mappa resta NERO
  finché i tile non si scaricano. Non è un bug del codice — evitare `erase`.
- **Debug auth:** `-skipAuth YES` salta onboarding+login → app; `-showLogin YES` va al
  login; `-resetAuth YES` riazzera i flag (`hasOnboarded`/`isSignedIn` in `RootGate`).
- **Schermo nero al launch:** se lanci con `--console-pty` e poi uccidi il processo, chiudi
  l'app. Per screenshot lancia senza console e attendi ~3s.
- **Simulatore = niente camera né giroscopio:** il foil olografico appare statico e la camera
  AVFoundation non ha device. La cattura ha un **fallback PHPicker** (foto da libreria) per
  testare il flusso sul simulatore. Il foil reattivo si apprezza solo su device fisico.
- **Naming:** non chiamare tipi propri `Tab` — collide con `SwiftUI.Tab` dentro `TabView`.

### Helper di debug (launch arguments)
- `-startTab today|collection|capture|map|profile` — apre una tab diretta.
- `-autoCapture YES` — sulla tab Cattura esegue la pipeline con un'immagine sintetica
  (test su simulatore senza PHPicker). Aggiungi `-autoSave YES` per salvare anche la carta.

## Architettura e convenzioni

- **Dipendenze esterne dietro protocollo.** Riconoscimento e persistenza hanno
  implementazione `Mock`/locale (default, gira offline sul simulatore) e una remota
  (Supabase) attivabile da `AppConfig`. Non hardcodare endpoint o chiavi nelle view.
- **Niente chiavi API nell'app.** Il riconoscimento passa SEMPRE da una Edge Function
  Supabase (cartella `supabase/`). L'app invia solo l'immagine già anonimizzata.
- **Privacy:** offuscamento volti/targhe **on-device** (Vision) PRIMA di qualsiasi invio o
  salvataggio. La posizione esatta non si mostra mai: solo l'area/quartiere.
- **Concurrency:** Swift 6 strict (`SWIFT_VERSION = 6.0`, **senza** Default Actor Isolation
  = MainActor: le annotazioni `@MainActor` sono esplicite — non cambiare il build setting
  senza chiedere). Tipi che attraversano isolation `Sendable`; servizi `async`; oggetti di
  UI `@MainActor`. Usare `@Observable` (non `ObservableObject`). Lavoro CPU pesante →
  `@concurrent` solo dopo averlo misurato (vedi skill `write-swift`).
- **Persistenza:** SwiftData (`@Model`). Le view leggono via `@Query`.
- **Test:** nuovi test con **Swift Testing** (`@Test`, `#expect`, `try #require`); XCTest solo
  per UI test.
- **Logging:** `Logger` di `os`, non `print`.
- **Stile codice:** commenti in italiano brevi e mirati come nel codice esistente.

### Gate iniziale (auth)
`RootGate` decide cosa mostrare: **onboarding → login → app**. Stato in `@AppStorage`
(`hasOnboarded`, `isSignedIn`). `OnboardingFlow` = carosello Flighty (pag.0 statica con
la macchina, le altre animate: stats/collezione/territorio). `LoginView` = sfondo
animato `DottedBackdrop` + `SignInWithAppleButton` + bottone Google (auth reale Supabase
da collegare; per ora segna loggato). NON aggiungere chiavi/endpoint nelle view.

### Shell (stile Flighty)
`RootShellView` = **`TabView` nativa di iOS 26** (la barra è Liquid Glass autentico —
NON sostituirla con una barra custom, l'utente la vuole nativa). **3 tab + camera**
come Flighty: Oggi/Collezione/Mappa + Cattura come `role: .search` (cerchio camera a
destra). Niente tab Profilo: il **profilo si apre toccando l'avatar** nello
`SheetHeader` (env `\.openProfile`), presentato come `.sheet`. La mappa è UNA sola
`MKMapView` (`MapHost` in `MapBackground.swift`) montata come `.background` del `TabView`
via `PersistentMapView`: configurata una volta sola, **non si ricarica né resetta la
camera** al cambio tab. Niente polilinee, solo i marker delle posizioni. Ogni tab di
contenuto è una `SheetCard` (card scura ancorata in basso, top trasparente per far
vedere la mappa). La tab Cattura è full-bleed (camera). Le schermate sono **contenuto
incorporabile**: niente sfondo/NavigationStack proprio (tranne Collection, che spinge al
dettaglio), header via `SheetHeader` (titolo + share + avatar a destra), padding ~130.

### Design system — usalo, non reinventare
Tutto in `CarSpot/DesignSystem/`. Mai colori/spaziature hardcoded nelle feature:
- Colori → `CSColor` · Font → `CSFont` + modifier `.eyebrow()` · Spaziature → `CSSpace` /
  `CSRadius` · Rarità (spina dorsale visiva) → `Rarity`.
- Materiali → `GlassPanel`, `.glassEffect(...)` (Liquid Glass nativo iOS 26).
- Componenti → `SpotCardView`, `RarityBadge`, `StatBar`, `PrimaryButton`/`GhostButton`.
- Atmosfera → `AsphaltBackground`, `GrainOverlay`, `HolographicFoil` + `MotionManager`.

**Il brief di CarSpot vince sulle regole generiche delle skill.** Alcune skill (impeccable,
taste) vietano "card custom" o "glass fatto a mano": qui le carte collezionabili SONO il
prodotto e il vetro è quello nativo `.glassEffect`. Non cambiare UI non richiesta.

## Skill — quando chiamarle

Skill globali in `~/.claude/skills/` + plugin attivi. Chiamale con il tool Skill **prima** di
agire quando la situazione corrisponde. Molte nascono per il web: **traducine i principi in
SwiftUI** (CSS `cubic-bezier` → `.spring(duration:bounce:)` / `.timingCurve`, `:active` →
`ButtonStyle` con `configuration.isPressed`, `prefers-reduced-motion` →
`@Environment(\.accessibilityReduceMotion)`, `backdrop-filter` → `.glassEffect`, Vibration
API → `.sensoryFeedback`). Mai copiare codice web nel progetto.

### Codice Swift e processo
| Situazione | Skill |
|---|---|
| Scrivere/rivedere Swift, errori di concurrency/Sendable, data race, retain cycle, performance | `write-swift` |
| Nuova feature non banale → prima di scrivere codice | `superpowers:brainstorming` → `superpowers:writing-plans` |
| Feature/decisione con terminologia o trade-off da chiarire (stress-test del piano) | `grill-with-docs` (usa `grilling` + `domain-modeling`; crea `GLOSSARY.md`, `docs/adr/`) |
| Scelta irreversibile (schema DB, RLS, modello dati) o termini confusi (Spot/Card/Sighting) | `domain-modeling` (ADR) |
| Dove mettere un confine/protocollo, rendere un modulo testabile | `codebase-design` |
| Salute architetturale periodica / dopo merge grossi | `improve-codebase-architecture` |
| Eseguire un piano scritto | `superpowers:executing-plans` / `superpowers:subagent-driven-development` |
| Bug, crash, comportamento inatteso | `superpowers:systematic-debugging` (+ `xcode-workflow-skills:debug`) |
| Dopo un fix: stesso pattern altrove | `xcode-workflow-skills:scan-similar-bugs` |
| Test | `superpowers:test-driven-development`, `xcode-workflow-skills:generate-tests` / `run-tests` |
| Refactor / rinomina tipi | `xcode-workflow-skills:safe-refactor` |
| Prima del commit | `xcode-workflow-skills:review-changes` |
| Prima di dire "fatto" | `superpowers:verification-before-completion` (build verde + screenshot se UI) |
| Performance / sicurezza / codice morto | `xcode-workflow-skills:performance-check` / `security-audit` / `dead-code-scanner` |
| Flussi UI, dead end, wiring dati | `xcode-workflow-skills:workflow-audit` |
| Release / screenshot App Store | `xcode-workflow-skills:release-prep` / `release-screenshots` |
| Supabase (schema, RLS, Edge Functions, Auth) | `supabase:supabase`, `supabase:supabase-postgres-best-practices` |
| Passi manuali che solo l'utente può fare (Apple Developer, APNs, chiavi Supabase) | `wizard` (rivedi lo script prima di farlo eseguire) |
| Scrivere il body di una PR | `pr` |
| Sessione andata storta → migliorare CLAUDE.md/ambiente | `retro` (+ `writing-for-agents`), `claude-md-management:revise-claude-md` |
| Il mio messaggio non si è capito | `wait-what` |

### Design e UI
| Situazione | Skill / tool |
|---|---|
| Nuova schermata o redesign: direzione visiva | `frontend-design` + `impeccable` (shape/craft) — Platform `ios` |
| Critica/audit di una schermata SwiftUI esistente | `impeccable critique <schermata>` / `impeccable audit <schermata>` (o agent `ui-reviewer`) |
| Rifinitura prima di consegnare una UI | `impeccable polish`, poi `break-ui` (dati peggiori: nomi auto lunghi, 0/1/9999 carte) |
| Tipografia, Dynamic Type, spaziature | `impeccable typeset` / `impeccable layout` |
| Copy UX, messaggi d'errore, empty state | `impeccable clarify`, `design:ux-copy` |
| Accessibilità | `design:accessibility-review`, `xcode-workflow-skills:ui-scan` |
| Linee guida SwiftUI/UX/palette/font da database | `ui-ux-pro-max` → `python3 ~/.claude/skills/ui-ux-pro-max/scripts/search.py "<query>" --stack swiftui` (dati iOS 16+, niente Liquid Glass: verifica) |
| Gesture, sheet, drag, molle, materiali, principi Apple | `apple-design` |
| Filosofia di polish/dettagli invisibili | `emil-design-eng` |
| Costruire un'animazione | `animate` (gate frequenza/scopo → valori) |
| Rivedere animazioni scritte | `review-animations` |
| Dove aggiungere motion (e dove NO) | `find-animation-opportunities` |
| Audit di tutta la motion dell'app + piani eseguibili da agent economici | `improve-animations` |
| Dare un nome a un effetto di motion | `animation-vocabulary` |
| Concept di schermate/flussi come immagini (prima di scrivere SwiftUI) | `imagegen-frontend-mobile` — solo su richiesta esplicita |
| Icona app, logo, brand board | `brandkit` — solo su richiesta esplicita |
| Coerenza del design system | `design:design-system` |

**Web-only, NON usare su CarSpot:** `impeccable live/generate/overdrive/extract/optimize`, le
skill taste web, `ui-styling`, `animation-performance`, `mobile-native`, `animate-expo`,
`pick-ui-library`, `ask-sonner`.

### MCP di design
- **21st.dev** (connettore claude.ai): `get_inspiration` / `search` (gratis, solo metadati +
  preview/video) per trovare riferimenti visivi — es. "holographic trading card", "rarity
  badge", "card reveal animation". Il codice (`get_component`) è **React/shadcn e a
  pagamento**: usalo solo come riferimento da tradurre in SwiftUI, mai da installare.
  `search_logo` (svgl, gratis) per loghi di brand/servizi (es. Google per il login); i
  marchi auto sono quasi assenti e restano soggetti a trademark.
- **Stitch** (Google): mockup rapidi di schermate da testo, solo per esplorazione.

## Modelli e subagent — non usare Opus per tutto

Opus (sessione principale) decide, progetta e verifica; il lavoro ripetitivo va delegato a
modelli più economici. Lancia **in parallelo** (un solo messaggio, più `Agent`) i pezzi
indipendenti.

| Modello | Per cosa | Agent |
|---|---|---|
| **Opus** | Architettura, decisioni di design/UX, concurrency difficile, Liquid Glass/animazioni fini, sintesi dei report, review finale, CLAUDE.md | sessione principale |
| **Sonnet** | Implementare un piano già deciso, view che seguono pattern esistenti, test, refactor meccanici, review UI/codice, analisi multi-file | `swift-implementer`, `ui-reviewer`, `impeccable-finish-reviewer`, `impeccable-documenter`, `Explore` con `model: sonnet` |
| **Haiku** | Cercare file/simboli, leggere docs/README/SDK, build e lista errori, screenshot, conteggi, grep su tutto il repo | `ios-scout`, `build-checker`, `researcher` |

Regole:
- Brief **autosufficienti**: file, obiettivo, vincoli, cosa significa "fatto". Il subagent non
  vede questa conversazione.
- Più subagent che **leggono** → in parallelo nella stessa checkout. Più subagent che
  **scrivono** → mai sugli stessi file; se possono sovrapporsi usa `isolation: "worktree"`.
- Il report di un subagent non è una prova: Opus ricontrolla diff e build prima di dire fatto.
- Le skill che producono piani per agent economici (`improve-animations`,
  `superpowers:writing-plans`) → eseguire i piani con `swift-implementer`.

## Stato
- ✅ Fase 0: scaffolding + design system + 5 tab.
- ✅ Fase 1: cattura MVP — camera AVFoundation (+ fallback PHPicker), anonimizzazione
  Vision on-device, RecognitionService (mock/remoto Supabase), RarityEngine,
  persistenza SwiftData, flusso conferma→salvataggio. Backend in `supabase/`.
- ✅ Fase 2/3: profilo giocatore (XP/livelli/valuta), obiettivi del giorno.
- ✅ Auth: onboarding animato + login (Apple/Google) con `RootGate` + permesso posizione
  (`LocationManager`); mappa di sfondo persistente che non si ricarica al cambio tab.
- ⏭️ Prossima: auth reale Supabase (token Apple/Google), sync cloud carte/profilo,
  rarità da specs reali, Live Activity. Vedi PROGETTO.md.
