// embed-asset — WS5
//
// Generates a text embedding for a digital asset's name + description and
// writes it to digital_assets.embedding (+ embedding_model). Intended to be
// invoked by a Database Webhook on INSERT/UPDATE of public.digital_assets, but
// also works when the asset's OWNER calls it directly with { asset_id }.
//
// Deploy:  supabase functions deploy embed-asset
// Secrets: supabase secrets set OPENAI_API_KEY=sk-... EMBED_WEBHOOK_SECRET=<random>
//          (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY are injected)
// Webhook: add HTTP header  x-webhook-secret: <EMBED_WEBHOOK_SECRET>
//
// Loop guard: our own UPDATE of `embedding` fires the UPDATE webhook again.
// UPDATE events whose name/description didn't change are skipped.
import { admin, errorResponse, HttpError, json, requireUser } from "../_shared/auth.ts";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("EMBED_WEBHOOK_SECRET") ?? "";
const EMBEDDING_MODEL = "text-embedding-3-small"; // 1536 dims — must match the vector column

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const fromWebhook = WEBHOOK_SECRET.length > 0 &&
      req.headers.get("x-webhook-secret") === WEBHOOK_SECRET;
    const supabase = admin();

    let assetId: string;
    let name: unknown;
    let description: unknown;

    if (fromWebhook) {
      // DB webhooks wrap the row in { type, record, old_record }.
      const record = payload.record ?? {};
      const old = payload.old_record;
      if (payload.type === "UPDATE" && old &&
          old.name === record.name && old.description === record.description) {
        return json({ skipped: "text unchanged" });
      }
      assetId = record.asset_id;
      name = record.name;
      description = record.description;
    } else {
      // Direct call: must be the signed-in owner; text comes from the DB,
      // never from the request body.
      const caller = await requireUser(req);
      assetId = payload.asset_id;
      if (!assetId) throw new HttpError(400, "missing asset_id");
      const { data, error } = await supabase
        .from("digital_assets")
        .select("user_id, name, description")
        .eq("asset_id", assetId)
        .single();
      if (error || !data) throw new HttpError(404, "asset not found");
      if (String(data.user_id).toLowerCase() !== caller.id.toLowerCase()) {
        throw new HttpError(403, "not your asset");
      }
      name = data.name;
      description = data.description;
    }
    if (!assetId) throw new HttpError(400, "missing asset_id");

    const text = [name, description]
      .filter((s: unknown) => typeof s === "string" && s.trim().length > 0)
      .join(". ")
      .trim()
      .slice(0, 2_000);
    if (!text) return json({ skipped: "no text to embed", asset_id: assetId });

    const embedding = await embed(text);
    const vectorLiteral = `[${embedding.join(",")}]`; // pgvector text input format

    const { error } = await supabase
      .from("digital_assets")
      .update({ embedding: vectorLiteral, embedding_model: EMBEDDING_MODEL })
      .eq("asset_id", assetId);
    if (error) throw error;

    return json({ ok: true, asset_id: assetId, model: EMBEDDING_MODEL });
  } catch (e) {
    return errorResponse(e);
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
