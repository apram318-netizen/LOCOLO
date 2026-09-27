// update-taste — WS5
//
// When a user engages with an asset (hype / explore), fold that asset's
// embedding into the user's taste_embedding using an exponential moving
// average. This is the personalization signal for the "For You" feed.
//
// Deploy:  supabase functions deploy update-taste
// Call:    POST { "asset_id": "<uuid>" }   (Authorization: Bearer <user access token>)
//
// The user is ALWAYS the caller from the JWT. A body user_id is accepted for
// backwards compatibility but must match, otherwise anyone could rewrite
// another user's taste profile with the service role.
//
// Alpha controls how fast taste shifts toward new interests.
import { admin, errorResponse, HttpError, json, requireUser } from "../_shared/auth.ts";

const ALPHA = 0.15;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  try {
    const caller = await requireUser(req);
    const { user_id, asset_id } = await req.json();
    if (!asset_id || !UUID_RE.test(asset_id)) throw new HttpError(400, "missing or invalid asset_id");
    if (user_id && String(user_id).toLowerCase() !== caller.id.toLowerCase()) {
      throw new HttpError(403, "user_id does not match the signed-in user");
    }
    const userId = caller.id;

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
      .eq("user_id", userId)
      .single();
    if (uErr) throw uErr;

    const prev = parseVector(user?.taste_embedding);
    const next = prev && prev.length === assetVec.length
      ? prev.map((v, i) => v * (1 - ALPHA) + assetVec[i] * ALPHA)
      : assetVec;

    const { error: wErr } = await supabase
      .from("users")
      .update({ taste_embedding: `[${next.join(",")}]`, taste_updated_at: new Date().toISOString() })
      .eq("user_id", userId);
    if (wErr) throw wErr;

    return json({ ok: true });
  } catch (e) {
    return errorResponse(e);
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
