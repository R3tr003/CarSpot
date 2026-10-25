# Stato del progetto (storico)

- ✅ Fase 0: scaffolding + design system + 5 tab.
- ✅ Fase 1: cattura MVP — camera AVFoundation (+ fallback PHPicker), anonimizzazione
  Vision on-device, RecognitionService (mock/remoto Supabase), RarityEngine,
  persistenza SwiftData, flusso conferma→salvataggio. Backend in `supabase/`.
- ✅ Fase 2/3: profilo giocatore (XP/livelli/valuta), obiettivi del giorno.
- ✅ Auth: onboarding animato + login (Apple/Google) con `RootGate` + permesso posizione
  (`LocationManager`); mappa di sfondo persistente che non si ricarica al cambio tab.
- ✅ Auth reale + analytics (2026-10-20): Clerk (Google funzionante su device; Apple
  attende Developer Program) → JWT verso Supabase (third-party auth, profilo creato al
  primo login), Mixpanel EU con consenso GDPR. DB rifatto per Clerk (migration 0002/0003).
- ✅ Sync cloud carte/profilo (SwiftData ↔ Supabase, migration 0004) e icona Liquid Glass
  (`CarSpot/AppIcon.icon`, light + dark) — 2026-10-21.
- ✅ Login email/telefono (OTP Clerk), setup profilo post-registrazione (migration 0005),
  webhook Clerk → Supabase — 2026-10-21, da provare su device.
- ✅ 2026-10-25: `recognize` con verifica JWT Clerk + rate limit (migration 0007/0008, non
  ancora deployata), anonimizzazione fail-closed, quartiere reale (`AreaResolver`), target
  `CarSpotTests`. Superfici a gradini (`Surface`, `KPIStrip`), colore unico + materiale per
  rarità, reveal v3 (`CardRevealView`: la foto diventa la carta), cronologia nella tab
  Cattura (`CaptureHistoryView`), doppioni con XP decrescente e "stessa auto" = 0 punti
  (`CardCopies`, `PhotoSimilarity`, `StoredCard.isRepeat`, migration 0009). Da provare su iPhone.
- ⏭️ Prossima: provider di riconoscimento (prova Claude Haiku vs Sonnet) + deploy di
  `recognize`; catalogo modelli con immagine standard (prova con immagini da internet) e
  Collezione "album"; marker reali sulla mappa (decisione privacy); rarità da specs reali.
