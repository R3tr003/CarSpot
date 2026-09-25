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
- **Concurrency:** Swift 6 strict. Tipi che attraversano isolation `Sendable`; servizi
  `async`; oggetti di UI `@MainActor`. Usare `@Observable` (non `ObservableObject`).
- **Persistenza:** SwiftData (`@Model`). Le view leggono via `@Query`.
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

## Skill da usare (caricate in questo ambiente)
- **frontend-design** → per nuovo lavoro di UI/visual (lo facciamo a feature pronte).
- **xcode-workflow-skills** → `debug`, `review-changes`, `generate-tests`, `run-tests`,
  `performance-check`, `security-audit`, `safe-refactor`, `release-prep`.
- **claude-md-management** → tenere aggiornato questo file.

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
