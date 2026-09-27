# Locolo Edge Functions (WS5 — semantic search & recommendations)

These power the pgvector hybrid discovery layer. The `get_recommended_assets`
RPC is already live in the database; these functions generate the embeddings it
ranks on. Model: **OpenAI `text-embedding-3-small` (1536 dims)** — must match the
`vector(1536)` columns.

| Function | Trigger | Auth | Purpose |
|---|---|---|---|
| `embed-asset` | DB webhook on `digital_assets` INSERT/UPDATE | `x-webhook-secret` header, or the asset's signed-in owner | Embed name+description → `digital_assets.embedding` |
| `update-taste` | App call on hype/explore | Signed-in user (user = JWT subject) | Fold asset embedding into `users.taste_embedding` (EMA) |
| `embed-query` | App call on search | Signed-in user | Embed a query string → return vector for `p_query_embedding` |

All three share `_shared/auth.ts`. The gateway's JWT check accepts the public
anon key, so each function calls `requireUser()` to resolve the real signed-in
user and rejects anon calls with 401. The app sends the session access token
(`EdgeFunctions.request` in `Locolo/ARModule/Services/EdgeFunctions.swift`).

## One-time setup

```bash
# 1. Auth + link (once)
supabase login
supabase link --project-ref zvrrbtiqsyzkyixbsybf

# 2. Secrets
supabase secrets set OPENAI_API_KEY=sk-...
supabase secrets set EMBED_WEBHOOK_SECRET=$(openssl rand -hex 24)

# 3. Deploy (the _shared folder is bundled automatically)
supabase functions deploy embed-asset
supabase functions deploy update-taste
supabase functions deploy embed-query
```

## Wire the asset embedding trigger

In the Supabase dashboard → **Database → Webhooks**, create a webhook:
- Table: `public.digital_assets`
- Events: `INSERT`, `UPDATE`
- Type: **Supabase Edge Function** → `embed-asset`
- HTTP header: `x-webhook-secret: <the EMBED_WEBHOOK_SECRET value>`

The function skips UPDATE events whose name/description didn't change, so its
own write of `embedding` doesn't re-trigger it in a loop.

## Backfill existing assets (one-time)

Prod has 10 assets today. For each, POST
`{ "type": "INSERT", "record": { asset_id, name, description } }` to `embed-asset`
with the `x-webhook-secret` header.

## Client wiring status

- **For You**: calls `get_recommended_assets` (server-ranked) with a newest-first
  fallback. Becomes *semantic* once assets have embeddings.
- **update-taste**: called on hype and on AR explore (`AssetEngagementRepository.sendTasteSignal`).
- **Semantic search**: `ARGalleryViewModel.deepSearch` calls `embed-query`, then
  passes the vector to `get_recommended_assets`. Until deployment it silently
  falls back to keyword search.
