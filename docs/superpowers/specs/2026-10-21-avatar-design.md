# Immagine profilo (avatar) — design

Data: 2026-10-21 · Stato: approvato dalla sessione principale (brief), dettagli = scelte mie (marcate *[mia scelta]*).

## Perché
Oggi l'avatar è solo l'iniziale del nome su accent. Serve una foto vera: per riconoscersi nell'app
e, più avanti, nelle classifiche (dove si vedono gli avatar degli altri).

## Obiettivi
- Setup profilo (dopo il primo login): passo **Foto** con libreria o fotocamera, ritaglio circolare, saltabile.
- Google (Apple quando tornerà): la foto dell'account Clerk viene importata **da sola** se esiste.
- Salvataggio su Supabase Storage compresso (512×512 JPEG, < 100 KB), cache locale.
- Avatar mostrato dove oggi c'è il segnaposto (`UserAvatar`: SheetHeader, Profilo, Impostazioni).

## Non obiettivi
- Classifiche (solo predisposizione: `UserAvatar` sa mostrare l'avatar di qualunque utente).
- Moderazione delle immagini.
- Riattivare Sign in with Apple.

## Backend (migration `0006_avatars`)
- `public.profiles`: `avatar_path text` (null = nessuna foto) e `avatar_updated_at timestamptz`
  (versione per invalidare la cache; **null = mai toccato** → regola dell'import automatico).
  Check: `avatar_path is null or avatar_path = id || '/avatar.jpg'` (nessuno può puntare ai file altrui).
  `grant update (avatar_path, avatar_updated_at) to authenticated` (la policy limita già alla propria riga).
- Bucket **privato** `avatars`, limite 200 KB, solo `image/jpeg`. Percorso `<sub>/avatar.jpg` (upsert).
  - Lettura: `to authenticated`, tutti gli oggetti del bucket (qualunque utente loggato vede gli avatar altrui).
  - Scrittura (insert/update/delete): solo `foldername[1] = sub` e nome file `avatar.jpg`.
  - *[mia scelta]* **Privato + lettura autenticata, non pubblico.** Motivo: la regola del progetto è
    "niente accesso anon" e un avatar è spesso un volto; con un bucket pubblico chiunque conosca l'id
    Clerk scarica la foto da internet. Il costo (niente CDN pubblica) è assorbito dalla cache locale
    versionata: ogni avatar si scarica una volta per versione. Signed URL non servono: il client
    Supabase scarica già col token Clerk.
- Webhook `clerk-webhook`, `user.deleted`: svuota anche `avatars/<id>/` prima di cancellare il profilo.

## App
- **Compressione** (`AvatarEncoding`, fuori dal main actor con `@concurrent`, come `ImageDownsampler`):
  dati originali → ImageIO con orientamento → ritaglio quadrato (rettangolo normalizzato dal cropper,
  o centro per l'import) → 512×512 → JPEG con qualità decrescente (0.8 → 0.5) finché < 100 KB.
- **Stato** in `ProfileAccount`: `avatarPath`, `avatarUpdatedAt` letti in `load`; azioni
  `setAvatar(jpeg:)`, `removeAvatar()`, `importAccountAvatarIfNeeded()`.
- **Import automatico** *[mia scelta]*: se `avatar_updated_at` è null e `AppServices.auth.accountImageURL`
  esiste (Clerk `user.hasImage` → `imageUrl`, altrimenti `imageUrl` del primo account esterno),
  scarica, comprime e carica. Gira dopo il caricamento del profilo, quindi vale anche per chi ha già
  fatto il setup. Chi rimuove la foto non se la vede reimportare (la data non è più null).
- **Passo Foto nel setup** *[mia scelta]*: dopo i permessi, prima di "Pronto" (così la richiesta della
  fotocamera arriva dopo che il passo permessi l'ha spiegata). Mostra l'avatar attuale (per Google già
  importato, con spinner durante l'import) e i pulsanti libreria/fotocamera. CTA "Continua" se c'è
  una foto, altrimenti "Salta per ora". "Pronto" mostra l'avatar sopra l'@nome.
- **Cambia foto dal Profilo** *[mia scelta]*: toccando l'avatar grande nel Profilo (stesso menu:
  libreria, fotocamera, rimuovi). Senza, chi ha già fatto il setup con email non potrebbe mai metterla.
- **Ritaglio** (`AvatarCropView`): fullScreenCover, foto sotto una maschera circolare, pan + pinch
  (scala minima = la foto copre il cerchio), "Annulla"/"Usa foto". Libreria = `PhotosPicker`;
  fotocamera = `UIImagePickerController` (frontale, senza editing), opzione nascosta se non disponibile.
- **Cache e visualizzazione** (`AvatarCache`): memoria + disco (`Caches/avatars/<userId>-<versione>.jpg`),
  download con il client Supabase autenticato. `UserAvatar` accetta un `AvatarRef?` (path + versione):
  con foto la mostra, altrimenti resta l'iniziale di oggi. Dopo un upload proprio, i byte vanno
  subito in cache (nessun download).
- Errori: `AppServices.errors.record` + messaggio `AppError`; mai bloccanti (il setup va avanti).
- Analytics: nessun evento nuovo con dati personali (al massimo `avatarSet(source: library|camera|account)`
  se esiste un pattern di eventi tipizzati — facoltativo).

## Da verificare sul telefono
Login email → passo Foto → libreria/fotocamera → ritaglio → header e Profilo mostrano la foto;
login Google con foto → avatar già presente senza fare nulla.
