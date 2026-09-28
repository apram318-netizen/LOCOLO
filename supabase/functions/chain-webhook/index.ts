// chain-webhook — Phase C indexer reconcile stub.
// Sole writer of confirmed trades / nft_tokens.owner_id once Alchemy/Moralis is wired.
// CLAUDE: verify partner signatures before enabling writes in production.
import { admin, json, errorResponse } from "../_shared/auth.ts";

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

    // TODO: verify Alchemy/Moralis signature header before trusting body.
    const secret = Deno.env.get("CHAIN_WEBHOOK_SECRET");
    if (secret) {
      const hdr = req.headers.get("x-locolo-webhook-secret") ?? "";
      if (hdr !== secret) return json({ error: "unauthorized" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const event = String(body.event ?? body.type ?? "");
    const db = admin();

    if (event === "Transfer" || event === "OrderFulfilled") {
      const assetId = body.asset_id;
      const toUserId = body.to_user_id;
      const txHash = body.tx_hash ?? null;
      const price = body.price ?? null;
      const fromUserId = body.from_user_id ?? null;

      if (assetId && toUserId) {
        await db.from("nft_tokens").upsert({
          asset_id: assetId,
          owner_id: toUserId,
          mint_state: "minted",
          minted_at: new Date().toISOString(),
          contract: body.contract ?? null,
          token_id: body.token_id ?? null,
          chain: body.chain ?? "base",
        });

        if (price != null) {
          await db.from("trades").insert({
            asset_id: assetId,
            seller_id: fromUserId,
            buyer_id: toUserId,
            price,
            currency: body.currency ?? "USDC",
            royalty_paid: body.royalty_paid ?? 0,
            platform_fee: body.platform_fee ?? 0,
            tx_hash: txHash,
            chain: body.chain ?? "base",
            contract: body.contract ?? null,
          });
        }
      }
    }

    return json({ ok: true, received: event || "unknown" });
  } catch (e) {
    return errorResponse(e);
  }
});
