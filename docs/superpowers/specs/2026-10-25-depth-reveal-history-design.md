# Profondità, reveal della carta, cronologia catture — design

Data: 2026-10-25 · Stato: approvato dall'utente (mockup nel visual companion: `depth-blocks.html` opzione B,
`reveal-prototype-v3.html`, `capture-history.html` in `.superpowers/brainstorm/`).

## Perché

Provando l'app sull'iPhone l'utente ha trovato tre cose che non gli piacciono:
1. I blocchi informativi (card livello, obiettivi, statistiche, righe) sono **piatti e statici**: tutti lo
   stesso vetro grigio su nero pieno. Causa trovata nel codice: `GlassPanel` è solo `.glassEffect(.regular)`
   sopra `presentationBackground(CSColor.base)`; il vetro non ha niente da rifrangere, il `tint` viene
   ignorato, `eyebrow()` ignora il colore, non c'è alcuna differenza di livello tra un blocco e l'altro.
2. La schermata dopo lo scatto è **piccola, senza animazione percepibile e generica**. Un primo prototipo
   (retro della carta che si gira + alone colorato + XP che rotola) è stato bocciato come "AI slop", e
   l'arcobaleno olografico pure. Vuole: **un colore per ogni rarità** e **differenza tra auto nuova e doppione**.
3. Chiudendo la fotocamera il pannello resta sulla tab Cattura **vuota** (bug del commit 348fa8b: la `TabView`
   UIKit seleziona la tab `.search`, il binding SwiftUI non la riporta indietro). Vuole lì una **cronologia**.

Riferimenti di gusto usati: taste-skill v2 (Leonxlnx), apple-design (WWDC "Designing Fluid Interfaces"),
ui-ux-pro-max. Il brief di CarSpot vince sulle skill dove confliggono (vedi Vincoli).

## Obiettivi

- **A. Profondità "a gradini"** su tutti i blocchi di contenuto delle tab (Today, Collezione, Mappa/Territorio,
  Profilo) e della schermata risultato.
- **B. Reveal della carta v3**: la foto scattata vola dentro la carta; rarità = colore + materiale; nuova vs
  doppione; un solo momento "rumoroso" in tutta l'app.
- **C. Tab Cattura = cronologia** degli scatti, e fine del pannello vuoto.
- **D. Un colore per rarità** in tutta l'app (niente gradienti arcobaleno sulle rarità).

## Non-obiettivi (progetti separati, già annotati)

