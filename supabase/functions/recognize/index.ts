// CarSpot — Edge Function "recognize"
// Fronts the vehicle-recognition provider so the API key never ships in the app.
// The app sends an already-anonymized JPEG (base64); we forward it and normalize
// the provider response into our VehicleCandidate shape.
//
// Deploy:  supabase functions deploy recognize
// Secret:  supabase secrets set RECOGNITION_API_KEY=...  RECOGNITION_API_URL=...

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

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

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const { imageBase64 } = await req.json();
    if (!imageBase64) {
      return json({ error: "imageBase64 mancante" }, 400);
    }

    // --- Provider call (example shape; adapt to CarNet.AI / chosen vendor) -----
    const providerResp = await fetch(API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": API_KEY },
      body: JSON.stringify({ image: imageBase64 }),
    });

    if (!providerResp.ok) {
      return json({ error: `provider ${providerResp.status}` }, 502);
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
    return json({ error: String(err) }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
