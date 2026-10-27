# CarSpot

Car spotting reale trasformato in un gioco di carte collezionabili: fotografi un'auto per strada e diventa
una carta della tua collezione.

## Gioco

**Carta**:
Il risultato di una cattura riuscita: un'auto riconosciuta (marca, versione, anno) con la sua rarità e la
foto anonimizzata dell'utente.
_Avoid_: Spot, avvistamento (per la carta salvata)

**Copia**:
Una delle carte che l'utente possiede della stessa versione; la prima vale l'XP pieno, le successive meno.
_Avoid_: Duplicato

**Ripetizione**:
Una carta della stessa auto già catturata (stessa versione, stesso quartiere, entro 24 ore): resta in
cronologia, non conta in collezione e non dà punti.
_Avoid_: Doppione (che è una copia valida)

**Rarità**:
Il livello di una carta o di una versione: Comune, Rara, Epica, Leggendaria; ognuna ha un colore e un
materiale.

## Catalogo e album

**Catalogo**:
L'elenco di riferimento di tutte le auto collezionabili, uguale per tutti gli utenti.

**Marca**:
La casa automobilistica (Fiat, Volkswagen). Nell'album è un set da completare.
_Avoid_: Brand, costruttore

**Modello**:
Un'auto del catalogo dentro una marca (Golf, Panda, 911), indipendente dalla generazione; è una casella
dell'album.
_Avoid_: Generazione (che non è una casella)

**Versione**:
Una variante con nome proprio di un modello (Golf GTI, Giulia Quadrifoglio), compresa la versione base; è
la sotto-carta che si colleziona dentro il modello.
_Avoid_: Allestimento, variante, trim

**Album**:
La vista della collezione organizzata per marca e modello, con i modelli trovati e quelli mancanti.
_Avoid_: Pokédex

**Trovato**:
Stato di un modello di cui l'utente possiede almeno una versione.

**Ombra**:
Come appare nell'album un modello o una versione non ancora trovati: la sagoma dell'immagine standard.
_Avoid_: Silhouette, carta bloccata

**Immagine standard**:
L'immagine di catalogo di una versione, uguale per tutti, mostrata nell'album al posto delle foto
dell'utente.
_Avoid_: Foto (che è sempre dell'utente)

**Marca completa**:
Una marca di cui l'utente ha trovato tutti i modelli.

**Fuori catalogo**:
Una carta che non corrisponde a nessuna versione né modello del catalogo; resta visibile nell'album con la
foto dell'utente.

## Missioni e serie

**Missione**:
Un compito con un obiettivo numerico da completare con le catture fatte dentro un periodo; dà PE, valuta e a
volte un badge.
_Avoid_: Obiettivo, sfida, challenge, quest

**Periodo**:
Il giorno, la settimana (da lunedì a domenica) o il mese di calendario di una missione, all'ora del telefono.

**Missione personale**:
Una missione scelta per un solo giocatore in base al suo gruppo.

**Missione comune**:
Una missione scritta a mano dal team, uguale per tutti i giocatori di un ambito.
_Avoid_: Evento, missione globale

**Ambito**:
Il pubblico di una missione comune: Mondo, Europa o un Paese.
_Avoid_: Area, regione (l'area è il quartiere di una carta)

**Gruppo**:
Il tipo di giocatore (un ritmo più uno stile) da cui dipendono le missioni personali di un periodo.
_Avoid_: Bucket, segmento

**Ritmo**:
Quante auto cattura di solito un giocatore: Occasionale, Abituale o Cacciatore.

**Stile**:
Cosa caratterizza la collezione di un giocatore: Rarità, Epoca, Esploratore, Marca o Generalista.

**Modello di missione**:
Una voce del repertorio da cui nascono le missioni personali, con la sua regola, gli obiettivi per ritmo e il
premio.
_Avoid_: Template

**Lista bersaglio**:
Un elenco di modelli d'auto di cui la missione chiede di catturarne almeno uno (o più).

**Riscatto**:
L'azione con cui il giocatore incassa il premio di una missione completata.
_Avoid_: Claim

**Finestra di riscatto**:
Il tempo in cui una missione completata si può riscattare: dall'inizio del periodo a due giorni dopo la fine.

**Badge**:
Un riconoscimento permanente ottenuto riscattando una missione mensile o comune.
_Avoid_: Medaglia, trofeo

**Serie**:
Il numero di giorni attivi consecutivi del giocatore.
_Avoid_: Streak

**Giorno attivo**:
Un giorno con almeno una cattura che non è una ripetizione.

**Serie in pericolo**:
Lo stato della serie quando ieri non è stato un giorno attivo: si salva solo catturando oggi una Rara o
superiore.

**Salvataggio**:
La cattura di una Rara o superiore che, il giorno dopo un giorno saltato, tiene in vita la serie.
