// onramp-session — Phase B partner checkout stub.
// CLAUDE: wire Coinbase Onramp / MoonPay / Stripe; today returns a pending shape.
import { requireUser, json, errorResponse, admin } from "../_shared/auth.ts";

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
    const user = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const amount = Number(body.amount ?? 0);
    const purpose = String(body.purpose ?? "onramp_usdc");
    const currency = String(body.currency ?? "USD");
    const assetId = body.asset_id ?? null;
    const mintOrderId = body.mint_order_id ?? null;
    const provider = String(body.provider ?? "coinbase_onramp");

    if (!(amount > 0)) return json({ error: "invalid amount" }, 400);

    const db = admin();
    const pref = `session_${crypto.randomUUID().replaceAll("-", "")}`;
    const { data, error } = await db.from("payment_intents").insert({
      user_id: user.id,
      provider,
      provider_ref: pref,
      amount,
      currency,
      purpose,
      asset_id: assetId,
      mint_order_id: mintOrderId,
      status: "pending",
    }).select("*").single();
    if (error) throw error;

    // Partner widget URL lands here once keys are configured.
    const checkoutUrl = null;

    return json({
      intent: data,
      checkout_url: checkoutUrl,
      status: "pending_partner",
      message: "Configure ONRAMP partner env vars to return a real checkout_url.",
    });
  } catch (e) {
    return errorResponse(e);
  }
});
