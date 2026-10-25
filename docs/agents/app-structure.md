# Struttura dell'app (dettagli)

Letto da CLAUDE.md quando si lavora su auth/onboarding, servizi esterni o guscio a tab.

## Gate iniziale (auth)
`RootGate` decide cosa mostrare: **onboarding → login → setup profilo → app** in base a
`@AppStorage("hasOnboarded")`, `AppServices.auth.state` (`signedOut`/`guest`/
`signedIn(userId:)`) e `ProfileAccount.needsSetup` (`profiles.onboarded_at` null).
`OnboardingFlow` = carosello Flighty (pag.0 statica con la macchina, le altre animate) +
**ultima pagina consenso statistiche** (GDPR, non saltabile).
`LoginView` = sfondo animato `DottedBackdrop` + Apple + Google + **email** e **telefono** con
codice OTP (`CodeSignInView`, niente password: accesso o registrazione nello stesso flusso).
Niente modalità ospite in UI (`.guest` solo per il debug `-skipAuth`).
`ProfileSetupFlow` (solo la prima volta, dopo il login): nome da spotter univoco
(`^[a-z0-9_.]{3,20}$`, controllo disponibilità) → permessi fotocamera/posizione spiegati →
"Pronto" (scrive `onboarded_at`). Offline o senza Supabase non blocca mai l'accesso.

**Servizi esterni dietro protocollo** (`CarSpot/Services/AppServices.swift`):
- `AppServices.auth: AuthService` → `ClerkAuthService` (ClerkKit) se `Secrets.clerkPublishableKey`
  è una `pk_…`, altrimenti `LocalAuthService` (login simulato, offline). Il token Clerk
  (TTL 1 min) va chiesto a ogni richiesta con `sessionToken()`, mai salvato.
- `SupabaseBackend` (supabase-swift) usa il token Clerk via `accessToken`: **mai usare
  `client.auth`**. Profilo creato lazy al primo login (`ensureProfile`) e anche dal
  webhook Clerk (`supabase/functions/clerk-webhook`, firma Svix, `verify_jwt=false`):
  `user.created` → profilo, `user.deleted` → cancella foto + profilo (cascade). Gli utenti
  con email/telefono stanno in **Clerk**; in Supabase solo `public.profiles` (niente PII).
- `AppServices.analytics: AnalyticsService` → `MixpanelAnalytics` (progetto **EU**,
  `api-eu.mixpanel.com`, niente geolocalizzazione IP) se c'è il token, altrimenti no-op.
  **Nulla parte senza consenso** (`.granted`). Eventi solo tipizzati (`AnalyticsEvent`),
  identify solo con l'id Clerk: mai email, nomi, foto, targhe, coordinate.
- Pacchetti SPM: ClerkKit 1.6.x, Supabase 2.55.x, Mixpanel 7.0.x (`Package.resolved` è
  committato). Sign in with Apple **non ancora attivo**: serve l'Apple Developer Program
  (vedi Gotcha "Personal Team"); fino ad allora il bottone Apple con Clerk dà errore inline.
- NON aggiungere chiavi/endpoint nelle view.

## Shell (stile Flighty)
`RootShellView` = **`TabView` nativa di iOS 26** (la barra è Liquid Glass autentico —
NON sostituirla con una barra custom, l'utente la vuole nativa). **3 tab + camera**
come Flighty: Oggi/Collezione/Mappa + Cattura come `role: .search` (cerchio camera a
destra). Niente tab Profilo: il **profilo si apre toccando l'avatar** nello
`SheetHeader` (env `\.openProfile`), presentato come `.sheet` annidato. **Struttura
(2026-10-21):** alla radice UNA sola `MKMapView` (`MapHost`/`MapSlot` in
`MapBackground.swift`, configurata una volta, non si ricarica) e sopra un **pannello di
sistema** (`.sheet` sempre presentato, `interactiveDismissDisabled`) che CONTIENE la
`TabView`: detent piccola (`.height(200)`: titolo + tab bar), media (`.fraction(0.5)`),
`.large`; `presentationBackgroundInteraction(.enabled)` (mappa sempre toccabile),
`presentationContentInteraction(.resizes)`, sfondo `CSColor.base`. NON tornare a un
pannello fatto a mano (il vecchio `SheetCard` si trascinava solo dalla cima e non era
fluido). La Cattura è il tab `role: .search` ma apre `CaptureView` in
`.fullScreenCover` (con X per chiudere); la tab resta selezionata e mostra la cronologia
(`CaptureHistoryView`, dal 2026-10-25).
Niente polilinee, solo marker. Le schermate sono **contenuto incorporabile**: niente
sfondo/NavigationStack proprio (tranne Collection, che spinge al dettaglio), header via
`SheetHeader` (titolo + share + avatar a destra).
