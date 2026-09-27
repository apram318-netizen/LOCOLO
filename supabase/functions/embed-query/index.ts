// embed-query — WS5
//
// Embeds a free-text search query and returns the vector so the client can
// pass it as p_query_embedding to get_recommended_assets for semantic search.
//
// Deploy:  supabase functions deploy embed-query
// Call:    POST { "q": "cyberpunk dragon" }  ->  { "embedding": [ ... 1536 ... ] }
//          (Authorization: Bearer <user access token>)
//
// Signed-in users only, with a length cap — otherwise this is an open,
// unauthenticated proxy to our OpenAI key.
import { errorResponse, HttpError, json, requireUser } from "../_shared/auth.ts";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY")!;
const EMBEDDING_MODEL = "text-embedding-3-small";
const MAX_QUERY_CHARS = 300;

Deno.serve(async (req) => {
  try {
    await requireUser(req);
    const { q, query } = await req.json();
    const input = (q ?? query ?? "").toString().trim().slice(0, MAX_QUERY_CHARS);
    if (!input) throw new HttpError(400, "missing query text");

    const res = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ model: EMBEDDING_MODEL, input }),
    });
    if (!res.ok) throw new Error(`OpenAI ${res.status}: ${await res.text()}`);
    const data = await res.json();

    return json({ embedding: data.data[0].embedding, model: EMBEDDING_MODEL });
  } catch (e) {
    return errorResponse(e);
  }
});
