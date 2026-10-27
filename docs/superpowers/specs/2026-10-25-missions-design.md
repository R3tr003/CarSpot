# Missioni giornaliere, settimanali, mensili e comuni — design

Data: 2026-10-25 · Stato: **approvato dall'utente (2026-10-25)**. ADR: `docs/adr/0002-missioni-regole-dati-verificate-dal-server.md`.
Mockup nel visual companion (`.superpowers/brainstorm/76939-1792946925/content/`): `today-layout.html`
(scelta: **B, selettore di periodo**), `today-layout-b3.html` (pallini numerati; l'utente li vuole
**leggermente più piccoli** di così).

## Perché

Oggi esistono solo 3 obiettivi del giorno uguali per tutti (`ChallengeEngine`), e alcuni contano **tutte**
le carte mai catturate: chi ha già un'Epica trova "Cattura un'auto Epica" completata appena apre l'app.
La serie di giorni non avanza mai (resta a 1). L'utente vuole **missioni che fanno andare avanti ma non si
finiscono subito**, su tre ritmi (giorno, settimana, mese), **su misura** per il tipo di giocatore, più
**missioni comuni** per ambito (Mondo, Europa, Italia) uguali per tutti. Premi: PE e valuta, e **badge** che
un domani confluiranno in una personalizzazione del profilo più ampia.

## Obiettivi

1. Missioni personali: **3 giornaliere, 3 settimanali, 2 mensili**, scelte da un algoritmo che mette il
   giocatore in un **gruppo** (Ritmo × Stile) e tara obiettivi e tipi di missione su quel gruppo.
2. Missioni comuni (1–3 attive per ambito), scritte a mano in una tabella sul server, con barra **personale**
   (ognuno la completa per sé; niente barra collettiva).
3. Progresso calcolato **solo dalle catture fatte dentro il periodo** della missione, ripetizioni escluse.
4. Premi decisi e verificati dal **server** (ricalcola il progresso dalle carte), con finestra di riscatto.
5. Serie di giorni funzionante, con stato "in pericolo" e salvataggio con una Rara.
6. Badge salvati (locale + server) per le mensili e le comuni completate.
7. UI in Oggi: selettore di periodo con pallini numerati.

## Non-obiettivi

- Vetrina dei badge / personalizzazione del profilo (progetto successivo). In questo lavoro il badge si vede
  nella riga della missione riscattata.
- Notifiche (serie in pericolo, missioni nuove), premi per la serie, ritaratura della curva dei livelli.
- Barra collettiva per le missioni comuni, classifiche.
- Dipendere dal catalogo dei modelli (ADR 0001): le missioni confrontano marca/modello per nome; l'aggancio
  al catalogo è previsto ma non costruito.

## Anti-obiettivi (sarebbe un fallimento anche se funziona)

- Missioni che si completano all'apertura dell'app senza uscire a fotografare.
- Premi che il telefono può gonfiare (importo o completamento falsificati).
- Missioni che cambiano a metà periodo, o diverse tra due telefoni dello stesso utente.
- UI rumorosa: aloni, neon, numeri che rotolano, card identiche in fila (vedi DESIGN.md).

## Decisioni dell'utente

- **Layout B**: in Oggi, sotto il blocco livello, un selettore **Oggi · Settimana · Mese · Comuni** e un
  solo elenco alla volta.
- **Pallino rosso con numero** sul segmento = missioni completate da riscattare; **pallino verde con
  numero** = missioni nuove non ancora viste (sparisce aprendo il segmento). Se ci sono entrambi si mostra il
  rosso. Pallini leggermente più piccoli del mockup b3. Niente etichetta "NEW" testuale.
- Quantità: 3 giornaliere (rinnovo a mezzanotte), 3 settimanali (lunedì), 2 mensili (il 1°), comuni 1–3.
- Badge solo per **mensili e comuni**; giornaliere e settimanali danno PE + valuta.
- **Una mensile** è sempre una **lista di modelli bersaglio** ("una tra F40, Countach, 959…").
- **Su misura per gruppo**: l'algoritmo inserisce il giocatore in un gruppo e le missioni sono pensate per
  quel gruppo.
