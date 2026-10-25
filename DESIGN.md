---
name: CarSpot
description: Car spotting come gioco di carte collezionabili — notte d'asfalto, vetro nativo, la rarità come unica fonte di colore.
colors:
  asphalt-base: "#0B0C0F"
  asphalt-surface: "#14161B"
  asphalt-elevated: "#1C1F26"
  ink: "#F4F6FB"
  ink-secondary: "#A7AEBC"
  ink-tertiary: "#848B9B"
  ink-inverse: "#0B0C0F"
  spotting-cyan: "#1CD5F3"
  spotting-cyan-deep: "#1592B0"
  ember-amber: "#FFB23E"
  glow-top: "#16323A"
  rarity-comune-light: "#B4BCCB"
  rarity-comune-dark: "#8A93A6"
  rarity-rara-light: "#36E2FF"
  rarity-rara-dark: "#2A7DF0"
  rarity-epica-light: "#C04BFF"
  rarity-epica-dark: "#FF4D9D"
  rarity-leggendaria-gold: "#FFE176"
  rarity-leggendaria-orange: "#FFA62B"
  rarity-leggendaria-rose: "#FF5E7E"
typography:
  display:
    fontFamily: "SF Pro"
    fontSize: "34pt (largeTitle, Dynamic Type)"
    fontWeight: 700
  title:
    fontFamily: "SF Pro"
    fontSize: "22pt (title2, Dynamic Type)"
    fontWeight: 600
  numeric:
    fontFamily: "SF Pro Rounded"
    fontSize: "variabile, stile di testo più vicino"
    fontWeight: 700
  body:
    fontFamily: "SF Pro"
    fontSize: "16pt (callout, Dynamic Type)"
    fontWeight: 400
  caption:
    fontFamily: "SF Pro"
    fontSize: "13pt (footnote, Dynamic Type)"
    fontWeight: 500
  eyebrow:
    fontFamily: "SF Pro"
    fontSize: "13pt (footnote, Dynamic Type)"
    fontWeight: 600
rounded:
  sm: "14pt"
  md: "22pt"
  card: "28pt"
  lg: "30pt"
  pill: "999pt"
spacing:
  xxs: "4pt"
  xs: "6pt"
  sm: "10pt"
  md: "16pt"
  lg: "24pt"
  xl: "36pt"
  xxl: "56pt"
components:
  button-primary:
    backgroundColor: "{colors.rarity-rara-light}"
    textColor: "{colors.ink-inverse}"
    typography: "{typography.title}"
    rounded: "{rounded.pill}"
    height: "52pt min"
  button-ghost:
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.pill}"
    height: "50pt min"
  filter-chip-selected:
    textColor: "{colors.ink-inverse}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    height: "44pt min"
  glass-panel:
    rounded: "{rounded.card}"
    padding: "{spacing.lg}"
  spot-card:
    backgroundColor: "{colors.asphalt-elevated}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "{spacing.md}"
  avatar:
    backgroundColor: "{colors.spotting-cyan}"
    textColor: "{colors.ink-inverse}"
    rounded: "{rounded.pill}"
---

# Design System: CarSpot

Sorgente di verità: `CarSpot/DesignSystem/` (SwiftUI, iOS 26). Questo file la descrive;
se codice e documento divergono, vince il codice e questo file va aggiornato.

## Overview

**Creative North Star: "Asphalt Premium"** — un parcheggio di notte guardato attraverso
un vetro: superfici quasi nere e calde, inchiostro freddo, e il colore che appare solo
quando c'è qualcosa di raro da vedere.

L'interfaccia è un'app da usare per strada, con una mano, spesso in fretta: gerarchie
corte, un'azione primaria per schermata, numeri grandi e arrotondati che danno il tono
"gioco". La struttura è quella di Flighty: una mappa persistente sotto, contenuti in
card scure ancorate in basso, tab bar nativa in Liquid Glass. Il prodotto sono le carte:
tutto il resto si tiene sobrio perché le carte possano brillare.

