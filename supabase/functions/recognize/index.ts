// CarSpot — Edge Function "recognize"
// Fronts the vehicle-recognition provider so the API key never ships in the app.
// The app sends an already-anonymized JPEG (base64); we forward it and normalize
// the provider response into our VehicleCandidate shape.
//
// Sicurezza (verify_jwt = false in config.toml perché la verifica è qui, nel codice):
//   1. solo POST;
//   2. JWT di sessione Clerk in `Authorization: Bearer …`, RS256 via JWKS del dominio Clerk
//      (iss + exp controllati) → 401 se manca o non è valido. La publishable key nel binario
//      NON basta: l'identità è il `sub` del token;
//   3. corpo limitato (MAX_BODY_CHARS) → 413; JSON non valido → 400;
//   4. rate limit per utente (DAILY_LIMIT al giorno, contatore atomico nel DB) → 429.
//
// Deploy:  supabase functions deploy recognize
// Secret:  supabase secrets set RECOGNITION_API_KEY=...  RECOGNITION_API_URL=...
//          CLERK_DOMAIN=<frontend API Clerk>   (SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY sono già nell'env)

import { createClient } from "jsr:@supabase/supabase-js@2.49.4";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5.9.6";

/** Riconoscimenti al giorno (UTC) per utente. */
const DAILY_LIMIT = 30;
/** Dimensione massima del corpo della richiesta (caratteri del JSON con la foto in base64). */
const MAX_BODY_CHARS = 3 * 1024 * 1024;

// Dominio della Frontend API di Clerk = quello di `[auth.third_party.clerk] domain` in
// supabase/config.toml. Il fallback è l'istanza di SVILUPPO: in produzione impostare CLERK_DOMAIN.
const CLERK_DOMAIN = Deno.env.get("CLERK_DOMAIN") ?? "quiet-oarfish-3994.clerk.accounts.dev";
const CLERK_ISSUER = `https://${CLERK_DOMAIN}`;
const jwks = createRemoteJWKSet(new URL(`${CLERK_ISSUER}/.well-known/jwks.json`));

const admin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

interface Candidate {
  make: string;
  model: string;
  yearEstimate: number | null;
  confidence: number;
}

const API_URL = Deno.env.get("RECOGNITION_API_URL") ?? "";
const API_KEY = Deno.env.get("RECOGNITION_API_KEY") ?? "";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  // 1) Identità: JWT Clerk.
  const userId = await authenticate(req);
  if (!userId) return json({ error: "non autorizzato" }, 401);

  try {
    // 2) Corpo: dimensione e forma.
    const body = await readBody(req);
    if (body === null) return json({ error: "immagine troppo grande" }, 413);

    let imageBase64: unknown;
    try {
      imageBase64 = JSON.parse(body)?.imageBase64;
    } catch {
      return json({ error: "json non valido" }, 400);
    }
    if (typeof imageBase64 !== "string" || imageBase64.length === 0) {
      return json({ error: "imageBase64 mancante" }, 400);
    }

    // 3) Rate limit per utente (dopo la validazione: le richieste malformate non consumano quota).
    const { data: allowed, error: quotaError } = await admin.rpc("consume_recognition_quota", {
      p_user_id: userId,
      p_limit: DAILY_LIMIT,
    });
    if (quotaError) {
      console.error("recognize quota:", quotaError);
      return json({ error: "errore interno" }, 500); // fail closed
    }
    if (allowed !== true) return json({ error: "limite giornaliero raggiunto" }, 429);

    // --- Provider call (example shape; adapt to CarNet.AI / chosen vendor) -----
    const providerResp = await fetch(API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": API_KEY },
      body: JSON.stringify({ image: imageBase64 }),
    });

    if (!providerResp.ok) {
      console.error(`recognize provider status ${providerResp.status}`);
      return json({ error: "provider non disponibile" }, 502);
    }

    const raw = await providerResp.json();

    // Map the provider payload → our candidates (top 3 by confidence).
    const candidates: Candidate[] = (raw.results ?? raw.predictions ?? [])
      .slice(0, 3)
      .map((r: Record<string, unknown>) => ({
        make: String(r.make ?? r.brand ?? "Sconosciuta"),
        model: String(r.model ?? ""),
        yearEstimate: r.year ? Number(r.year) : null,
        confidence: Number(r.confidence ?? r.score ?? 0),
      }));

    return json({ candidates });
  } catch (err) {
    console.error("recognize:", err);
    return json({ error: "errore interno" }, 500);
  }
});

/** `sub` del JWT Clerk, o null se manca/non è valido (firma RS256, issuer, exp). */
async function authenticate(req: Request): Promise<string | null> {
  const header = req.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(\S+)$/i.exec(header);
  if (!match) return null;
  try {
    const { payload } = await jwtVerify(match[1], jwks, {
      issuer: CLERK_ISSUER,
      algorithms: ["RS256"],
    });
    return typeof payload.sub === "string" && payload.sub !== "" ? payload.sub : null;
  } catch {
    return null;
  }
}

/** Legge il corpo come testo fermandosi al limite; null se lo supera. */
async function readBody(req: Request): Promise<string | null> {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_CHARS) return null;
  if (!req.body) return "";

  const reader = req.body.getReader();
  const decoder = new TextDecoder();
  let text = "";
  let bytes = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > MAX_BODY_CHARS) {
      await reader.cancel();
      return null;
    }
    text += decoder.decode(value, { stream: true });
  }
  return text + decoder.decode();
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