- Missioni comuni con barra personale, uguale per tutti nell'ambito.
- **Finestra di riscatto**: una missione completata resta riscattabile **2 giorni dopo la fine** del periodo
  (pallino rosso ancora acceso), poi si perde.
- **Serie**: un giorno conta con **una cattura qualsiasi** (non ripetizione). Se salti un giorno, il giorno
  dopo la serie è **in pericolo** e si salva solo catturando una **Rara o superiore**; altrimenti torna a
  **0**. Due giorni saltati di fila: persa *(mia regola, l'utente l'ha accettata)*.
- Premi indicativi accettati: giornaliere 60–150 PE, settimanali 250–500, mensili 800–1.500 + badge, comuni
  ~500–1.500 + badge. Valuta = PE/4 come oggi.

## Glossario (nuovi termini — vanno in `docs/GLOSSARY.md`)

- **Missione**: un compito con un obiettivo numerico in un **periodo**; sostituisce "obiettivo/sfida".
- **Periodo**: giorno, settimana (lun–dom) o mese di calendario, all'ora del telefono.
- **Missione comune**: missione scritta a mano, uguale per tutti in un **ambito**.
- **Ambito**: Mondo, Europa o un Paese (es. Italia). *Avoid*: "area" (che è il quartiere della carta).
- **Gruppo**: la coppia Ritmo × Stile del giocatore, calcolata all'inizio di ogni periodo.
- **Ritmo**: Occasionale, Abituale, Cacciatore. **Stile**: Rarità, Epoca, Esploratore, Marca, Generalista.
- **Modello di missione**: una delle voci del catalogo delle missioni (regola + obiettivi per ritmo +
  premio). *Avoid*: "template" nella UI.
- **Riscatto**, **finestra di riscatto**.
- **Serie**, **giorno attivo**, **serie in pericolo**, **salvataggio**.
- **Badge**.

## Come funziona

### Regola di una missione (gemella client/server)

Una missione è **dati**, non una closure: una `MissionRule` serializzabile in JSON, valutata identica in
Swift e in SQL (stesso schema di `CardCopies` ↔ `private.award_card`: si cambiano in coppia).

Campi (tutti opzionali tranne `count`):

| Campo | Significato |
|---|---|
| `count` | `cards` (numero di carte) · `models` (chiavi marca\|modello distinte) · `makes` (marche distinte) · `areas` (quartieri distinti, area vuota esclusa) |
| `min_rarity` | `Rara` / `Epica` / `Leggendaria`: rarità minima |
| `year_from`, `year_to` | anno compreso (inclusivi); le carte con anno 0 non contano |
| `min_power` | potenza minima |
| `makes` | marca tra queste (normalizzate) |
| `models` | lista bersaglio `"marca|modello"` normalizzati; una carta corrisponde se la sua chiave è uguale o comincia con `bersaglio + " "` (es. `porsche|911` prende "911 Carrera") |
| `fresh` | `model` · `make` · `area`: solo carte la cui chiave di quel tipo **non** compare in nessuna carta (non ripetizione) catturata **prima dell'inizio del periodo** |

Normalizzazione: quella di `CardCopies.key` / `private.norm` (minuscole, spazi ridotti). Sempre esclusi
`isRepeat`. Finestra: `capturedAt ∈ [inizio, fine)`.

