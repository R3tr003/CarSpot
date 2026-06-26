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
xcrun simctl install booted "$APP" && xcrun simctl launch booted com.carspot.app

# Screenshot
xcrun simctl io booted screenshot shot.png
```

Preferire i tool **XcodeBuildMCP** quando disponibili (`build_run_sim`, `snapshot_ui`).
L'automazione UI a tap di XcodeBuildMCP **non è abilitata** in questa configurazione.

### Gotcha verificati (non ripeterli)
- **Rilancio:** `simctl launch` su app già in foreground NON rilancia. `simctl terminate`
  PRIMA di `launch` quando serve rivedere lo stato iniziale.
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

### Shell (stile Flighty)
`RootShellView` = mappa MapKit a tutto schermo (`MapBackground`) come sfondo
persistente + `BottomSheet` trascinabile (2 detent) che ospita la tab attiva +
`FloatingTabBar` (pillola glass con 4 tab: Oggi/Collezione/Mappa/Profilo) e un
bottone camera accent che presenta `CaptureView` come `fullScreenCover` (come
"Add Flight"). Le schermate sono **contenuto incorporabile**: niente sfondo o
NavigationStack proprio (tranne Collection, che spinge al dettaglio), header via
`SheetHeader` (titolo + share + `UserAvatar` a destra), padding bottom ~130 per la
tab bar flottante.

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
- ⏭️ Prossima — Fase 2/3: rarità da specs reali, obiettivi del giorno funzionanti,
  XP/valuta/livelli, Live Activity. Vedi PROGETTO.md.
