# Skill per CarSpot — quando chiamarle

Letto da CLAUDE.md prima di scegliere una skill. Le skill nascono spesso per il web: traducine i principi in SwiftUI, mai il codice.


Skill globali in `~/.claude/skills/` + plugin attivi. Chiamale con il tool Skill **prima** di
agire quando la situazione corrisponde. Molte nascono per il web: **traducine i principi in
SwiftUI** (CSS `cubic-bezier` → `.spring(duration:bounce:)` / `.timingCurve`, `:active` →
`ButtonStyle` con `configuration.isPressed`, `prefers-reduced-motion` →
`@Environment(\.accessibilityReduceMotion)`, `backdrop-filter` → `.glassEffect`, Vibration
API → `.sensoryFeedback`). Mai copiare codice web nel progetto.

### Codice Swift e processo
| Situazione | Skill |
|---|---|
| Scrivere/rivedere Swift, errori di concurrency/Sendable, data race, retain cycle, performance | `write-swift` |
| Nuova feature non banale → prima di scrivere codice | `superpowers:brainstorming` → `superpowers:writing-plans` |
| Feature/decisione con terminologia o trade-off da chiarire (stress-test del piano) | `grill-with-docs` (usa `grilling` + `domain-modeling`; crea `GLOSSARY.md`, `docs/adr/`) |
| Scelta irreversibile (schema DB, RLS, modello dati) o termini confusi (Spot/Card/Sighting) | `domain-modeling` (ADR) |
| Dove mettere un confine/protocollo, rendere un modulo testabile | `codebase-design` |
| Salute architetturale periodica / dopo merge grossi | `improve-codebase-architecture` |
| Eseguire un piano scritto | `superpowers:executing-plans` / `superpowers:subagent-driven-development` |
| Bug, crash, comportamento inatteso | `superpowers:systematic-debugging` (+ `xcode-workflow-skills:debug`) |
| Dopo un fix: stesso pattern altrove | `xcode-workflow-skills:scan-similar-bugs` |
| Test | `superpowers:test-driven-development`, `xcode-workflow-skills:generate-tests` / `run-tests` |
| Refactor / rinomina tipi | `xcode-workflow-skills:safe-refactor` |
| Prima del commit | `xcode-workflow-skills:review-changes` |
| Prima di dire "fatto" | `superpowers:verification-before-completion` (build verde + screenshot se UI) |
| Performance / sicurezza / codice morto | `xcode-workflow-skills:performance-check` / `security-audit` / `dead-code-scanner` |
| Flussi UI, dead end, wiring dati | `xcode-workflow-skills:workflow-audit` |
| Release / screenshot App Store | `xcode-workflow-skills:release-prep` / `release-screenshots` |
| Supabase (schema, RLS, Edge Functions, Auth) | `supabase:supabase`, `supabase:supabase-postgres-best-practices` |
| Passi manuali che solo l'utente può fare (Apple Developer, APNs, chiavi Supabase) | `wizard` (rivedi lo script prima di farlo eseguire) |
| Scrivere il body di una PR | `pr` |
| Sessione andata storta → migliorare CLAUDE.md/ambiente | `retro` (+ `writing-for-agents`), `claude-md-management:revise-claude-md` |
| Il mio messaggio non si è capito | `wait-what` |

### Design e UI
| Situazione | Skill / tool |
|---|---|
| Nuova schermata o redesign: direzione visiva | `frontend-design` + `impeccable` (shape/craft) — Platform `ios` |
| Critica/audit di una schermata SwiftUI esistente | `impeccable critique <schermata>` / `impeccable audit <schermata>` (o agent `ui-reviewer`) |
| Rifinitura prima di consegnare una UI | `impeccable polish`, poi `break-ui` (dati peggiori: nomi auto lunghi, 0/1/9999 carte) |
| Tipografia, Dynamic Type, spaziature | `impeccable typeset` / `impeccable layout` |
| Copy UX, messaggi d'errore, empty state | `impeccable clarify`, `design:ux-copy` |
| Accessibilità | `design:accessibility-review`, `xcode-workflow-skills:ui-scan` |
| Linee guida SwiftUI/UX/palette/font da database | `ui-ux-pro-max` → `python3 ~/.claude/skills/ui-ux-pro-max/scripts/search.py "<query>" --stack swiftui` (dati iOS 16+, niente Liquid Glass: verifica) |
| Gesture, sheet, drag, molle, materiali, principi Apple | `apple-design` |
| Filosofia di polish/dettagli invisibili | `emil-design-eng` |
| Costruire un'animazione | `animate` (gate frequenza/scopo → valori) |
| Rivedere animazioni scritte | `review-animations` |
| Dove aggiungere motion (e dove NO) | `find-animation-opportunities` |
| Audit di tutta la motion dell'app + piani eseguibili da agent economici | `improve-animations` |
| Dare un nome a un effetto di motion | `animation-vocabulary` |
| Concept di schermate/flussi come immagini (prima di scrivere SwiftUI) | `imagegen-frontend-mobile` — solo su richiesta esplicita |
| Icona app, logo, brand board | `brandkit` — solo su richiesta esplicita |
| Coerenza del design system | `design:design-system` |

**Web-only, NON usare su CarSpot:** `impeccable live/generate/overdrive/extract/optimize`, le
skill taste web, `ui-styling`, `animation-performance`, `mobile-native`, `animate-expo`,
`pick-ui-library`, `ask-sonner`.

### MCP di design
- **21st.dev** (connettore claude.ai): `get_inspiration` / `search` (gratis, solo metadati +
  preview/video) per trovare riferimenti visivi — es. "holographic trading card", "rarity
  badge", "card reveal animation". Il codice (`get_component`) è **React/shadcn e a
  pagamento**: usalo solo come riferimento da tradurre in SwiftUI, mai da installare.
  `search_logo` (svgl, gratis) per loghi di brand/servizi (es. Google per il login); i
  marchi auto sono quasi assenti e restano soggetti a trademark.
- **Stitch** (Google): mockup rapidi di schermate da testo, solo per esplorazione.