**Aggancio al catalogo** (non costruito): quando le carte avranno un riferimento al catalogo, `models`
potrà contenere id e si aggiungeranno campi tipo `tags` ("italiana", "supercar"). Le regole esistenti
restano valide perché il confronto per nome resta il fallback (come l'album, ADR 0001).

### Modelli di missione (pool)

Ogni modello ha: id, periodo, slot, regola, **obiettivo per ritmo** (Occasionale/Abituale/Cacciatore),
premio = `min(max, base + perUnità × obiettivo)`, stile preferito (o nessuno), badge sì/no, parametri
ammessi. Il pool vive **nel codice dell'app** e, gemello, nella tabella `mission_templates` del server
(che è l'autorità sull'importo e sulla regola).

Pool iniziale (titoli italiani; i numeri sono il punto di partenza del bilanciamento):

**Giorno** — slot *volume* (1) + slot *extra* (2 diverse)

| id | titolo | regola | obiettivi O/A/C | premio | stile |
|---|---|---|---|---|---|
| `d_cards` | Cattura N auto | cards | 1/3/6 | 40+20·N ≤160 | volume |
| `d_rare` | Una Rara o superiore | cards, min Rara | 1/1/2 | 60+40·N ≤140 | Rarità |
| `d_epic` | Un'Epica o superiore | cards, min Epica | 1/1/1 | 130 | Rarità |
| `d_vintage` | Un'auto prima del 1990 | cards, year_to 1989 | 1/1/2 | 70+40·N ≤150 | Epoca |
| `d_newarea` | In un quartiere nuovo | cards, fresh area | 1/1/2 | 60+40·N ≤140 | Esploratore |
| `d_makes` | N marche diverse | makes | 2/2/3 | 40+30·N ≤130 | Generalista |
| `d_newmodel` | Un modello che non hai | models, fresh model | 1/1/2 | 60+40·N ≤140 | Generalista |
| `d_power` | Potenza 80+ | cards, min_power 80 | 1/1/2 | 70+40·N ≤150 | Marca |

**Settimana** — slot *volume* (1), *varietà* (1), *stile* (1)

| id | titolo | regola | obiettivi O/A/C | premio | slot · stile |
|---|---|---|---|---|---|
| `w_cards` | Cattura N auto | cards | 5/15/40 | 150+10·N ≤500 | volume |
| `w_makes` | N marche diverse | makes | 3/5/8 | 150+30·N ≤400 | varietà |
| `w_areas` | N quartieri diversi | areas | 2/4/6 | 150+40·N ≤400 | varietà · Esploratore |
| `w_newmodels` | N modelli nuovi | models, fresh model | 2/5/10 | 150+30·N ≤450 | varietà |
| `w_rare` | N Rare o superiori | cards, min Rara | 2/4/8 | 150+30·N ≤400 | stile · Rarità |
| `w_epic` | N Epiche o superiori | cards, min Epica | 1/2/3 | 200+100·N ≤500 | stile · Rarità |
| `w_vintage` | N auto prima del 1990 | cards, year_to 1989 | 1/3/5 | 150+50·N ≤400 | stile · Epoca |
| `w_decade` | Un'auto degli anni '70 | cards, param `decade` | 1/2/3 | 200+80·N ≤450 | stile · Epoca |
| `w_make` | N auto di Porsche | cards, param `make` | 2/4/6 | 150+40·N ≤400 | stile · Marca |

**Mese** — slot *lista bersaglio* (1, badge) + slot *stile* (1, badge)

| id | titolo | regola | obiettivi O/A/C | premio | stile |
|---|---|---|---|---|---|
| `m_list_icons` | Icone anni '80 e '90 | models: ferrari f40, ferrari testarossa, lamborghini countach, porsche 959, bmw m1, lancia delta integrale, audi quattro | 1/1/2 | 1000+250·(N−1) ≤1250 | Rarità, Epoca |
| `m_list_hothatch` | Piccole cattive | models: volkswagen golf gti, abarth 595, peugeot 205 gti, renault clio rs, ford fiesta st, honda civic type r, mini cooper s | 1/2/3 | 800+200·(N−1) ≤1200 | Generalista, Esploratore |
| `m_list_italian` | Sportive italiane | models: alfa romeo giulia quadrifoglio, alfa romeo 4c, maserati mc20, lamborghini huracan, ferrari 296, ferrari roma | 1/1/2 | 1000+250·(N−1) ≤1250 | Marca, Rarità |
| `m_list_german` | Sportive tedesche | models: porsche 911, bmw m3, bmw m4, audi rs, mercedes-benz amg | 1/2/3 | 800+200·(N−1) ≤1200 | Marca, Generalista |
| `m_newmodels` | N modelli nuovi | models, fresh model | 8/20/50 | 600+15·N ≤1500 | Generalista |
| `m_areas` | N quartieri diversi | areas | 4/8/15 | 600+50·N ≤1500 | Esploratore |
| `m_legend` | Una Leggendaria | cards, min Leggendaria | 1/1/2 | 1200+300·(N−1) ≤1500 | Rarità |
| `m_vintage` | N auto prima del 1990 | cards, year_to 1989 | 3/8/15 | 600+40·N ≤1200 | Epoca |
| `m_makes` | N marche diverse | makes | 6/12/20 | 600+40·N ≤1400 | Marca, Generalista |

Le liste bersaglio contano con `count: models` (due foto della stessa auto della lista valgono 1).
Le liste includono modelli del riconoscimento di prova (Delta Integrale, Golf GTI, Abarth 595, Mini Cooper
S, Giulia Quadrifoglio, 911, M3) così si possono provare sul telefono.

Parametri: `w_decade` riceve `decade` (1950…2010, il server ne ricava `year_from = decade`,
`year_to = decade + 9`); `w_make` riceve `make` (una sola marca). Il client li sceglie (decennio/marca
più presenti nella collezione o, per "spingere verso il nuovo", un decennio non ancora coperto); il
server accetta solo i parametri ammessi dal modello e nella forma ammessa.

### Gruppo (tailoring)

Calcolato dalle carte non ripetizione catturate **prima dell'inizio del periodo** (mai da quelle dentro il
periodo: così le missioni non cambiano a metà e sono riproducibili su un altro telefono dopo la sync).

