// update-taste — WS5
//
// When a user engages with an asset (hype / explore), fold that asset's
// embedding into the user's taste_embedding using an exponential moving
// average. This is the personalization signal for the "For You" feed.
//
// Deploy:  supabase functions deploy update-taste
// Call:    POST { "user_id": "<uuid>", "asset_id": "<uuid>" }
//
// Alpha controls how fast taste shifts toward new interests.
import { createClient } from "jsr:@supabase/supabase-js@2";

const ALPHA = 0.15;

Deno.serve(async (req) => {
  try {
    const { user_id, asset_id } = await req.json();
    if (!user_id || !asset_id) return json({ error: "missing user_id or asset_id" }, 400);

    const supabase = admin();

    const { data: asset, error: aErr } = await supabase
      .from("digital_assets")
      .select("embedding")
      .eq("asset_id", asset_id)
      .single();
    if (aErr) throw aErr;

    const assetVec = parseVector(asset?.embedding);
    if (!assetVec) return json({ skipped: "asset has no embedding yet" });

    const { data: user, error: uErr } = await supabase
      .from("users")
      .select("taste_embedding")
      .eq("user_id", user_id)
      .single();
    if (uErr) throw uErr;

    const prev = parseVector(user?.taste_embedding);
    const next = prev
      ? prev.map((v, i) => v * (1 - ALPHA) + assetVec[i] * ALPHA)
      : assetVec;

    const { error: wErr } = await supabase
      .from("users")
      .update({ taste_embedding: `[${next.join(",")}]`, taste_updated_at: new Date().toISOString() })
      .eq("user_id", user_id);
    if (wErr) throw wErr;

    return json({ ok: true, user_id });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

// pgvector may come back as a JSON array or the text form "[1,2,3]".
function parseVector(v: unknown): number[] | null {
  if (!v) return null;
  if (Array.isArray(v)) return v as number[];
  if (typeof v === "string") {
    try {
      const arr = JSON.parse(v);
      return Array.isArray(arr) ? arr : null;
    } catch {
      return null;
    }
  }
  return null;
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
