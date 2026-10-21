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
    fontFamily: "SF Pro Rounded"
    fontSize: "34pt (largeTitle, Dynamic Type)"
    fontWeight: 800
  title:
    fontFamily: "SF Pro Rounded"
    fontSize: "22pt (title2, Dynamic Type)"
    fontWeight: 700
  numeric:
    fontFamily: "SF Pro Rounded"
    fontSize: "variabile, stile di testo più vicino"
    fontWeight: 900
  body:
    fontFamily: "SF Pro Rounded"
    fontSize: "16pt (callout, Dynamic Type)"
    fontWeight: 500
  caption:
    fontFamily: "SF Pro Rounded"
    fontSize: "13pt (footnote, Dynamic Type)"
    fontWeight: 600
  eyebrow:
    fontFamily: "SF Pro Rounded"
    fontSize: "11pt (caption2, Dynamic Type)"
    fontWeight: 700
    letterSpacing: "2.2pt"
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
- La rarità è la spina dorsale visiva: gradiente, bordo, glow e foil di ogni carta derivano da `Rarity`.
- Vetro solo nativo (`.glassEffect`), mai blur fatto a mano.
- Tipografia SF Pro Rounded ovunque, che scala con Dynamic Type.
- Motion fisica e breve, senza rimbalzi sulle interazioni frequenti; il "momento wow" è riservato al reveal di una carta rara.

## Colors

Palette "Nocturne": tre livelli d'asfalto, tre inchiostri, un accent ciano e un ambra
per le ricompense. I colori saturi appartengono alle rarità.

### Primary
- **Spotting Cyan** (`#1CD5F3`, `CSColor.accent`): stato attivo, progresso (livello, obiettivi completati), filtro "Tutte", avatar dell'utente. È il colore del giocatore, non delle carte.

### Secondary
- **Ember Amber** (`#FFB23E`, `CSColor.accentWarm`): ricompense (PE, valuta, streak) ed errori non bloccanti. Mai per azioni distruttive (quelle usano `role: .destructive` di sistema).

### Rarità (`Rarity.gradient`)
- **Comune — Acciaio freddo** (`#B4BCCB → #8A93A6`): nessun glow.
- **Rara — Ciano elettrico** (`#36E2FF → #2A7DF0`): glow 0,25.
- **Epica — Viola-magenta** (`#C04BFF → #FF4D9D`): glow 0,45, foil olografico.
- **Leggendaria — Oro al tramonto** (`#FFE176 → #FFA62B → #FF5E7E`): glow 0,7, foil olografico.

### Neutral
- **Asfalto** (`#0B0C0F`, `CSColor.base`): sfondo più profondo.
- **Asfalto rialzato** (`#14161B`, `surface`; `#1C1F26`, `elevated`): sheet, sezioni, base delle carte.
- **Inchiostro** (`#F4F6FB`, `ink`): testo primario.
- **Inchiostro secondario** (`#A7AEBC`, `inkSecondary`): testo di supporto, sottotitoli, valori informativi.
- **Inchiostro terziario** (`#848B9B`, `inkTertiary`): eyebrow e micro-etichette; ≥ 4,5:1 anche su vetro scuro.
- **Inchiostro inverso** (`#0B0C0F`, `inkInverse`): testo sopra gradienti di rarità, accent e bianco.
- **Hairline / specular** (bianco 8% / 35%): bordi di vetro e divisori.

### Named Rules
**The Rarity Owns Color Rule.** I gradienti di rarità compaiono solo su carte, badge e pulsanti legati a una rarità. Avatar, header e UI generica usano l'accent o i neutri: se tutto brilla, la Leggendaria non vale niente.

**The No Pure Black Rule.** Nessun `#000` né `.black` come superficie. Ombre e scrim scuri sono ammessi.

## Typography

**Font unico:** SF Pro Rounded (`design: .rounded`), pesi da medium a black.

**Character:** arrotondato e pesante sui numeri e sui titoli per il tono da gioco; l'eyebrow maiuscolo con tracking largo dà il registro "scheda tecnica".

### Hierarchy
`CSFont` mappa la size richiesta sullo stile di testo di sistema più vicino, quindi tutto scala con Dynamic Type.
- **Display** (heavy, 34 → largeTitle): titoli di schermata (`SheetHeader`), hero dell'onboarding.
- **Title** (bold, 17–22 → body/title2): titoli di card, nomi auto, pulsanti.
- **Numeric** (black): contatori, livello, PE, statistiche.
- **Body** (medium, 15–16 → subheadline/callout): testo corrente.
- **Caption** (semibold, 12–13 → caption/footnote): metadati, hint, errori inline.
- **Eyebrow / Micro** (bold 11 → caption2, tracking 2,2, MAIUSCOLO): etichette di sezione ed etichette sotto i numeri. È la dimensione minima: niente testo sotto gli 11 pt.