**Key Characteristics:**
- Dark-first, mai nero puro: l'asfalto è `#0B0C0F`, non `#000`.
- La rarità è la spina dorsale visiva: un colore unico (`Rarity.color`) e un materiale (`Rarity.finish`) per ogni rarità. Niente arcobaleno, niente aloni.
- Vetro solo nativo (`.glassEffect`), mai blur fatto a mano.
- Tipografia SF Pro (Rounded solo sui numeri di gioco), che scala con Dynamic Type.
- Motion fisica e breve, senza rimbalzi sulle interazioni frequenti; il "momento wow" è riservato al reveal di una carta rara.

## Colors

Palette "Nocturne": tre livelli d'asfalto, tre inchiostri, un accent ciano e un ambra
per le ricompense. I colori saturi appartengono alle rarità.

### Primary
- **Spotting Cyan** (`#1CD5F3`, `CSColor.accent`): stato attivo, progresso (livello, obiettivi completati), filtro "Tutte", avatar dell'utente. È il colore del giocatore, non delle carte.

### Secondary
- **Ember Amber** (`#FFB23E`, `CSColor.accentWarm`): ricompense (PE, valuta, streak) ed errori non bloccanti. Mai per azioni distruttive (quelle usano `role: .destructive` di sistema).

### Rarità (`Rarity.color` + `Rarity.finish`) — aggiornato 2026-10-25
- **Comune** `#B4BCCB` — opaca, bordo 1 pt al 35%.
- **Rara** `#36E2FF` — bordo metallico 2 pt che si schiarisce con l'inclinazione.
- **Epica** `#C04BFF` — bordo foil monocromo viola.
- **Leggendaria** `#FFC14D` — foil oro monocromo su tutta la carta + bordo oro.
Il riflesso speculare segue l'inclinazione ed è tinto del colore della rarità. `Rarity.gradient` esiste solo per compatibilità e vale `[color]`.

### Neutral
- **Asfalto** (`#0B0C0F`, `CSColor.base`): sfondo più profondo.
- **Asfalto rialzato** (`#14161B`, `surface`; `#1C1F26`, `elevated`): sheet, sezioni, base delle carte.
- **Inchiostro** (`#F4F6FB`, `ink`): testo primario.
- **Inchiostro secondario** (`#A7AEBC`, `inkSecondary`): testo di supporto, sottotitoli, valori informativi.
- **Inchiostro terziario** (`#848B9B`, `inkTertiary`): eyebrow e micro-etichette; ≥ 4,5:1 anche su vetro scuro.
- **Inchiostro inverso** (`#0B0C0F`, `inkInverse`): testo sopra gradienti di rarità, accent e bianco.
- **Hairline / specular** (bianco 8% / 35%): bordi di vetro e divisori.

### Named Rules
**The Rarity Owns Color Rule.** Il colore di rarità compare solo su carte, badge, pallini e testi legati a una rarità. Avatar, header e UI generica usano l'accent o i neutri: se tutto brilla, la Leggendaria non vale niente.

**The No Pure Black Rule.** Nessun `#000` né `.black` come superficie. Ombre e scrim scuri sono ammessi.

## Typography

**Font:** SF Pro per titoli e testo; SF Pro Rounded (`design: .rounded`, bold, cifre a larghezza fissa) solo per i numeri di gioco.

**Character:** sobrio come Flighty. Il tono da gioco lo danno i numeri e le carte, non la tipografia. Niente maiuscolo spaziato: era il segnale più evidente di interfaccia "generata" (restyle 2026-10-21).