- **Ritmo** = catture nei 28 giorni prima dell'inizio, diviso 4 (a settimana): < 5 Occasionale,
  5–19 Abituale, ≥ 20 Cacciatore. Nessuna carta → Occasionale.
- **Stile** (servono ≥ 10 carte in totale, altrimenti Generalista): Rarità se Epiche+ ≥ 15%; Epoca se auto
  prima del 1990 ≥ 30%; Esploratore se quartieri distinti ≥ 5 e ≥ 50% delle carte; Marca se una marca
  ≥ 40%. Se ne valgono più d'uno vince quello che supera di più la propria soglia (in rapporto); a parità
  l'ordine è Rarità, Epoca, Esploratore, Marca.

### Generazione

- Seed stabile = FNV-1a di `"<ownerId o 'guest'>|<periodo>|<inizio yyyy-MM-dd>"` → generatore SplitMix64.
  (Mai `hashValue`: cambia a ogni avvio.)
- Per ogni slot si sceglie un modello tra quelli di quello slot con peso 1, ×3 se il suo stile coincide con
  lo stile del giocatore; senza ripetere modelli nello stesso periodo. Obiettivo dal ritmo.
- Parametri dei modelli parametrici scelti dal seed tra i candidati (vedi sopra).
- Identità: `"<periodo>:<inizio>|<idModello>"` (es. `week:2026-10-19|w_makes`).

### Missioni comuni

Tabella `community_missions` sul server (scritta a mano da noi via SQL/MCP): id, ambito (`world`, `europe`
o codice Paese ISO come `IT`), titolo it/en, `starts_on`/`ends_on` (date incluse), regola, obiettivo,
premio, `badge_id`. L'app scarica quelle attive (e quelle finite da ≤ 2 giorni) a ogni sync e le tiene in
cache per l'offline. Ambiti mostrati: Mondo sempre, Europa se la **Regione del telefono** è europea, il
Paese se coincide (*mia scelta: niente posizione, niente dati nuovi al cloud*). Il server **non** controlla
l'ambito (rischio basso: al massimo un utente non italiano riscatta una missione italiana).
Ospite senza account: nessuna missione comune (servono il server e un account).
Il progresso si conta da `starts_on` a fine `ends_on`, all'ora del telefono.

### Riscatto e verifica sul server

