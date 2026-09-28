// purge-storage — drain pending_storage_deletes (§5.9 / §5.27).
//
// Deploy: supabase functions deploy purge-storage --no-verify-jwt
// Secrets: PURGE_CRON_SECRET (optional)
// Schedule: cron POST every 15m with x-cron-secret header.
import { admin, errorResponse, HttpError, json } from "../_shared/auth.ts";

const CRON_SECRET = Deno.env.get("PURGE_CRON_SECRET") ?? "";

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
    if (CRON_SECRET && req.headers.get("x-cron-secret") !== CRON_SECRET) {
      throw new HttpError(401, "bad cron secret");
    }
    const supabase = admin();
    const { data: rows, error } = await supabase
      .from("pending_storage_deletes")
      .select("id, bucket, object_path")
      .is("purged_at", null)
      .order("created_at", { ascending: true })
      .limit(100);
    if (error) throw new HttpError(500, error.message);

    let purged = 0;
    let skipped = 0;
    for (const row of rows ?? []) {
      const path = row.object_path as string;
      const bucket = row.bucket as string;
      try {
        if (path.startsWith("prefix:")) {
          // Convention: prefix:DigitalArt:<assetId> → list folder DigitalArt/<assetId>
          const key = path.slice("prefix:".length).replace(/:/g, "/");
          const { data: listed, error: listErr } = await supabase.storage
            .from(bucket)
            .list(key, { limit: 100 });
          if (listErr) {
            skipped += 1;
            continue;
          }
          const names = (listed ?? []).map((f) => `${key}/${f.name}`);
          if (names.length > 0) {
            await supabase.storage.from(bucket).remove(names);
          }
        } else if (path.endsWith("/")) {
          const { data: listed, error: listErr } = await supabase.storage
            .from(bucket)
            .list(path.replace(/\/$/, ""), { limit: 100 });
          if (listErr) {
            skipped += 1;
            continue;
          }
          const names = (listed ?? []).map((f) => `${path}${f.name}`);
          if (names.length > 0) {
            await supabase.storage.from(bucket).remove(names);
          }
        } else {
          const { error: delErr } = await supabase.storage.from(bucket).remove([path]);
          if (delErr) {
            skipped += 1;
            continue;
          }
        }
        await supabase.from("pending_storage_deletes")
          .update({ purged_at: new Date().toISOString() })
          .eq("id", row.id);
        purged += 1;
      } catch {
        skipped += 1;
      }
    }
    return json({ ok: true, scanned: rows?.length ?? 0, purged, skipped });
  } catch (e) {
    return errorResponse(e);
  }
});
