// firebase-custom-token — mint a Firebase Auth custom token for the signed-in
// Supabase user (uid = Supabase user id). Replaces anonymous Firebase sign-in
// so Firestore rules can bind chat identity (status §5.8).
//
// Deploy:  supabase functions deploy firebase-custom-token
// Secrets: FIREBASE_SERVICE_ACCOUNT_JSON — full service-account JSON.
//          When unset, returns 503 stub so clients keep anonymous fallback.
//
// Production: prefer firebase-admin createCustomToken(uid) from a Node runtime
// or call Google Identity Toolkit with a signed JWT. This stub documents the
// contract the iOS client expects.
import { requireUser, errorResponse, json } from "../_shared/auth.ts";

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
    const user = await requireUser(req);
    const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!saRaw) {
      return json({
        stub: true,
        message: "Set FIREBASE_SERVICE_ACCOUNT_JSON and implement Admin createCustomToken.",
        uid: user.id,
      }, 503);
    }

    // Placeholder: parse SA to prove secret shape; real minting needs Admin SDK.
    const sa = JSON.parse(saRaw) as { project_id?: string; client_email?: string };
    if (!sa.project_id || !sa.client_email) {
      return json({ error: "invalid service account JSON" }, 500);
    }

    return json({
      stub: true,
      message: "Service account present — wire firebase-admin createCustomToken(uid) here.",
      uid: user.id,
      projectId: sa.project_id,
    }, 501);
  } catch (e) {
    return errorResponse(e);
  }
});
