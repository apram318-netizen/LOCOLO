# Locolo Edge Functions (WS5 — semantic search & recommendations)

These power the pgvector hybrid discovery layer. The `get_recommended_assets`
RPC is already live in the database; these functions generate the embeddings it
ranks on. Model: **OpenAI `text-embedding-3-small` (1536 dims)** — must match the
`vector(1536)` columns.

| Function | Trigger | Purpose |
|---|---|---|
| `embed-asset` | DB webhook on `digital_assets` INSERT/UPDATE | Embed name+description → `digital_assets.embedding` |
| `update-taste` | App call on hype/explore | Fold asset embedding into `users.taste_embedding` (EMA) |
| `embed-query` | App call on search | Embed a query string → return vector for `p_query_embedding` |

## One-time setup

```bash
# 1. Auth + link (once)
supabase login
supabase link --project-ref zvrrbtiqsyzkyixbsybf

# 2. Add the OpenAI key as a secret (used by all three functions)
supabase secrets set OPENAI_API_KEY=sk-...

# 3. Deploy
supabase functions deploy embed-asset
supabase functions deploy update-taste
supabase functions deploy embed-query
```

## Wire the asset embedding trigger

In the Supabase dashboard → **Database → Webhooks**, create a webhook:
- Table: `public.digital_assets`
- Events: `INSERT`, `UPDATE`
- Type: **Supabase Edge Function** → `embed-asset`

(Or call `embed-asset` from `ARCreateViewModel.saveAsset` right after insert.)

## Backfill existing assets (one-time)

For each existing asset with a name/description, POST `{ "record": { asset_id, name, description } }`
to the `embed-asset` function. With zero rows today this is a no-op; run it after
the first assets exist.

## Client wiring status

- **For You**: already calls `get_recommended_assets` (server-ranked) with a
  newest-first fallback. Works today; becomes *semantic* once assets have embeddings.
- **update-taste**: call from the hype/explore path once WS5.4 engagement lands.
- **Semantic search**: `ARSearchView` should call `embed-query`, then pass the
  returned vector as `p_query_embedding` to `get_recommended_assets`. Deferred
  until the functions are deployed (keyword search remains the fallback).
