# CarSpot 🚗

App iOS nativa (SwiftUI · iOS 26 · Swift 6) che trasforma il *car spotting* reale in
un gioco di carte collezionabili: inquadri un'auto vera, l'app la riconosce e la
trasforma in una carta con rarità, statistiche, sfide e territorio.

> UI ispirata a Flighty (mappa a tutto schermo + Liquid Glass), design system
> "Nocturne / Asphalt Premium".

## Avvio rapido

1. **Apri** `CarSpot.xcodeproj` in Xcode 26 e premi ⌘R su un simulatore iOS 26.
2. **Secrets** (solo se colleghi Supabase): copia il template e inserisci le chiavi
   ```bash
   cp Secrets.swift.example CarSpot/Services/Secrets.swift
   ```
   `CarSpot/Services/Secrets.swift` è nel `.gitignore`: le chiavi non finiscono mai su git.

L'app funziona **offline** out-of-the-box (riconoscimento mock + dati locali SwiftData);
non serve alcuna chiave per provarla.

## Documentazione
- [PROGETTO.md](PROGETTO.md) — concept, architettura, decisioni e roadmap.
- [CLAUDE.md](CLAUDE.md) — convenzioni, comandi e note per lo sviluppo.
- [supabase/README.md](supabase/README.md) — backend (schema PostGIS + Edge Function).

## Stato
- ✅ Fase 0 — scaffolding + design system Liquid Glass
- ✅ Fase 1 — cattura MVP (camera, anonimizzazione Vision, riconoscimento, SwiftData)
- ✅ UI shell stile Flighty (mappa di sfondo + TabView Liquid Glass nativa)
- ⏭️ Fase 2/3 — rarità da specs reali, obiettivi, XP/livelli
