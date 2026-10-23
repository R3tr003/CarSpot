# Tracking plan analytics (Mixpanel EU)

Analytics di **prodotto** (funnel, attivazione, retention, engagement). Le metriche
tecniche (latenze, crash, errori, permessi di sistema) stanno in Sentry: qui non si duplicano.

Codice: `CarSpot/Services/Analytics/` — `Analytics.swift` (enum `AnalyticsEvent` e tipi dei
valori), `MixpanelAnalytics.swift` (nomi e proprietà in snake_case, super/profile properties),
`AnalyticsProfileSync.swift` (snapshot del giocatore). Per aggiungere un evento: nuovo case in
`AnalyticsEvent`, nome e proprietà in `MixpanelAnalytics.swift`, una riga qui. **I nomi
esistenti non si rinominano mai** (i dati storici devono restare confrontabili).

## Regole privacy (inderogabili)

- Niente parte senza consenso GDPR (`AnalyticsConsent.granted`): `track` e `updateProfile`
  scartano tutto altrimenti. Mixpanel parte in opt-out e viene acceso solo dal consenso.
- `identify` solo con l'id Clerk (`user_…`). `useIPAddressForGeoLocation = false`,
  `trackAutomaticEvents = false`: nessuna posizione da IP, nessun evento automatico.
- **Mai** email, nome, cognome, username, telefono, foto, targhe, coordinate, città/zona,
  testo libero, messaggi d'errore.
- Proprietà solo: valori enumerati, numeri, booleani, dati non personali dell'auto
  (`make` = marca, `rarity`). Mai modello + anno + zona insieme (e il modello non viene mai
  inviato).
- `has_real_name` è un booleano: il nome non lascia mai l'app verso Mixpanel.
- Spegnere le statistiche invia prima `analytics_disabled`, svuota la coda (`flush`) e poi
  fa `optOutTracking`, che cancella ciò che non è partito.

## Super properties

Registrate con `registerSuperProperties` a ogni avvio e dopo `reset()` (che le azzera).
Sono su **ogni** evento.

| Proprietà | Valori | Note |
|---|---|---|
| `app_version` | es. `1.0` | `CFBundleShortVersionString` |
| `build` | es. `42` | `CFBundleVersion` |
| `app_language` | `it` \| `en` | lingua in cui gira l'app (`Locale.app`), non quella del telefono |
| `environment` | `development` \| `production` | `#if DEBUG`: filtrare `production` nei report |

## Proprietà del profilo utente (People)

`people.set` solo con consenso **e** utente identificato; altrimenti lo snapshot aspetta e
parte dopo `identify`/consenso. Gli snapshot identici all'ultimo inviato si scartano.
Aggiornato da `AnalyticsProfileSync.refresh(in:)` nei punti: dopo il login (e di nuovo a sync
finito), dopo salvataggio carta e riscatto sfida (`PlayerStore.reportProgress`), all'avvio,
al ritorno in primo piano (`RootGate`), dopo il cambio del nome reale.

| Proprietà | Tipo | Origine |
|---|---|---|
| `level`, `xp` | int | `PlayerProfile` |
| `cards_count` | int | carte in collezione |
| `legendary_count`, `epic_count` | int | carte per rarità |
| `streak_days` | int | `PlayerProfile.streak` — **oggi costante a 1**: la serie non viene mai aggiornata nel codice (vedi punti aperti) |
| `has_real_name` | bool | esiste nome+cognome in Clerk (mai il nome) |
| `app_language` | `it` \| `en` | come super property |
| `signup_method` | `apple` \| `google` \| `email` \| `phone` | solo per chi si registra con questa versione (`is_new_user == true`); salvato in UserDefaults e azzerato al logout |
| `first_capture_at` | data | `setOnce`: data della prima carta |

## Eventi

Legenda file: `Funzione` = punto di invio nel codice. "Consenso" = come per tutti, parte solo
se concesso.

### Ciclo di vita e onboarding

| Evento | Quando parte | Proprietà (valori ammessi) | File : funzione |
|---|---|---|---|
| `app_opened` | App in primo piano (una volta per sessione; gli alert di sistema non contano) | `kind`: `cold` \| `warm` | `Services/Errors/AppTelemetry.swift` : `didBecomeActive` |
| `onboarding_step_viewed` | Cambio pagina dell'onboarding (anche la prima) | `step`: 0…4 (4 = consenso) | `Features/Onboarding/OnboardingFlow.swift` : `body` (`onChange(of: page)`) |
| `consent_given` | Consenso statistiche concesso (solo se `granted`; è il **primo** evento tracciato) | `granted`: `true`; `origin`: `onboarding` \| `settings` | `OnboardingFlow.swift` : `finish(with:)`; `Features/Profile/SettingsView.swift` : `privacySection` |
| `onboarding_completed` | Scelta del consenso (qualunque) | — | `OnboardingFlow.swift` : `finish(with:)` |
| `analytics_disabled` | Toggle "Statistiche anonime" spento, **prima** dello spegnimento | — | `SettingsView.swift` : `privacySection` |

