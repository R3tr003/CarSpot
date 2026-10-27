---
status: accepted
---

# Missioni come regole-dati gemelle, scelte dal telefono e verificate dal server

Le missioni personali sono scelte **sul telefono** (gruppo calcolato dalle carte prima dell'inizio del
periodo, seed stabile per utente e periodo), perché devono funzionare offline e per l'ospite. Ogni missione
è però una **regola in JSON** (`MissionRule`) valutata in modo identico in Swift e in SQL
(`private.mission_progress`), così al riscatto il **server ricalcola il progresso dalle carte** e decide il
premio dalla sua tabella `mission_templates`, invece di fidarsi del telefono come facevano gli obiettivi
del giorno (`challenge_claims`, migration 0004). Regola, catalogo dei modelli di missione e premi vanno
cambiati **in coppia** nei due lati, come `CardCopies` ↔ `private.award_card`.

## Considered Options

- **Generazione sul server** (RPC che assegna le missioni): il server saprebbe esattamente cosa è stato
  assegnato, ma niente missioni offline né per l'ospite e un'altra superficie esposta. Scartata.
- **Fidarsi del client sul completamento** (come la 0004): semplice, ma con premi mensili da 1.000+ PE e
  badge il completamento falso diventa conveniente. Scartata.
- **Closure Swift per le regole** (come il vecchio `ChallengeEngine`): impossibili da replicare sul server
  e da mandare in una tabella per le missioni comuni. Scartata.

## Consequences

- Il server **non** verifica che la missione riscattata fosse davvero assegnata a quel giocatore: chi
  manomette il client può scegliere i modelli di missione più remunerativi del periodo, ma serve comunque
  il progresso reale sulle carte e valgono i tetti 3/3/2 per periodo. Accettato.
- I periodi seguono l'ora del telefono: il client manda inizio e fine della finestra e il server
  accetta solo mezzanotti plausibili (UTC−12…UTC+14), durata del calendario ±1 h e nessuna
  sovrapposizione con finestre dello stesso tipo già riscattate (migration 0012). Resta fidato il fuso
  scelto entro quei limiti: chi cambia fuso viaggiando può vedersi rifiutare un riscatto che si
  sovrappone a uno precedente.
- Il premio si paga in un trigger AFTER INSERT (0012): una riga scartata da `ON CONFLICT DO NOTHING`
  non paga; il BEFORE valida soltanto.
- Le carte restano la fonte di fiducia: chi inserisce carte false ottiene anche missioni false. È un
  problema dell'anti-cheat delle carte, non delle missioni.
- Aggiungere un modello di missione al pool può rimescolare le missioni del periodo in corso dopo un
  aggiornamento dell'app; i modelli sul server non si cancellano.
- Le liste bersaglio confrontano marca/modello per nome (come l'album, ADR 0001); quando le carte avranno
  un riferimento al catalogo la regola potrà usare gli id senza cambiare forma.