### Named Rules
**The Eleven Point Floor Rule.** Nessun testo sotto `caption2`. Le micro-etichette usano `CSFont.micro`.

**The Fixed Frame Exception.** Solo i layout a proporzione fissa (la carta collezionabile) limitano il Dynamic Type, con `.dynamicTypeSize(...DynamicTypeSize.xLarge)`. Tutto il resto deve scorrere o andare a capo.

## Layout

Scala di spaziatura `CSSpace`: 4 · 6 · 10 · 16 · 24 · 36 · 56. Il margine standard di schermata è `lg` (24), quello interno ai pannelli `lg`, e le righe compatte `md` (16). La collezione è una griglia a 2 colonne flessibili con gap `md`. Le schermate dei tab sono contenuto incorporabile dentro `SheetCard`: niente sfondo né NavigationStack proprio (eccetto Collezione), con padding inferiore che lascia libera la tab bar. Ogni target tattile è ≥ 44 pt (`CSSize.minTap`).

## Elevation & Depth

La profondità viene dal vetro, non dalle ombre. Le superfici in Liquid Glass nativo (`GlassPanel`, `.glassEffect`) stanno sopra la mappa e l'asfalto, con un bordo speculare (gradiente bianco 35% → trasparente → hairline) che dà lo spessore. Le ombre sono riservate alle carte (ombra nera morbida e glow della rarità) e ai pulsanti primari (alone del loro gradiente).

### Shadow Vocabulary
- **Carta** (nero 50%, r 20, y 14 + glow `rarity.primary × glowStrength × 0,5`, r 24): dettaglio e reveal.
- **Carta compatta** (nero 30%, r 10, y 6, nessun glow): griglia della collezione.
- **Pulsante primario** (primo colore del gradiente 50%, r 18, y 8).

## Shapes

Forme continue (`style: .continuous`) ovunque. Raggi: 14 per elementi interni (foto nella carta, mini-statistiche, banner), 22 per righe e tile, 28 per carte e pannelli, capsula per pulsanti, chip e badge.

## Components

### Buttons
- **Primary** (`PrimaryButton`): capsula con il gradiente (default Rara), testo `inkInverse`, altezza minima 52, haptic medium (disattivabile con `haptic: false` quando l'azione ha già il suo feedback).
- **Ghost** (`GhostButton`): capsula in vetro interattivo, testo `ink`. Le scelte di pari peso (es. il consenso statistiche) usano due Ghost.
- **Pressione** (`CSPressStyle`): scala 0,97 con `.spring(duration: 0.2, bounce: 0)`; con Reduce Motion solo attenuazione. Ogni pulsante custom lo usa: mai `DragGesture` per il press.

### Chips
`FilterChip`: capsula; selezionato = riempimento col colore della rarità e testo `inkInverse`, altrimenti bianco 6% e `inkSecondary`. Altezza minima 44, trait `.isSelected`, haptic `.selection`.

### Cards / Containers
`GlassPanel`: vetro nativo, raggio 28, padding 24, tint opzionale al 50%.

### Navigation
`TabView` nativa di iOS 26 (Liquid Glass autentico, mai sostituita): Oggi, Collezione, Mappa + Cattura come `role: .search`. `SheetHeader`: titolo display + avatar (apre il Profilo) + Condividi solo se c'è un'azione.

### Spot Card (signature)
`SpotCardView`: proporzione 0,7; base `elevated → surface` con velo di rarità al 16%; marca come eyebrow nel colore della rarità, modello su massimo 2 righe; foto come miniatura decodificata una volta (ImageIO, ~600 px); bordo gradiente 1,5 pt; foil olografico reattivo al giroscopio per Epica e Leggendaria (fermo con Reduce Motion). VoiceOver la legge come un solo elemento: "Marca Modello, anno, rarità, colore".

### Reveal della carta (Cattura)
Proporzionale alla rarità: Comune solo dissolvenza ≤ 0,25 s; Rara scala 0,95 → 1 con alone; Epica/Leggendaria più una passata di foil, ≤ 1,2 s in tutto, saltabile con un tap. Haptic `.success` per Comune/Rara, impatto pesante per Epica/Leggendaria. Con Reduce Motion solo dissolvenza.

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
- **Don't** usare i gradienti di rarità fuori dalle carte (avatar, header, decorazioni).
- **Don't** usare `.system(size:)` per il testo: rompe Dynamic Type.
- **Don't** sostituire la tab bar nativa o imitare il vetro con blur e opacità.
- **Don't** mettere testo sotto gli 11 pt, né `inkTertiary` su testo che serve leggere per agire.
- **Don't** far rimbalzare le transizioni frequenti né superare ~0,4 s su azioni ripetute.
