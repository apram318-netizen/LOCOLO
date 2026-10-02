// verify-mint-purchase — settle a mint order paid with an App Store In-App
// Purchase (consumable `com.apram.locolo.mint`).
//
// The app buys with StoreKit 2, passing the mint order id as the
// appAccountToken, then POSTs { order_id, signed_transaction } here with the
// user's JWT. We:
//   1. verify the JWS: x5c chain → pinned Apple Root CA - G3, Apple OIDs on
//      the leaf / intermediate, ES256 signature by the leaf;
//   2. check bundle id, product id, appAccountToken == order id, not revoked;
//   3. record the transaction once (iap_transactions PK = replay guard) and
//      flip the order pending → paid.
// The digital_assets insert trigger then lets exactly one asset consume it.
//
// Deploy:  supabase functions deploy verify-mint-purchase
// Needs:   docs/migrations/2026_v3_release_gates.sql (iap_transactions).
// Env (optional): IAP_BUNDLE_ID (default com.apram.locolo),
//                 IAP_MINT_PRODUCT_ID (default com.apram.locolo.mint),
//                 IAP_ALLOW_SANDBOX ("false" to refuse Sandbox; App Review
//                 and TestFlight purchase in Sandbox, so keep it on for launch).
import * as x509 from "npm:@peculiar/x509@1.12.3";
import { admin, errorResponse, HttpError, json, requireUser } from "../_shared/auth.ts";

x509.cryptoProvider.set(crypto);

const APPLE_ROOT_G3_SHA256 =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";
const OID_LEAF = "1.2.840.113635.100.6.11.1";
const OID_INTERMEDIATE = "1.2.840.113635.100.6.2.1";

const BUNDLE_ID = Deno.env.get("IAP_BUNDLE_ID") ?? "com.apram.locolo";
const PRODUCT_ID = Deno.env.get("IAP_MINT_PRODUCT_ID") ?? "com.apram.locolo.mint";
const ALLOW_SANDBOX = (Deno.env.get("IAP_ALLOW_SANDBOX") ?? "true") !== "false";

type TransactionPayload = {
  transactionId: string;
  originalTransactionId?: string;
  bundleId: string;
  productId: string;
  appAccountToken?: string;
  environment: string;
  purchaseDate?: number;
  revocationDate?: number;
  type?: string;
};

function b64urlToBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(s.length / 4) * 4, "=");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

function b64ToBytes(s: string): Uint8Array {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function verifySignedTransaction(jws: string): Promise<TransactionPayload> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new HttpError(400, "malformed transaction");
  const [h, p, sig] = parts;

  const header = JSON.parse(new TextDecoder().decode(b64urlToBytes(h))) as { alg?: string; x5c?: string[] };
  if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length !== 3) {
    throw new HttpError(400, "unexpected transaction header");
  }

  const ders = header.x5c.map(b64ToBytes);
  if (await sha256Hex(ders[2]) !== APPLE_ROOT_G3_SHA256) {
    throw new HttpError(400, "untrusted certificate chain");
  }
  const [leaf, intermediate, root] = ders.map((d) => new x509.X509Certificate(d));
  const now = new Date();
  const chainOK =
    await root.verify({ date: now }) &&
    await intermediate.verify({ publicKey: root, date: now }) &&
    await leaf.verify({ publicKey: intermediate, date: now });
  if (!chainOK) throw new HttpError(400, "invalid certificate chain");
  if (!leaf.getExtension(OID_LEAF) || !intermediate.getExtension(OID_INTERMEDIATE)) {
    throw new HttpError(400, "certificate is not an App Store signing certificate");
  }

  const key = await leaf.publicKey.export({ name: "ECDSA", namedCurve: "P-256" }, ["verify"]);
  const signed = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    b64urlToBytes(sig),
    new TextEncoder().encode(`${h}.${p}`),
  );
  if (!signed) throw new HttpError(400, "bad transaction signature");

  return JSON.parse(new TextDecoder().decode(b64urlToBytes(p))) as TransactionPayload;
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
    const user = await requireUser(req);
    const body = await req.json().catch(() => null) as
      { order_id?: string; signed_transaction?: string } | null;
    const orderId = body?.order_id?.toLowerCase();
    if (!orderId || !body?.signed_transaction) throw new HttpError(400, "order_id and signed_transaction required");

    const tx = await verifySignedTransaction(body.signed_transaction);
    if (tx.bundleId !== BUNDLE_ID) throw new HttpError(400, "wrong app");
    if (tx.productId !== PRODUCT_ID) throw new HttpError(400, "wrong product");
    if (tx.revocationDate) throw new HttpError(402, "purchase was refunded");
    if (tx.environment !== "Production" && !(ALLOW_SANDBOX && tx.environment === "Sandbox")) {
      throw new HttpError(400, "sandbox purchases are not accepted");
    }
    if (tx.appAccountToken?.toLowerCase() !== orderId) throw new HttpError(400, "purchase is for a different order");

    const db = admin();
    const { data: order, error: orderErr } = await db
      .from("mint_orders").select("order_id, user_id, status").eq("order_id", orderId).maybeSingle();
    if (orderErr) throw orderErr;
    if (!order || order.user_id !== user.id) throw new HttpError(404, "mint order not found");

    const { error: insertErr } = await db.from("iap_transactions").insert({
      transaction_id: tx.transactionId,
      original_transaction_id: tx.originalTransactionId ?? null,
      user_id: user.id,
      order_id: orderId,
      product_id: tx.productId,
      environment: tx.environment,
      purchased_at: tx.purchaseDate ? new Date(tx.purchaseDate).toISOString() : null,
    });
    if (insertErr) {
      // 23505: this transaction (or this order) was already recorded.
      if (insertErr.code !== "23505") throw insertErr;
      const { data: seen } = await db
        .from("iap_transactions").select("order_id").eq("transaction_id", tx.transactionId).maybeSingle();
      if (seen?.order_id !== orderId) throw new HttpError(409, "transaction already used");
      // Same purchase retried (e.g. the first call died before the update).
    }

    if (order.status === "pending") {
      const { error: updErr } = await db
        .from("mint_orders").update({ status: "paid" }).eq("order_id", orderId).eq("status", "pending");
      if (updErr) throw updErr;
      return json({ order_id: orderId, status: "paid" });
    }
    return json({ order_id: orderId, status: order.status });
  } catch (e) {
    return errorResponse(e);
  }
});
