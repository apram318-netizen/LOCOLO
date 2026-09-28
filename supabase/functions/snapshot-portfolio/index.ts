// snapshot-portfolio — nightly / post-trade portfolio valuation stub.
//
// Writes daily portfolio_snapshots for active users. Full valuation logic
// (sum current_value of owned assets) lands when Phase A owner_id RPCs are live.
//
// Deploy:  supabase functions deploy snapshot-portfolio --no-verify-jwt
// Secrets: SNAPSHOT_CRON_SECRET (optional), SUPABASE_SERVICE_ROLE_KEY (injected)
import { admin, errorResponse, HttpError, json } from "../_shared/auth.ts";

const CRON_SECRET = Deno.env.get("SNAPSHOT_CRON_SECRET") ?? "";

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
    if (CRON_SECRET && req.headers.get("x-cron-secret") !== CRON_SECRET) {
      throw new HttpError(401, "bad cron secret");
    }

    const supabase = admin();
    const day = new Date().toISOString().slice(0, 10);

    // Owners with current_value holdings (falls back to creator if owner_id null).
    const { data: assets, error } = await supabase
      .from("digital_assets")
      .select("owner_id, user_id, current_value")
      .not("current_value", "is", null)
      .limit(5000);
    if (error) throw new HttpError(500, error.message);

    type Agg = { total: number; count: number };
    const byUser = new Map<string, Agg>();
    for (const a of assets ?? []) {
      const uid = (a.owner_id ?? a.user_id) as string | null;
      if (!uid) continue;
      const value = Number(a.current_value) || 0;
      const prev = byUser.get(uid) ?? { total: 0, count: 0 };
      prev.total += value;
      prev.count += 1;
      byUser.set(uid, prev);
    }

    let upserted = 0;
    for (const [userId, agg] of byUser) {
      const { error: upErr } = await supabase.from("portfolio_snapshots").upsert(
        {
          user_id: userId,
          day,
          total_value: Math.round(agg.total * 100) / 100,
          holdings_count: agg.count,
          currency: "USDC",
        },
        { onConflict: "user_id,day" },
      );
      if (!upErr) upserted += 1;
    }

    return json({ ok: true, day, upserted, users: byUser.size });
  } catch (e) {
    return errorResponse(e);
  }
});
