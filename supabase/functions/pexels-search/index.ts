const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return Response.json({ error: "Méthode non autorisée" }, { status: 405, headers: corsHeaders });
  }

  try {
    const apiKey = Deno.env.get("PEXELS_API_KEY");
    if (!apiKey) {
      return Response.json({ error: "La clé Pexels n’est pas configurée." }, { status: 500, headers: corsHeaders });
    }

    const body = await request.json();
    const query = typeof body.query === "string" ? body.query.trim().slice(0, 100) : "";
    if (query.length < 2) {
      return Response.json({ error: "Saisis au moins deux caractères." }, { status: 400, headers: corsHeaders });
    }

    const url = new URL("https://api.pexels.com/v1/search");
    url.searchParams.set("query", query);
    url.searchParams.set("per_page", "18");
    url.searchParams.set("locale", "fr-FR");
    url.searchParams.set("orientation", "square");

    const pexelsResponse = await fetch(url, { headers: { Authorization: apiKey } });
    if (!pexelsResponse.ok) {
      console.error("Pexels search failed", pexelsResponse.status);
      return Response.json({ error: "Le service photo est temporairement indisponible." }, { status: 502, headers: corsHeaders });
    }

    const result = await pexelsResponse.json();
    const photos = (result.photos ?? []).map((photo: Record<string, any>) => ({
      id: photo.id,
      alt: photo.alt ?? "",
      photographer: photo.photographer,
      photographer_url: photo.photographer_url,
      url: photo.url,
      src: { small: photo.src?.small, medium: photo.src?.medium },
    }));
    return Response.json({ photos }, { headers: corsHeaders });
  } catch (error) {
    console.error("Pexels search error", error);
    return Response.json({ error: "Impossible d’effectuer la recherche photo." }, { status: 500, headers: corsHeaders });
  }
});