### Hierarchy
`CSFont` mappa la size richiesta sullo stile di testo di sistema più vicino, quindi tutto scala con Dynamic Type.
- **Display** (bold, 34 → largeTitle): titoli di schermata (`SheetHeader`), hero dell'onboarding.
- **Title** (semibold, 17–22 → body/title2): titoli di card, nomi auto, pulsanti.
- **Numeric** (Rounded bold, cifre fisse): contatori, livello, PE, statistiche.
- **Body** (regular, 15–16 → subheadline/callout): testo corrente.
- **Caption** (medium, 12–13 → caption/footnote): metadati, hint, errori inline.
- **Eyebrow** (`.eyebrow()`, semibold footnote, `inkSecondary`, maiuscola solo iniziale): etichette di sezione. Il colore passato si ignora.
- **Micro** (`CSFont.micro`, medium 11 → caption2): etichette sotto i numeri. È la dimensione minima: niente testo sotto gli 11 pt.

### Named Rules
**The Eleven Point Floor Rule.** Nessun testo sotto `caption2`. Le micro-etichette usano `CSFont.micro`.

**The Fixed Frame Exception.** Solo i layout a proporzione fissa (la carta collezionabile) limitano il Dynamic Type, con `.dynamicTypeSize(...DynamicTypeSize.xLarge)`. Tutto il resto deve scorrere o andare a capo.

## Layout

Scala di spaziatura `CSSpace`: 4 · 6 · 10 · 16 · 24 · 36 · 56. Il margine standard di schermata è `lg` (24), quello interno ai pannelli `lg`, e le righe compatte `md` (16). La collezione è una griglia a 2 colonne flessibili con gap `md`. Le schermate dei tab sono contenuto incorporabile dentro il pannello di sistema (`.sheet` con la `TabView`): niente sfondo né NavigationStack proprio (eccetto Collezione), con padding inferiore che lascia libera la tab bar. Ogni target tattile è ≥ 44 pt (`CSSize.minTap`).

## Elevation & Depth

**Superfici a gradini (2026-10-25).** I blocchi di contenuto delle tab sono `Surface` opache: fondo pannello `panel #0E1014`, gruppi `group #15181E`, blocco eroe `hero #1A1D24`, elementi annidati `nested #232731`. Più chiaro = più in alto; un filo di luce sul bordo superiore (bianco 9% eroe, 6% gruppi); ombra (nero 35%, r 24, y 10) solo sull'eroe e sulle carte. Un solo eroe per schermata; il resto in gruppi con righe e `SurfaceDivider`, statistiche in `KPIStrip` (niente riquadro per numero). Il Liquid Glass nativo resta sui controlli (tab bar, pulsanti flottanti, X, pillole dell'header) e su foto/mappa (`GlassPanel` in onboarding): è il livello di navigazione, non il contenuto. Niente aloni colorati da nessuna parte.

### Shadow Vocabulary
- **Carta** (nero neutro, nessun glow colorato): dettaglio e reveal.
- **Carta compatta** (nero 30%, r 10, y 6, nessun glow): griglia della collezione.

## Shapes

Forme continue (`style: .continuous`) ovunque. Raggi: 14 per elementi interni (foto nella carta, mini-statistiche, banner), 22 per righe e tile, 28 per carte e pannelli, capsula per pulsanti, chip e badge.

## Components

