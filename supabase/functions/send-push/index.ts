// send-push — delivers a notifications row to the recipient's iPhones via APNs.
//
// Invoked by a Database Webhook on INSERT into public.notifications
// (docs/migrations/2026_ar_notifications.sql). Talks to APNs directly over
// HTTP/2 with a token-based (.p8) key, so no Firebase Cloud Messaging setup
// is needed.
//
// Deploy:  supabase functions deploy send-push --no-verify-jwt
// Secrets: supabase secrets set PUSH_WEBHOOK_SECRET=<random> \
//            APNS_KEY_ID=<10-char key id> APNS_TEAM_ID=<team id> \
//            APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)" \
//            APNS_BUNDLE_ID=com.apram.locolo          # optional default topic
//          (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected)
// Webhook: Database → Webhooks → notifications, INSERT → this function,
//          HTTP header  x-webhook-secret: <PUSH_WEBHOOK_SECRET>
//
// Message bodies are end-to-end encrypted and never reach the server, so a
// chat push only says who wrote. Pushes respect notification_prefs and the
// recipient's blocks (enforced when the row was created).
import { admin, errorResponse, HttpError, json } from "../_shared/auth.ts";

const WEBHOOK_SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
const KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const PRIVATE_KEY = (Deno.env.get("APNS_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
const DEFAULT_TOPIC = Deno.env.get("APNS_BUNDLE_ID") ?? "";

type NotificationRow = {
  notification_id: string;
  recipient_id: string;
  actor_id: string | null;
  type: string;
  asset_id: string | null;
  comment_id: string | null;
  offer_id: string | null;
  conversation_id: string | null;
  body: string | null;
};

const PREF_FOR_TYPE: Record<string, string> = {
  follow: "follows",
  hype: "hypes",
  comment: "comments",
  mention: "mentions",
  offer: "offers",
  offer_status: "offers",
  message: "messages",
  new_post: "new_posts",
  discovery: "milestones",
  milestone: "milestones",
};

Deno.serve(async (req) => {
  try {
    if (!WEBHOOK_SECRET || req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
      throw new HttpError(401, "bad webhook secret");
    }
    if (!KEY_ID || !TEAM_ID || !PRIVATE_KEY) {
      throw new HttpError(503, "APNs credentials not configured");
    }
    const payload = await req.json();
    if (payload.type !== "INSERT" || payload.table !== "notifications") {
      return json({ skipped: "not a notifications insert" });
    }
    const n = payload.record as NotificationRow;
    const supabase = admin();

    const prefColumn = PREF_FOR_TYPE[n.type];
    if (prefColumn) {
      const { data: prefs } = await supabase
        .from("notification_prefs")
        .select(prefColumn)
        .eq("user_id", n.recipient_id)
        .maybeSingle();
      if (prefs && (prefs as unknown as Record<string, unknown>)[prefColumn] === false) {
        return json({ skipped: "muted by recipient" });
      }
    }

    const { data: tokens } = await supabase
      .from("device_tokens")
      .select("token, environment, bundle_id")
      .eq("user_id", n.recipient_id);
    if (!tokens || tokens.length === 0) return json({ skipped: "no devices" });

    const [actor, asset, badge] = await Promise.all([
      n.actor_id
        ? supabase.from("users").select("username, name").eq("user_id", n.actor_id).maybeSingle()
          .then((r) => r.data)
        : Promise.resolve(null),
      n.asset_id
        ? supabase.from("digital_assets").select("name").eq("asset_id", n.asset_id).maybeSingle()
          .then((r) => r.data)
        : Promise.resolve(null),
      supabase.from("notifications").select("notification_id", { count: "exact", head: true })
        .eq("recipient_id", n.recipient_id).is("read_at", null)
        .then((r) => r.count ?? 0),
    ]);

    const message = compose(n, actor, asset);
    const aps: Record<string, unknown> = {
      alert: message.subtitle
        ? { title: message.title, subtitle: message.subtitle, body: message.body }
        : { title: message.title, body: message.body },
      sound: "default",
      badge,
      "thread-id": message.thread,
      category: n.type === "message" ? "CHAT_MESSAGE" : "SOCIAL",
    };
    const body = JSON.stringify({
      aps,
      source: "push",
      type: n.type,
      notificationId: n.notification_id,
      url: message.url,
      ...(n.conversation_id ? { conversationId: n.conversation_id } : {}),
      ...(n.type === "message" ? { senderName: displayName(actor) } : {}),
    });

    const jwt = await apnsJwt();
    let sent = 0;
    const stale: string[] = [];
    await Promise.all(tokens.map(async (t) => {
      const topic = t.bundle_id || DEFAULT_TOPIC;
      if (!topic) return;
      const host = t.environment === "sandbox"
        ? "https://api.sandbox.push.apple.com"
        : "https://api.push.apple.com";
      const res = await fetch(`${host}/3/device/${t.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
          ...(message.collapseId ? { "apns-collapse-id": message.collapseId } : {}),
        },
        body,
      });
      if (res.ok) {
        sent++;
        return;
      }
      const reason = await res.json().then((j) => j.reason as string).catch(() => "");
      if (res.status === 410 || ["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"].includes(reason)) {
        stale.push(t.token);
      } else {
        console.error(`APNs ${res.status} ${reason} for ${t.token.slice(0, 8)}…`);
      }
    }));
    if (stale.length > 0) {
      await supabase.from("device_tokens").delete().in("token", stale);
    }
    return json({ ok: true, sent, removed: stale.length });
  } catch (e) {
    return errorResponse(e);
  }
});

// MARK: - Copy

type Person = { username?: string | null; name?: string | null } | null;
type Asset = { name?: string | null } | null;

function displayName(p: Person): string {
  return (p?.name && p.name.trim()) || (p?.username ? `@${p.username}` : "Someone");
}

type Composed = {
  title: string;
  subtitle?: string;
  body: string;
  url: string;
  thread: string;
  collapseId?: string;
};

function compose(n: NotificationRow, actor: Person, asset: Asset): Composed {
  const who = displayName(actor);
  const handle = actor?.username ? `@${actor.username}` : undefined;
  const art = asset?.name?.trim() ? `“${asset.name.trim()}”` : "your creation";
  const assetUrl = n.asset_id ? `locolo://asset/${n.asset_id}` : "locolo://activity";
  const userUrl = n.actor_id ? `locolo://user/${n.actor_id}` : "locolo://activity";
  const quote = (s: string | null) => {
    const text = (s ?? "").trim();
    return text.length > 140 ? `“${text.slice(0, 139)}…”` : `“${text}”`;
  };

  switch (n.type) {
    case "follow":
      return { title: who, subtitle: handle, body: "started following you.", url: userUrl,
               thread: "follows", collapseId: `follow-${n.actor_id}` };
    case "hype":
      return { title: `⚡ ${who} hyped ${art}`, body: "Your creation is getting noticed.", url: assetUrl,
               thread: `asset-${n.asset_id}` };
    case "comment":
      return { title: `${who} commented on ${art}`, body: quote(n.body), url: assetUrl,
               thread: `asset-${n.asset_id}` };
    case "mention": {
      const on = asset?.name?.trim() ? ` on “${asset.name.trim()}”` : "";
      return { title: `${who} mentioned you${on}`, body: quote(n.body), url: assetUrl,
               thread: `asset-${n.asset_id}` };
    }
    case "offer": {
      const amount = money(n.body);
      return { title: amount ? `💰 New offer: ${amount}` : "💰 New offer",
               body: `${who} wants to buy ${art}. Tap to review.`, url: assetUrl, thread: "offers" };
    }
    case "offer_status": {
      const [status, raw] = (n.body ?? "").split(":");
      const amount = money(raw ?? null);
      const offer = amount ? `your ${amount} offer` : "your offer";
      return status === "accepted"
        ? { title: "🎉 Offer accepted", body: `${who} accepted ${offer} for ${art}.`,
            url: assetUrl, thread: "offers" }
        : { title: "Offer declined", body: `${who} declined ${offer} for ${art}.`,
            url: assetUrl, thread: "offers" };
    }
    case "message":
      return { title: who, body: "🔒 New message", url: `locolo://chat/${n.conversation_id}`,
               thread: `chat-${n.conversation_id}`, collapseId: `chat-${n.conversation_id}` };
    case "new_post":
      return { title: `✨ ${who} dropped something new`, body: `${art} is live — go find it in AR.`,
               url: assetUrl, thread: "new-posts" };
    case "discovery":
      return { title: `🧭 ${who} discovered ${art}`, body: "Someone just found your creation in the wild.",
               url: assetUrl, thread: `asset-${n.asset_id}` };
    case "milestone": {
      const [kind, count] = (n.body ?? "").split(":");
      return kind === "views"
        ? { title: `👀 ${count} explorers found ${art}`, body: "Your creation is a local landmark.",
            url: assetUrl, thread: "milestones" }
        : { title: `🔥 ${art} hit ${count} hypes`, body: "Keep creating — people love this one.",
            url: assetUrl, thread: "milestones" };
    }
    default:
      return { title: "Locolo", body: "You have new activity.", url: "locolo://activity", thread: "activity" };
  }
}

function money(raw: string | null): string {
  const value = Number(raw);
  if (raw === null || raw === "" || !Number.isFinite(value)) return "";
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(value);
}

// MARK: - APNs provider token (ES256 JWT, valid up to 60 min; cached for 50)

let cachedJwt: { token: string; at: number } | null = null;

async function apnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.at < 50 * 60) return cachedJwt.token;

  const pem = PRIVATE_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
  const header = b64url(JSON.stringify({ alg: "ES256", kid: KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: TEAM_ID, iat: now }));
  const signingInput = `${header}.${claims}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput),
  );
  const token = `${signingInput}.${b64urlBytes(new Uint8Array(signature))}`;
  cachedJwt = { token, at: now };
  return token;
}

function b64url(text: string): string {
  return b64urlBytes(new TextEncoder().encode(text));
}

function b64urlBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
