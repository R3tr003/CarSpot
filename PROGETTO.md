# CarSpot — Car Spotting come gioco di carte collezionabili

App iOS nativa (SwiftUI, iOS 26, Swift 6) che trasforma il car spotting reale in un
TCG/RPG: inquadri un'auto vera, l'app la riconosce e la converte in una carta
collezionabile con rarità, statistiche, sfide giornaliere, territorio e duelli.

## Stato attuale — Fase 0 (Fondamenta) ✅

- Progetto Xcode generato (synchronized root group, niente pbxproj da editare a mano).
- **Design system "Nocturne / Asphalt Premium"** in Liquid Glass: token, componenti,
  effetti (foil olografico reattivo al movimento, grana asfalto).
- Scheletro a 5 tab funzionante: Oggi, Collezione, Cattura, Territorio, Profilo.
- Build verde + verifica su simulatore iOS 26 (iPhone 17 Pro).

### Come eseguire
```bash
open CarSpot.xcodeproj   # ⌘R su un simulatore iOS 26
```
Helper di debug: launch argument `-startTab collection|capture|map|profile`.

## Decisioni architetturali

### Backend: Supabase (Postgres + PostGIS)
Scelto perché l'app è fortemente geografica (avvistamenti per area, controllo
quartieri, classifiche di zona): PostGIS gestisce le query spaziali nativamente.
- **Auth** (Sign in with Apple) · **Postgres** (carte, collezioni, classifiche)
- **PostGIS** (avvistamenti/quartieri) · **Storage** (foto offuscate)
- **Realtime + Edge Functions → APNs** (notifiche avvistamento)
- **Edge Functions** (orchestrazione riconoscimento + anti-cheat)

### Riconoscimento auto: API cloud + conferma utente
Flusso: **cattura → blur volti/targhe on-device (Vision) → crop inviato a una
Edge Function che chiama un'API di riconoscimento (es. CarNet.AI ~97% marca/modello)
→ l'utente conferma fra i candidati**. L'anno è trattato come stima da confermare
(accuratezza reale 75–85% ±2 anni). Le chiavi API restano nel backend, mai nell'app.

### Design
Liquid Glass nativo iOS 26 + motion ispirato a Flighty (transizioni zoom
`matchedTransitionSource`, parallasse, haptics). La **rarità è la spina dorsale
visiva**; la carta Leggendaria ha il foil olografico reattivo al giroscopio.

## Struttura
```
CarSpot/
  App/                      entry point
  DesignSystem/
    Theme/                  CSColor, CSFont, CSLayout, Rarity
    Components/             GlassPanel, SpotCardView, RarityBadge, StatBar, PrimaryButton
    Effects/                AsphaltBackground, HolographicFoil, MotionManager
  Features/                 Root, Today, Collection, Capture, Map, Profile
  Models/                   SpotCard, DailyChallenge (dati di esempio)
```

## Roadmap
- **Fase 1 — Cattura (MVP):** ✅ fatta. AVFoundation (+ fallback PHPicker per il
  simulatore), anonimizzazione Vision on-device (volti/targhe), RecognitionService
  (mock offline / remoto Supabase), RarityEngine, persistenza SwiftData, flusso
  conferma→salvataggio. Codice backend in `supabase/` (schema PostGIS + Edge Function).
- **Fase 2 — Collezione & Carte:** persistenza, dettaglio, rarità derivata da specs reali.
- **Fase 3 — Gamification:** obiettivi del giorno, XP, valuta, livelli, Live Activity.
- **Fase 4 — Social/Proprietari:** registra la tua auto, notifiche avvistamento, reazioni.
- **Fase 5 — Territorio:** MapKit, quartieri PostGIS, classifiche, Supervisori.
- **Fase 6 — Duelli:** sfide testuali sui dati tecnici.
- **Fase 7 — Rifinitura:** widget, Live Activities, TestFlight.