### Buttons
- **Primary** (`PrimaryButton`): capsula a colore pieno (default accent; mai colorata per rarità prima del reveal), senza alone, testo `inkInverse`, altezza minima 52, haptic medium (disattivabile con `haptic: false` quando l'azione ha già il suo feedback).
- **Ghost** (`GhostButton`): capsula in vetro interattivo, testo `ink`. Le scelte di pari peso (es. il consenso statistiche) usano due Ghost.
- **Pressione** (`CSPressStyle`): scala 0,97 con `.spring(duration: 0.2, bounce: 0)`; con Reduce Motion solo attenuazione. Ogni pulsante custom lo usa: mai `DragGesture` per il press.

### Chips
`FilterChip`: capsula; selezionato = riempimento col colore della rarità e testo `inkInverse`, altrimenti bianco 6% e `inkSecondary`. Altezza minima 44, trait `.isSelected`, haptic `.selection`.

### Cards / Containers
`Surface(.hero | .group, padding:)`: superfici opache a gradini, raggio 20 (vedi Elevation). `GlassPanel` (vetro nativo, raggio 28) solo sopra foto/mappa.

### Navigation
`TabView` nativa di iOS 26 (Liquid Glass autentico, mai sostituita): Oggi, Collezione, Mappa + Cattura come `role: .search`. `SheetHeader`: titolo display + avatar (apre il Profilo) + Condividi solo se c'è un'azione.

### Spot Card (signature)
`SpotCardView`: proporzione 0,7; base `elevated → surface` con velo di rarità al 16%; marca come eyebrow nel colore della rarità, modello su massimo 2 righe; foto come miniatura decodificata una volta (ImageIO, ~600 px); materiale per rarità (tabella Rarità), reattivo a dito/giroscopio, fermo con Reduce Motion; "×N" in alto a destra quando il modello ha più copie. VoiceOver la legge come un solo elemento: "Marca Modello, anno, rarità, colore".

### Reveal della carta (Cattura)
Unico momento "rumoroso" dell'app (`CardRevealView`). La foto scattata (già anonimizzata) vola nella finestra della carta con molla senza rimbalzo; una sola vibrazione all'atterraggio, intensità per rarità; da Rara in su la carta si inclina da sola una volta per mostrare il materiale; testi con sfasamento 70 ms; nota nuova / doppione (pila di 2 carte dietro) / "Già vista qui" (stessa auto: 0 punti); "+N PE" statico e barra del livello che avanza una volta. Carta inclinabile col dito e col giroscopio. Tap = stato finale. Con Reduce Motion solo dissolvenze, vibrazione presente. Mai: retro che si gira, aloni, arcobaleno, numeri che rotolano.

### Motion
Molle `.spring(duration:bounce:)` con bounce 0 per tutto ciò che è frequente (pagine, filtri, stati, barre: 0,2–0,6 s). Il rimbalzo (bounce ≤ 0,15) è riservato al reveal. Ogni animazione legge `accessibilityReduceMotion`. Le animazioni continue (sfondo a puntini) girano a 30 fps e si fermano in background o con Reduce Motion.

## Do's and Don'ts

### Do:
- **Do** usare i token (`CSColor`, `CSFont`, `CSSpace`, `CSRadius`, `CSSize`) per ogni valore; un nuovo valore ricorrente diventa un token.
- **Do** dare a ogni stato vuoto un messaggio e una via d'uscita ("Nessuna carta ancora — tocca la fotocamera").
- **Do** comunicare la rarità anche a parole (badge, label VoiceOver), non solo col colore.
- **Do** usare `.sensoryFeedback` e un solo haptic per azione.
- **Do** scrivere il copy in italiano, dando del tu, senza gergo tecnico negli errori ("Sei offline. Riprova quando torni in rete.").

### Don't:
- **Don't** mostrare dati finti come reali: se una funzione non esiste ancora, va nascosta o etichettata "Anteprima".
- **Don't** usare il colore di rarità fuori da carte, badge e dati di rarità (avatar, header, decorazioni).
- **Don't** glow/aloni colorati, gradienti arcobaleno, bordi al neon, numeri che rotolano, rimbalzi su UI, fade-in di intere schermate, card identiche in fila (usa un gruppo con divisori).
- **Don't** usare `.system(size:)` per il testo: rompe Dynamic Type.
- **Don't** sostituire la tab bar nativa o imitare il vetro con blur e opacità.
- **Don't** mettere testo sotto gli 11 pt, né `inkTertiary` su testo che serve leggere per agire.
- **Don't** far rimbalzare le transizioni frequenti né superare ~0,4 s su azioni ripetute.