Nuova tabella `mission_claims` (le vecchie `challenge_claims`/`challenge_rewards` restano, non più usate).
Il client inserisce: periodo (`day`/`week`/`month`/`community`), `period_start` (data), `mission_id`
(id del modello o della missione comune), `goal`, `params`, `window_start` (istante di inizio periodo
all'ora del telefono). Un trigger `private.award_mission`:

1. **Finestra temporale**: `window_start` deve stare tra `period_start 00:00 UTC − 14 h` e `+ 12 h`
   (qualsiasi fuso); fine = `window_start + 1 giorno / 7 giorni / 1 mese`; il riscatto è accettato da
   `window_start` a **fine + 2 giorni**. `period_start` coerente col periodo (lunedì per la settimana, il 1°
   per il mese). Per le comuni la finestra è `starts_on`–`ends_on` (con lo stesso margine di fuso) + 2 giorni.
2. **Tetti**: max 3 / 3 / 2 riscatti personali per giorno / settimana / mese; una sola volta per missione
   (chiave primaria).
3. **Obiettivo** dentro `goal_min`–`goal_max` del modello; parametri ammessi.
4. **Progresso** ricalcolato con `private.mission_progress` (stessa regola del client) sulle carte del
   proprietario nella finestra: se < obiettivo → rifiuto.
5. **Premio** dal server (`min(max, base + perUnità × goal)` o quello della missione comune), scritto nella
   riga, PE + valuta con `private.grant_reward`; se il modello/missione ha badge → riga in `player_badges`.

Errori di regola = `P0001` (il client scarta il riscatto, come oggi). Il client manda prima le carte e poi i
riscatti (già così in `SyncService.pushOnce`), quindi il server vede le carte prima di contare.
Il client assegna PE localmente all'istante (come oggi); al pull il profilo del server è la verità.

### Serie

Ricavata dalle carte, non salvata come contatore (il campo `PlayerProfile.streak` resta, aggiornato col
valore calcolato per le analytics). Giorno attivo = almeno una carta non ripetizione quel giorno
(calendario del telefono). Partendo da oggi all'indietro:

- Oggi attivo → la catena include oggi. Oggi non attivo ma ieri sì → serie intatta, oggi "da fare".
- Ieri non attivo, l'altro ieri sì → **in pericolo**: si salva solo con una Rara+ oggi. Se oggi c'è una
  Rara+ → salvata, la catena salta il buco (il giorno saltato non conta). Se oggi c'è solo una Comune →
  ancora in pericolo fino a mezzanotte (mostra il valore vecchio); a fine giornata senza Rara+ la vecchia
  serie è persa e quella nuova parte da 1 (la Comune di oggi).
- Due giorni di fila non attivi → **0**.
- Camminando all'indietro, un buco di un giorno si salta solo se il giorno dopo il buco ha una Rara+.

### Badge

`player_badges (owner_id, badge_id, earned_at)` scritta solo dal trigger. Id: mensili `month:<yyyy-MM>|<idModello>`,
comuni il `badge_id` della riga. In locale `PlayerProfile.badges: [String]` (riempito dal riscatto e dal
pull). La riga della missione riscattata mostra "Badge ottenuto"; la vetrina è un progetto futuro.

### Stato locale (SwiftData, campi nuovi con default → migrazione leggera)

In `PlayerProfile`: `claimedMissions: [String]` (identità riscattate), `pendingMissionClaims: [String]`
(payload JSON in attesa di invio), `seenMissions: [String]` (per il pallino verde; si potano le identità di
periodi chiusi), `badges: [String]`. Le missioni comuni in cache in un file JSON nella cartella Caches
(*mia scelta: nessun nuovo `@Model`, così non si tocca il container in `CarSpotApp`*). I vecchi
`claimedChallenges`/`pendingClaims` restano e vengono ignorati.

## UI (Oggi)

Sotto il blocco livello:

- **Selettore** a 4 segmenti (Oggi, Settimana, Mese, Comuni) costruito col design system (capsula `nested`,
  pillola selezionata che scorre; Reduce Motion → senza scorrimento). Pallini numerati piccoli nell'angolo
  in alto a destra dell'etichetta: rosso (`CSColor.danger`) = da riscattare, verde (`CSColor.success`) =
  nuove; il rosso vince. Il segmento selezionato si ricorda nella sessione.
- Eyebrow "N di M" a sinistra e "finisce tra 6 h / 3 g" a destra.
- Un `Surface(.group)` con le righe (`ChallengeRow` evoluta): obiettivi ≤ 5 → segmenti come oggi; > 5 →
  barra continua + "7 di 12". Premio "+N PE", "Riscatta" se completata, "Fatto" (+ "Badge ottenuto" per
  mensili/comuni) se riscattata. Badge in palio indicato nella riga ("badge").
- Missioni del periodo **precedente** completate e non riscattate (entro i 2 giorni): un secondo gruppo
  sotto, "Settimana scorsa · riscatta entro martedì".
- Comuni: etichetta d'ambito (MONDO / EUROPA / ITALIA) accanto al titolo, "fino al 30 nov". Vuoto:
  "Nessuna missione comune in corso".
- Blocco livello: la fiammella diventa ambra con "in pericolo" e sotto una riga `nested`: "Ieri non hai
  catturato. Prendi una Rara o superiore entro mezzanotte per salvare la serie."

## Bilanciamento (riferimento)

Carte 20/55/130/260 PE; livello: passo 100 + 60·(l−1) (al livello 10 servono 640 PE). Un Abituale che fa
tutto in un mese: giornaliere ~30 × 300 = 9.000, settimanali ~4 × 900 = 3.600, mensili ~2.000, comuni
~1.000. Oggi gli obiettivi del giorno danno già fino a ~400 PE/giorno, quindi l'ordine di grandezza resta
simile. La curva dei livelli andrà ritarata più avanti (non-obiettivo).

## Vincoli

- Swift 6 strict, `@MainActor` espliciti, logica pura testabile (Swift Testing) per regola, gruppo,
  generazione, finestre, serie.
- File toccabili: `ChallengeEngine.swift` (sostituito), `TodayView.swift`, `PlayerProfile.swift`,
  `Models/SpotCard.swift` (solo tipi sfide), `CloudStore`/`SupabaseCloudStore`/`SyncService` (solo
  riscatti), nuovi file in `Features/Today/`, `Services/Game/`, `CarSpotTests/`, migration **0011**.
  Non toccare `StoredCard`, `CaptureViewModel`, `RootShellView`, `CollectionView`, `CardDetailView`,
  `SpotCardView`, `Localizable.xcstrings`, `CLAUDE.md`, `tools/`.
- Stringhe nuove con `String(localized:)`: il catalogo lo aggiorna la sessione principale.
- Migration applicata sul remoto solo dopo l'ok esplicito dell'utente, poi `get_advisors`.

## Scelte mie dopo la revisione (da controllare)

- **Conteggio distinto**: aggiunto `count: models`; "modelli nuovi" e liste bersaglio contano modelli
  distinti, non foto.
- **Riscatto rifiutato dal server** (`P0001`): il client toglie la missione da `claimedMissions` (la riga
  torna com'era: "Riscatta" se in locale risulta ancora completa), logga e manda la metrica; i PE locali
  tornano quelli del server al pull successivo. Gli altri errori (rete, 5xx) restano in coda e si ritentano
  finché la finestra è aperta, poi si scartano. Il PE locale resta immediato come oggi. Rifiuti attesi
  rari: le carte partono prima dei riscatti e un errore su una carta ferma il giro.
- **Pool che cambia dopo un aggiornamento**: accettato (app di un solo sviluppatore). Un nuovo modello nel
  pool può rimescolare le missioni del periodo in corso dopo l'aggiornamento; quelle già riscattate restano
  riscattate (identità per id). Sul server i modelli non si cancellano: colonna `active`; il server accetta
  riscatti anche di modelli non attivi purché il periodo sia quello in cui erano attivi (semplificazione:
  accetta sempre i modelli presenti in tabella).
- **Ospite**: come oggi gioca e riscatta in locale (PE locali, niente sync, niente comuni); al primo login
  vale il reset già esistente (`resetForOwner`).
- **Il server non verifica che la missione fosse proprio assegnata** al giocatore (servirebbe il generatore
  lato server). Il rischio è limitato: progresso reale richiesto e tetti 3/3/2; al massimo uno sceglie i
  modelli più remunerativi del periodo. Va nell'ADR.
- **Comuni**: `goal` deve essere uguale a quello della riga; un solo riscatto per missione; nessun altro
  tetto.
- **Migration**: numero **0011** come da incarico, con timestamp reale al momento dell'applicazione (la
  cronologia remota ordina per timestamp; un buco nella numerazione se la 0010 del catalogo non è ancora
  applicata non è un problema).

## Lasciato a chi costruisce

- Nomi dei tipi Swift e struttura dei file; forma esatta del JSON della regola purché identica ai due lati.
- Testi esatti delle righe, icone SF Symbols per modello.
- Come scegliere decennio/marca dei modelli parametrici, purché deterministico dal seed e dai dati prima del
  periodo.