> **Nota `onboarding_step_viewed`:** l'ultima pagina è proprio quella del consenso, quindi nel
> primo avvio **nessuna** pagina arriva a Mixpanel (il consenso non c'è ancora). L'evento è
> mantenuto per completezza (utile solo se in futuro il consenso viene chiesto prima).
> Il funnel di onboarding si legge da `consent_given` / `onboarding_completed`.

### Accesso e account

| Evento | Quando parte | Proprietà | File : funzione |
|---|---|---|---|
| `sign_in_started` | Si sceglie un metodo (OAuth: al tocco; email/telefono: all'apertura del foglio codice) | `method`: `apple` \| `google` \| `email` \| `phone` | `Features/Onboarding/LoginView.swift` : `signIn(method:_:)`, `openCode(_:)` |
| `sign_in_failed` | Accesso non riuscito | `method` (come sopra); `reason`: `wrong_code` \| `expired` \| `unsupported_country` \| `cancelled` \| `other` | `LoginView.swift` : `signIn(method:_:)` (annullo OAuth = `cancelled`); `Features/Onboarding/CodeSignInView.swift` : `trackFailure(_:)` (invio e verifica codice) |
| `signed_in` | Sessione attiva dopo l'accesso | `method`; `is_new_user`: bool (**assente** con auth locale: non distingue) | `LoginView.swift` : `signIn`; `CodeSignInView.swift` : `verify()`. `is_new_user` da `AuthService.lastSignInIsNewUser` (Clerk: `SignUp` vs `SignIn`) |
| `signed_out` | Lo stato auth passa a uscito (anche dopo cancellazione account) | — | `Features/Root/RootGate.swift` : `handle(_:from:)` |
| `account_deleted` | Conferma eliminazione account, **prima** di chiamare Clerk | — | `SettingsView.swift` : `deleteAccount()` |

### Setup profilo

| Evento | Quando parte | Proprietà | File : funzione |
|---|---|---|---|
| `setup_step_completed` | Si passa oltre un passo | `step`: `welcome` \| `real_name` \| `username` \| `permissions` \| `photo` (la foto conta anche se saltata: chi la imposta lo dice `avatar_updated`) | `Features/Onboarding/ProfileSetupFlow.swift` : `advance()`, `saveRealName()`, `saveName()` |
| `profile_setup_completed` | Fine del setup ("Entra in CarSpot") | — | `ProfileSetupFlow.swift` : `finish()` |
| `permission_answered` | L'utente risponde al prompt di sistema (una volta per permesso) | `permission`: `camera` \| `location`; `granted`: bool | `Features/Onboarding/ProfileSetupPermissionsStep.swift` : `requestCamera()`; `Services/Camera/CameraController.swift` : `prepare()`; `Services/Location/LocationManager.swift` : `locationManagerDidChangeAuthorization` |
| `real_name_updated` | Nome/cognome salvati | `origin`: `setup` \| `settings` | `ProfileSetupFlow.swift` : `saveRealName()`; `SettingsView.swift` : `PersonNameEditor.save()` |
| `avatar_updated` | Foto profilo cambiata o rimossa dall'utente (non l'import automatico da Google) | `action`: `set` \| `removed` | `Services/Backend/ProfileAccount.swift` : `setAvatar(jpeg:)`, `removeAvatar()` |

### Navigazione

| Evento | Quando parte | Proprietà | File : funzione |
|---|---|---|---|
| `tab_viewed` | Cambio tab (e prima tab all'apertura). La mappa è la tab `map`: niente evento a parte | `name`: `today` \| `collection` \| `map` \| `capture` | `Features/Root/RootShellView.swift` : `panel` (`onChange(of: selection)`) |
| `panel_detent_changed` | Altezza del pannello cambiata | `detent`: `small` \| `medium` \| `large` | `RootShellView.swift` : `panel` (`onChange(of: detent)`) |
| `profile_opened` | Si apre il profilo dall'avatar | — | `RootShellView.swift` : `panel` (`onChange(of: accountSheet)`) |
| `settings_opened` | Si apre Impostazioni dall'avatar | — | idem |

### Cattura e collezione

| Evento | Quando parte | Proprietà | File : funzione |
|---|---|---|---|
| `capture_started` | Parte la pipeline su una foto | `source`: `camera` \| `library` \| `auto` (`auto` = solo debug `-autoCapture`) | `Features/Capture/CaptureViewModel.swift` : `runPipeline(data:source:)` |
| `capture_completed` | Esito della pipeline (anche per un riconoscimento ripetuto con "Riprova"). L'annullamento non si traccia | `outcome`: `success` \| `no_vehicle` \| `unreadable` \| `recognition_failed` \| `offline` \| `error`; `source`: `camera` \| `library`; `duration_ms`: int; `candidates`: int (0 se non success) | `CaptureViewModel.swift` : `finish(_:candidates:)` (mappatura in `outcome(for:)`) |
| `card_saved` | Carta salvata in collezione | `rarity`: `comune` \| `rara` \| `epica` \| `leggendaria`; `make`: marca; `is_first_card`: bool; `is_new_make`: bool (prima volta per quella marca, confronto esatto sul testo); `xp_gained`: int (premio della rarità) | `CaptureViewModel.swift` : `persist(into:)` |
| `card_viewed` | Si apre il dettaglio di una carta | `rarity` (come sopra) | `Features/Collection/CardDetailView.swift` : `onAppear` |
| `collection_filtered` | Cambia il filtro per rarità | `filter`: `all` \| `comune` \| `rara` \| `epica` \| `leggendaria` | `Features/Collection/CollectionView.swift` : `body` (`onChange(of: filter)`) |

### Gioco

| Evento | Quando parte | Proprietà | File : funzione |
|---|---|---|---|
| `challenge_claimed` | Premio di una sfida riscattato | `id`: `today2` \| `vintage` \| `rarePlus` \| `epic` \| `trio` \| `powerful` (è già il **tipo** di sfida: `ChallengeEngine` non espone altro); `reward`: int (PE) | `Features/Today/TodayView.swift` : `claim(_:)` |
| `level_up` | Il livello sale dopo una cattura o un riscatto (un evento solo anche se salta più livelli) | `level`: int (nuovo livello) | `Persistence/PlayerProfile.swift` : `PlayerStore.award`, `PlayerStore.claim` (`trackLevelUp`) |

**Non implementato: `streak_updated`.** Nel codice non c'è nessuna logica che aggiorni la
serie (`PlayerProfile.streak` resta 1; `lastActiveDay` non viene mai letto). Quando verrà
scritta, aggiungere l'evento `streak_updated {days}` dove cambia.

## Funnel consigliati

1. **Attivazione** (il principale): `app_opened` → `signed_in` → `profile_setup_completed` →
   `capture_completed` (`outcome = success`) → `card_saved`. Finestra: 7 giorni dal primo
   `app_opened`. Scomporre per `method` (di `signed_in`) e per `app_language`.
2. **Accesso**: `sign_in_started` → `signed_in`, scomposto per `method`; con `sign_in_failed`
   per `reason` si vede dove si perde chi ci prova (es. `unsupported_country` sul telefono).
3. **Setup profilo**: `setup_step_completed` per `step` (ordine: welcome → real_name →
   username → permissions → photo) → `profile_setup_completed`.
4. **Cattura**: `capture_started` → `capture_completed`; breakdown per `outcome` e `source`;
   mediana di `duration_ms`; poi `capture_completed(success)` → `card_saved` (quanti
   confermano il riconoscimento).
5. **Prima carta**: `card_saved` con `is_first_card = true`: tempo dal primo `app_opened`.
6. **Engagement collezione**: `card_saved` → `card_viewed` → `collection_filtered`.

## Retention e metriche

- **Retention**: evento di partenza `card_saved` (oppure `signed_in` per l'installazione),
  evento di ritorno `app_opened`; curve a 1/7/30 giorni. Alternativa più severa: ritorno =
  `card_saved`.
- **DAU / WAU / MAU**: utenti unici di `app_opened` (stickiness = DAU/MAU). Escludere
  `environment = development`.
- **Carte per utente attivo** (settimana): conteggio `card_saved` / utenti unici.
- **Varietà**: quota di `card_saved` con `is_new_make = true`; distribuzione per `rarity`.
- **Progressione**: `level_up` per `level` (a che livello ci si ferma); `xp_gained` medio.
- **Sfide**: `challenge_claimed` per `id` e `reward`.
- **Privacy**: tasso di `consent_given` su `onboarding_completed`; `analytics_disabled` nel
  tempo.
- **Qualità riconoscimento (prodotto)**: quota di `capture_completed` con `outcome` diverso da
  `success`, per `source`. (Latenza e errori tecnici: Sentry.)

## Coorti consigliate

| Coorte | Definizione |
|---|---|
| Attivati | ≥ 1 `card_saved` (oppure profilo `cards_count ≥ 1`) |
| Collezionisti | ≥ 5 `card_saved` negli ultimi 7 giorni |
| A rischio | ≥ 1 `card_saved` in passato **e** nessun `app_opened` da 7 giorni |
| Leggendari | profilo `legendary_count ≥ 1` |
| Registrati ma non attivati | `profile_setup_completed` e nessun `card_saved` dopo 3 giorni |
| Nuovi utenti | `signed_in` con `is_new_user = true` |

## Limiti noti

- `signup_method` e `is_new_user` esistono solo dalle registrazioni fatte con questa versione
  in poi; per gli utenti precedenti manca.
- Eventi inviati prima di `identify` (es. `signed_in` tracciato dalla view un istante prima
  del cambio di stato) hanno un id anonimo che Mixpanel unisce all'utente al primo `identify`.
- `account_deleted` parte prima della cancellazione: se Clerk la rifiuta (offline) l'evento
  resta ma l'utente non è stato cancellato. Dopo una cancellazione riuscita segue un
  `signed_out` (stesso utente) e il `reset`.
- Il profilo utente su Mixpanel **non** viene cancellato all'eliminazione dell'account
  (nessuna PII, ma se serve per conformità: `people.deleteUser()` o richiesta GDPR da Mixpanel).
- `is_new_make` confronta la marca col testo esatto salvato; il conteggio "Marche" in
  Collezione ignora le maiuscole.
