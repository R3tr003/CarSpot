---
status: accepted
---

# Catalogo dei modelli: Marca → Modello → Versione su Supabase, abbinato alle carte per nome

L'album della Collezione ha bisogno di un catalogo uguale per tutti (immagine standard, dati per i filtri,
attribuzione delle immagini). Lo teniamo in tre tabelle Supabase in sola lettura (`car_makes`,
`car_models`, `car_variants`), scritte solo dalla pipeline `tools/catalog/` col service role, con le
immagini in un bucket pubblico e uno snapshot JSON dentro l'app per l'offline e l'ospite. La casella
dell'album è il **Modello**; ogni **Versione** (GTI, Quadrifoglio…) è una carta a sé dentro il modello,
per volontà dell'utente; le generazioni non sono caselle.

Le carte salvate **non** hanno un riferimento al catalogo: si abbinano per nome (marca e versione
normalizzati come `CardCopies.key`, poi alias, poi prefisso del modello, poi l'anno per i modelli omonimi),
e quello che non trova posto resta visibile come "Fuori catalogo".

## Considered Options

- **Colonna `variant_id` sulle carte** (in SwiftData e in `public.cards`): abbinamento esatto e query lato
  server, ma richiede di cambiare il riconoscimento, il salvataggio, la sync e le carte già esistenti, e
  lega le carte a id di un catalogo di prova che cambierà. Rimandato a quando il riconoscimento userà il
  catalogo come lista di etichette.
- **Catalogo solo nell'app** (JSON nel bundle): niente backend, ma ogni correzione o immagine nuova richiede
  un aggiornamento dell'app, e il server non potrà mai premiare le marche complete.
- **Rarità come colonna del catalogo**: scartata per ora; l'app la calcola con la stessa `RarityEngine`
  delle carte, così le due non divergono finché non arrivano le specifiche reali.

## Consequences

- Il premio per la marca completa, se fatto lato server, dovrà replicare l'abbinamento per nome o
  aspettare il `variant_id`.
- Rinominare una versione nel catalogo può spostare carte esistenti in "Fuori catalogo": i nomi vecchi
  vanno conservati come alias.