- Marker reali sulla mappa (serve una decisione privacy sulla posizione dell'area).
- **Catalogo modelli con immagine standard uguale per tutti** + Collezione stile album "trovata / non trovata"
  (richiesta dell'utente del 2026-10-25). Decisione utente: per ora una **prova con immagini scaricate da
  internet**, quelle professionali dopo. Ha un suo design separato (schema DB, licenze, ADR).
  Questo design NON tocca la struttura della Collezione oltre allo stile delle superfici e al "×N".
- Riconoscimento reale (provider) e rarità da specifiche.

## Anti-obiettivi (sarebbe un fallimento anche se funziona)

- Aloni/glow colorati, gradienti arcobaleno, bordi al neon, numeri che rotolano, rimbalzi su elementi UI,
  fade-up identico su ogni blocco, "hover lift", pulsazioni in loop, emoji come icone.
- Sostituire la tab bar nativa o il pannello di sistema (`.sheet`) con versioni fatte a mano.
- Ombre grigie morbide su ogni card.

## Vincoli

- CLAUDE.md di progetto: SwiftUI iOS 26, Swift 6 strict con `@MainActor` espliciti, `@Observable`, SwiftData,
  design system in `CarSpot/DesignSystem/` (mai colori/spaziature hardcoded nelle feature), Dynamic Type
  (`CSFont`, mai `.system(size:)` per testo), `CSPressStyle` per la pressione, Reduce Motion rispettato,
  `Logger` di os, Swift Testing, commenti brevi in italiano, stringhe nel catalogo (IT base + EN).
- **Liquid Glass nativo resta sui controlli** (tab bar, pulsanti flottanti, X di chiusura, pillole
  dell'header). I blocchi di contenuto passano a superfici opache a gradini — è anche la regola Apple:
  il vetro è il livello di navigazione, non il contenuto.
- Verifica solo con build generica (`generic/platform=iOS Simulator`, `build` / `build-for-testing`);
  **niente simulatori, niente installazioni**: l'utente prova sull'iPhone.
- L'XP è deciso dal server (trigger `private.award_card`, migration 0004): il client non deve divergere.

## Decisioni

### A. Superfici a gradini (approvata opzione B)

- **Toni** (nuovi token in `CSColor`, nomi a scelta del builder):
  fondo pannello `#0E1014` (sostituisce `CSColor.base` in `presentationBackground`), gruppo `#15181E`,
  eroe `#1A1D24`, annidato (icone, tracce) `#232731`.
- **Luce dall'alto**: ogni superficie ha un filo di luce sul bordo superiore (1 pt, bianco ~9% sull'eroe,
  ~6% sui gruppi), non un bordo intero. **Ombra solo sull'eroe** (nero ~35%, raggio ~24, y ~10) e sulle carte.
- **Un blocco eroe per schermata**, più grande e più chiaro, che risponde alla domanda della schermata
  (Today: livello e progresso; Profilo: livello; Territorio: riepilogo). Il resto in **gruppi** con righe e
  divisori 1 px, non in card separate identiche (es. i 3 obiettivi del giorno = un gruppo).
- **KPI** (statistiche di Collezione e Profilo): niente riquadro per ogni numero; etichetta sopra il valore,
  divisori verticali, cifre tabulari.
- Raggi: eroe e gruppi 20, elementi annidati scalano (10, 8).
- Colore solo su dati, stato e azione: barra progresso accent; XP ambra; rarità col suo colore; completato
  verde (token nuovo, es. `#3FC07A`).
- `eyebrow()` deve rispettare il colore passato (oggi lo ignora).
- `StatBar`/barre di progresso: si animano **solo quando il valore cambia** (es. dopo una cattura), non a
  ogni apparizione. Niente fade-in globale di intere schermate (Today oggi lo fa: togliere).
- `GlassPanel` resta per i casi su foto/mappa (es. onboarding) ma non per i blocchi delle tab.

### B. Reveal della carta v3 (approvato `reveal-prototype-v3.html`)

Sequenza (Common salta i passi marcati ★):
1. **Volo** (0–560 ms): il fermo immagine a schermo intero si rimpicciolisce dentro la finestra foto della
   carta (transizione geometrica continua, molla senza rimbalzo, es. `.spring(duration: 0.5, bounce: 0)`).
   Lo sfondo resta la stessa foto, scurita (~70%) e con sfocatura lieve (≤ 6 pt). La cornice della carta
   compare intorno (opacità + scala 0,97→1).
2. **Atterraggio** (~560 ms): **una sola vibrazione**, intensità per rarità (Common leggera … Legendary
   forte). ★ La carta si inclina da sola di 7–9° una volta e torna, così il materiale prende luce.
3. **Testi** (~+150 ms): marca/modello, poi meta (anno, quartiere, ora), poi riga rarità; sfasamento 70 ms,
   salita 10 pt + opacità, curva "out" (tipo `cubic-bezier(0.22,1,0.36,1)`).
4. **Nota** (~+260 ms): nuova → "Nuova nella collezione" + "Carta N · prima <Marca>" (la seconda parte solo
   se è davvero la prima di quella marca); doppione → "La tua 3ª Polo" e dietro la carta compaiono
   **due carte della pila** sfalsate (8–10 pt, 2–4°).
5. **Ricompensa** (~+420 ms): riga "+N XP" (ambra, statica, niente conteggio) e "Livello L · x/100";
   la barra del livello avanza una volta (~800 ms). Azioni: **"Cattura un'altra"** (secondaria) e
   **"Fatto"** (primaria: chiude la fotocamera e porta alla cronologia).

Interazione: la carta si **inclina col dito** (1:1, resistenza elastica oltre ~16°, al rilascio torna con
molla critica che eredita la velocità) e, su device, col **giroscopio** (`MotionManager` esistente).
Tocco sullo sfondo = salta allo stato finale. **Riduci movimento**: niente volo né inclinazione, dissolvenze
brevi; la vibrazione resta.

Materiali per rarità (colore unico + finitura, niente arcobaleno):

| Rarità | Colore | Finitura |
|---|---|---|
| Comune | `#B4BCCB` | opaca, bordo 1 pt al ~35% |
| Rara | `#36E2FF` | bordo metallico 2 pt la cui luminosità segue l'inclinazione |
| Epica | `#C04BFF` | bordo foil: riflesso monocromo viola che scorre con l'inclinazione |
| Leggendaria | `#FFC14D` | foil oro monocromo su tutta la carta + bordo oro |

Il riflesso speculare (luce radiale che segue l'inclinazione) è tinto del colore della rarità.

**Nuova vs doppione**: doppione = esiste già nella collezione locale una carta con stessa marca+modello
(confronto normalizzato: minuscole, spazi ridotti).

**XP dei doppioni (deciso dall'utente: "parte da un 25% del primo e poi va sempre a diminuire, sennò sono
punti illimitati")**. Formula *(i valori esatti sono mia scelta)*: per la copia numero `n` (n = 1 la prima)
`xp = n == 1 ? base : floor(base × 0.25 / 2^(n−2))`. Esempi: Comune 20 → 5, 2, 1, 0…; Leggendaria
260 → 65, 32, 16, 8, 4, 2, 1, 0. La valuta segue l'XP come oggi. Va nel trigger server
`private.award_card` (nuova migration **applicata sul progetto Supabase remoto**, poi `get_advisors`) e
replicata nel client solo per mostrarla; costanti in un posto solo per lato.

**Stessa macchina = zero punti (deciso dall'utente, 2026-10-25)**: chi fotografa più volte la stessa auto
(stesso posto) non deve accumulare punti. Una cattura è una **ripetizione** se vale almeno uno dei due:
1. stesso modello (chiave normalizzata) **nello stesso quartiere** (`spottedArea`) **nelle 24 ore** precedenti
   (controllo anche sul server, non aggirabile);
2. la foto anonimizzata è **quasi identica** (feature print di Vision, on-device, niente invio) a una delle
   ultime catture di quel modello (soglia di distanza in una costante, da tarare).
La carta di una ripetizione **si salva comunque** (`isRepeat = true`): compare in cronologia con
"Già vista · nessun punto", **0 XP e 0 valuta**, **non** conta come copia (né "×N" né numero di copia per
l'XP dei doppioni), **non** compare in Collezione e **non** conta per gli obiettivi del giorno. Il reveal
mostra la variante "Già vista qui" senza riga XP. Sul server: colonna `cards.is_repeat` (default false);
un trigger *before insert* la mette a true se vale la regola 1; il client può mandarla true per la regola 2
(abbassa solo i propri punti). `award_card` dà 0 se `is_repeat`, e conta le copie solo tra le non ripetute.

**Copie scritte sulla carta (richiesta dell'utente)**: quando un modello ha più copie, la carta stessa
(in `SpotCardView`, quindi Collezione, dettaglio e reveal) mostra "×N" con il numero di copie inserite.

### C. Cronologia nella tab Cattura (approvata `capture-history.html`)

- La tab Cattura diventa una tab vera con contenuto `CaptureHistoryView`. Toccarla **seleziona la tab e
  apre la fotocamera**; chiudendo la fotocamera (X o "Fatto") si resta sulla cronologia. Così la selezione
  della `TabView` e quella SwiftUI coincidono e il pannello vuoto sparisce.
- Header `SheetHeader("Cattura")`, bottone primario "Scatta una foto", riga riassunto (carte, modelli,
  ultima cattura).
- Sezioni per giorno (Oggi, Ieri, poi data), dalla più recente; intestazione con il numero di catture del
  giorno (+ XP del giorno solo se calcolabile in modo esatto dai dati salvati).
- Riga: miniatura della propria foto (anonimizzata) con bordo interno 2 pt del colore della rarità,
  marca (secondaria), modello, "quartiere · ora", a destra rarità (pallino + nome colorato) e "Nuova" o
  "×N" (N = copie di quel modello in collezione).
- La cattura appena fatta compare in cima con un velo del colore della rarità che svanisce in ~3 s.
- Tocco su una riga → dettaglio carta con la stessa transizione zoom della Collezione.
- Stato vuoto: "Nessuna cattura" + una frase + il bottone.

### D. Un colore per rarità

`Rarity` espone un colore unico (tabella sopra) usato per badge, bordi carta, pallini, testi. I gradienti
multi-colore delle rarità e l'`HolographicFoil` arcobaleno vengono sostituiti dalla finitura monocroma
della tabella (anche in `SpotCardView` e nel dettaglio carta).

## Chiarimenti dopo il builder check (decisioni mie, marcate)

- **Conferma del modello resta** (con il riconoscimento reale servirà correggere gli errori). *Mia scelta:*
  dalla fase di elaborazione in poi la **foto scattata resta grande a schermo intero** come sfondo
  (scurita), e il pannello dei candidati sta sopra. Premendo "Aggiungi alla collezione" il pannello esce e
  la foto vola nella carta: niente salto. Il pannello di conferma usa le superfici a gradini.
  L'unica vibrazione del reveal si sposta dal cambio di fase all'atterraggio (~560 ms).
- **Doppioni = solo XP** (e valuta, che segue l'XP). *Mia scelta:* obiettivi del giorno e analytics
  invariati.
- **Etichetta in cronologia** *(mia scelta)*: derivata da `capturedAt`, nessun campo nuovo. La prima copia di
  un modello resta "Nuova"; le successive mostrano l'ordinale al momento dello scatto ("2ª", "3ª").
  Niente totale XP per giorno: solo il numero di catture.
- **Rilevamento doppione sul server**: confronto normalizzato marca+modello escludendo la riga appena
  inserita. Un disallineamento breve con il client finché le carte non sono sincronizzate è accettabile.
  La percentuale è una costante unica (server) con il gemello nel client.

## Lasciato al builder

- Nomi dei token e dei componenti, struttura dei file, come implementare la transizione geometrica
  (`matchedGeometryEffect` o calcolo dei frame) e il foil monocromo (shader o gradienti).
- Valori fini di molle e durate entro quelli indicati.
- Come esporre al VM "nuova/doppione", "prima marca", numero carta, conteggio copie.
- Copy esatta (IT/EN) nel tono delle stringhe esistenti.
