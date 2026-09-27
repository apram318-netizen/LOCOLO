// embed-query — WS5
//
// Embeds a free-text search query and returns the vector so the client can
// pass it as p_query_embedding to get_recommended_assets for semantic search.
//
// Deploy:  supabase functions deploy embed-query
// Call:    POST { "q": "cyberpunk dragon" }  ->  { "embedding": [ ... 1536 ... ] }

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY")!;
const EMBEDDING_MODEL = "text-embedding-3-small";

Deno.serve(async (req) => {
  try {
    const { q, query } = await req.json();
    const input = (q ?? query ?? "").toString().trim();
    if (!input) return json({ error: "missing query text" }, 400);

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
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
