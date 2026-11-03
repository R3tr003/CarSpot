# Template email e SMS di Clerk

L'app accede senza password, quindi l'unico template che gli utenti vedono è
**Verification code** (codice per accesso e registrazione), via email e via SMS.
Bilingue: italiano sopra, inglese sotto. Dashboard Clerk → **Customization → Emails / SMS**.

## Email — Verification code

| Campo | Valore |
|---|---|
| Subject | `{{otp_code}} · Codice CarSpot / CarSpot code` |
| From | `noreply` (resta `@carspot-eu.com` quando l'istanza production ha il dominio) |
| Reply-To | `help` → le risposte arrivano all'assistenza |

Corpo (vista codice dell'editor, sostituisci tutto):

```html
<re-html>
  <re-head>
    <re-title>Codice CarSpot · CarSpot code</re-title>
    <re-preheader>{{otp_code}} è il tuo codice di verifica · is your verification code</re-preheader>
    <re-font family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"></re-font>
  </re-head>
  <re-body background-color="#F2F3F5" padding="32px 16px">
    <re-container width="560px" background-color="#FFFFFF" border-radius="20px">
      <re-block background-color="#0B0C0F" border-radius="20px 20px 0 0" padding="32px 24px 28px" align="center">
        <re-image src="https://carspot-eu.com/assets/icon.png" width="72px" alt="CarSpot"></re-image>
        <re-spacer height="12px"></re-spacer>
        <re-heading level="h2" align="center" color="#F4F6FB" font-size="22px">CarSpot</re-heading>
      </re-block>

      <re-block padding="36px 32px 8px" align="center">
        <re-text align="center" color="#1592B0" font-size="13px" font-weight="600">CODICE DI VERIFICA · VERIFICATION CODE</re-text>
        <re-spacer height="8px"></re-spacer>
        <re-block background-color="#F2F3F5" border-radius="14px" padding="22px 16px" align="center">
          <re-heading level="h1" align="center" color="#0B0C0F" font-size="40px">{{otp_code}}</re-heading>
        </re-block>
      </re-block>

      <re-block padding="24px 32px 0">
        <re-text color="#0B0C0F" font-size="16px" line-height="1.55">Inserisci questo codice in CarSpot per continuare. Vale solo per pochi minuti: non condividerlo con nessuno, CarSpot non te lo chiederà mai.</re-text>
        <re-spacer height="8px"></re-spacer>
        <re-text color="#4A5160" font-size="14px" line-height="1.55">Non hai chiesto tu questo codice? È stato richiesto da <b>{{requested_from}}</b> il <b>{{requested_at}}</b>. Puoi ignorare questa email: senza il codice nessuno può entrare nel tuo account.</re-text>
      </re-block>

      <re-block padding="28px 32px 0">
        <re-text color="#848B9B" font-size="12px" font-weight="600">ENGLISH</re-text>
        <re-spacer height="6px"></re-spacer>
        <re-text color="#0B0C0F" font-size="16px" line-height="1.55">Enter this code in CarSpot to continue. It only works for a few minutes: don't share it with anyone, CarSpot will never ask you for it.</re-text>
        <re-spacer height="8px"></re-spacer>
        <re-text color="#4A5160" font-size="14px" line-height="1.55">Didn't request this code? It was requested from <b>{{requested_from}}</b> at <b>{{requested_at}}</b>. You can ignore this email: without the code nobody can get into your account.</re-text>
      </re-block>

      <re-block padding="32px 32px 32px" align="center">
        <re-text align="center" color="#848B9B" font-size="13px" line-height="1.7">Assistenza · Support: <a href="mailto:help@carspot-eu.com" style="color:#1592B0;">help@carspot-eu.com</a><br><a href="https://carspot-eu.com/privacy.html" style="color:#1592B0;">Privacy</a> · <a href="https://carspot-eu.com/termini.html" style="color:#1592B0;">Termini</a> · <a href="https://carspot-eu.com/en/terms.html" style="color:#1592B0;">Terms</a></re-text>
        <re-spacer height="8px"></re-spacer>
        <re-text align="center" color="#A7AEBC" font-size="12px">© {{current_year}} CarSpot</re-text>
      </re-block>
    </re-container>
  </re-body>
</re-html>
```

Note:
- `{{requested_from}}` e `{{requested_at}}` sono le variabili del template di default di Clerk
  (dispositivo/luogo e ora della richiesta): se il selettore variabili dell'editor non le
  mostra, togli le due frasi "Non hai chiesto tu…" / "Didn't request…" o lasciale senza dettagli.
- Il logo è preso da `https://carspot-eu.com/assets/icon.png` (sito su GitHub Pages), non da
  `{{> app_logo}}`: così non dipende dal logo caricato in Clerk.
- Testata scura col logo, corpo chiaro: molti client email (Gmail, Outlook) stravolgono le
  email interamente scure.
- Nell'anteprima dell'editor le variabili restano `{{…}}`: i valori veri si vedono solo con
  *Send test email* o con un accesso vero.

## SMS — Verification code

```text
{{otp_code}} è il tuo codice CarSpot / is your CarSpot code. Non condividerlo / Don't share it.
```

Breve per stare in un solo SMS. iOS propone il codice sopra la tastiera da solo.
