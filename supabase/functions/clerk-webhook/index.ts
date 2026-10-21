// CarSpot — Edge Function "clerk-webhook"
// Riceve gli eventi utente di Clerk (via Svix) e tiene allineato Supabase:
//   user.created → crea la riga in public.profiles (se l'app non l'ha già fatto)
//   user.deleted → cancella foto (bucket spots/<id>/) e profilo; carte, riscatti,
//                  veicoli e avvistamenti seguono con ON DELETE CASCADE (GDPR).
// Nessun dato personale (email, telefono, nome) viene salvato.
//
// Deploy:  verify_jwt = false (chiama Clerk, non l'app) — la sicurezza è la firma Svix.
// Secret:  CLERK_WEBHOOK_SIGNING_SECRET=whsec_...  (Clerk → Webhooks → endpoint → Signing secret)
// Senza secret la funzione rifiuta tutto (fail closed).

import { Webhook } from "npm:svix@1.45.1";
import { createClient } from "jsr:@supabase/supabase-js@2.49.4";

const SIGNING_SECRET = Deno.env.get("CLERK_WEBHOOK_SIGNING_SECRET") ?? "";
const admin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

interface ClerkEvent {
  type: string;
  data: { id?: string; deleted?: boolean };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (!SIGNING_SECRET) return json({ error: "webhook non configurato" }, 503);

  // La firma va verificata sul corpo grezzo, prima di qualsiasi parsing.
  const payload = await req.text();
  let event: ClerkEvent;
  try {
    event = new Webhook(SIGNING_SECRET).verify(payload, {
      "svix-id": req.headers.get("svix-id") ?? "",
      "svix-timestamp": req.headers.get("svix-timestamp") ?? "",
      "svix-signature": req.headers.get("svix-signature") ?? "",
    }) as ClerkEvent;
  } catch {
    return json({ error: "firma non valida" }, 401);
  }

  const userId = event.data?.id;
  if (!userId || !/^user_[A-Za-z0-9]+$/.test(userId)) return json({ ignored: true }, 200);

  try {
    switch (event.type) {
      case "user.created":
        await ensureProfile(userId);
        break;
      case "user.deleted":
        await deleteUserData(userId);
        break;
      default:
        return json({ ignored: event.type }, 200);
    }
    return json({ ok: true }, 200);
  } catch (e) {
    console.error(`clerk-webhook ${event.type} ${userId}:`, e);
    // 500 → Svix ritenta con backoff.
    return json({ error: "errore interno" }, 500);
  }
});

/** Stessa regola dell'app (SupabaseBackend.ensureProfile): username dagli ultimi caratteri dell'id. */
async function ensureProfile(userId: string) {
  const tail = userId.toLowerCase();
  for (const length of [6, 12]) {
    const { error } = await admin.from("profiles").insert({
      id: userId,
      username: `spotter_${tail.slice(-length)}`,
    });
    if (!error) return;
    if (error.code !== "23505") throw error;
    // Unicità violata: o il profilo esiste già (creato dall'app) o lo username è preso.
    const { data } = await admin.from("profiles").select("id").eq("id", userId).maybeSingle();
    if (data) return;
  }
  throw new Error("username non disponibile");
}

async function deleteUserData(userId: string) {
  // Foto: tutti gli oggetti sotto spots/<userId>/ (a pagine da 100).
  for (;;) {
    const { data: files, error } = await admin.storage.from("spots").list(userId, { limit: 100 });
    if (error) throw error;
    if (!files || files.length === 0) break;
    const { error: rmError } = await admin.storage
      .from("spots")
      .remove(files.map((f) => `${userId}/${f.name}`));
    if (rmError) throw rmError;
    if (files.length < 100) break;
  }
  const { error } = await admin.from("profiles").delete().eq("id", userId);
  if (error) throw error;
}

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
