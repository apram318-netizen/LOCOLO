// embed-asset — WS5
//
// Generates a text embedding for a digital asset's name + description and
// writes it to digital_assets.embedding (+ embedding_model). Intended to be
// invoked by a Database Webhook on INSERT/UPDATE of public.digital_assets, but
// also works when called directly with { asset_id, name, description }.
//
// Deploy:  supabase functions deploy embed-asset
// Secrets: supabase secrets set OPENAI_API_KEY=sk-...
//          (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically)

import { createClient } from "jsr:@supabase/supabase-js@2";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY")!;
const EMBEDDING_MODEL = "text-embedding-3-small"; // 1536 dims — must match the vector column

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    // DB webhooks wrap the row in { record }; direct calls pass it flat.
    const record = payload.record ?? payload;
    const assetId = record.asset_id;
    if (!assetId) return json({ error: "missing asset_id" }, 400);

    const text = [record.name, record.description]
      .filter((s: unknown) => typeof s === "string" && s.trim().length > 0)
      .join(". ")
      .trim();
    if (!text) return json({ skipped: "no text to embed", asset_id: assetId });

    const embedding = await embed(text);
    const vectorLiteral = `[${embedding.join(",")}]`; // pgvector text input format

    const supabase = admin();
    const { error } = await supabase
      .from("digital_assets")
      .update({ embedding: vectorLiteral, embedding_model: EMBEDDING_MODEL })
      .eq("asset_id", assetId);
    if (error) throw error;

    return json({ ok: true, asset_id: assetId, model: EMBEDDING_MODEL });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

async function embed(input: string): Promise<number[]> {
  const res = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model: EMBEDDING_MODEL, input }),
  });
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return data.data[0].embedding as number[];
}

function admin() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
