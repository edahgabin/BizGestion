const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function plainText(value: string | undefined): string {
  return (value ?? "")
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}

function searchTerms(query: string): string[] {
  const terms = [query];
  const translations: Record<string, string> = {
    riz: "rice", huile: "oil", sucre: "sugar", farine: "flour", savon: "soap",
    lait: "milk", eau: "water", tomate: "tomato", oignon: "onion",
    mais: "corn", haricot: "beans", mil: "millet", café: "coffee", the: "tea",
    pain: "bread", poisson: "fish", viande: "meat", poulet: "chicken",
    chaussure: "shoes", chaussures: "shoes", vetement: "clothing",
    robe: "dress", pantalon: "trousers", telephone: "phone",
    cahier: "notebook", stylo: "pen", ciment: "cement", peinture: "paint",
    batterie: "battery", medicament: "medicine",
  };
  const packaging: Record<string, string> = { sac: "bag", sachet: "sachet", carton: "carton", boite: "box", bidon: "canister", bouteille: "bottle", paquet: "pack" };
  const tokens = query.split(/\s+/);
  const englishTokens = tokens.map((token) => {
    const key = token.toLocaleLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    return translations[key] ?? packaging[key] ?? token;
  });
  const translated = englishTokens.join(" ");
  if (translated.toLocaleLowerCase() !== query.toLocaleLowerCase()) terms.push(translated);

  // Keep brand/product names while also trying likely package descriptions.
  const packageWord = tokens.find((token) => packaging[token.toLocaleLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")]);
  if (packageWord) {
    const productName = tokens.filter((token) => token !== packageWord).join(" ");
    if (productName) {
      terms.push(`${productName} bag`, `${productName} sack`);
    }
  } else {
    terms.push(`${translated} product packaging`, `bag of ${translated}`, `${translated} package`);
  }
  return [...new Set(terms.map((term) => term.trim()).filter(Boolean))].slice(0, 5);
}

async function searchCommons(query: string) {
  const url = new URL("https://commons.wikimedia.org/w/api.php");
  url.searchParams.set("action", "query");
  url.searchParams.set("generator", "search");
  url.searchParams.set("gsrsearch", `filetype:bitmap ${query}`);
  url.searchParams.set("gsrnamespace", "6");
  url.searchParams.set("gsrlimit", "12");
  url.searchParams.set("prop", "imageinfo|info");
  url.searchParams.set("iiprop", "url|extmetadata");
  url.searchParams.set("iiurlwidth", "640");
  url.searchParams.set("inprop", "url");
  url.searchParams.set("format", "json");

  const response = await fetch(url, {
    headers: {
      "Api-User-Agent": "BizGestion/1.0 (commercial product image search)",
      "Accept": "application/json",
    },
  });
  if (!response.ok) throw new Error(`Commons HTTP ${response.status}`);

  const result = await response.json();
  const pages = Object.values(result.query?.pages ?? {}) as Record<string, any>[];
  return pages.flatMap((page) => {
    const image = page.imageinfo?.[0];
    if (!image?.thumburl || !image?.descriptionurl) return [];
    const metadata = image.extmetadata ?? {};
    const author = plainText(metadata.Artist?.value) || "Auteur non indiqué";
    const license = plainText(metadata.LicenseShortName?.value) || "Licence libre à vérifier";
    return [{
      imageUrl: image.thumburl,
      pageUrl: image.descriptionurl,
      alt: plainText(metadata.ImageDescription?.value) || page.title,
      credit: `${author} · ${license} · Wikimedia Commons`,
    }];
  });
}

async function searchOpenverse(query: string) {
  const url = new URL("https://api.openverse.org/v1/images/");
  url.searchParams.set("q", query);
  url.searchParams.set("license_type", "commercial");
  url.searchParams.set("page_size", "12");
  url.searchParams.set("filter_dead", "true");

  const response = await fetch(url, { headers: { "Accept": "application/json" } });
  if (!response.ok) throw new Error(`Openverse HTTP ${response.status}`);

  const result = await response.json();
  return (result.results ?? []).flatMap((image: Record<string, any>) => {
    const imageUrl = image.thumbnail || image.url;
    const pageUrl = image.foreign_landing_url || image.detail_url;
    if (!imageUrl || !pageUrl) return [];
    const author = plainText(image.creator) || "Auteur non indiqué";
    const license = plainText(image.license) || "Licence à vérifier";
    const provider = plainText(image.provider);
    return [{
      imageUrl,
      pageUrl,
      alt: plainText(image.title) || query,
      credit: `${author} · ${license} · Openverse${provider ? ` / ${provider}` : ""}`,
    }];
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") {
    return Response.json({ error: "Méthode non autorisée" }, { status: 405, headers: corsHeaders });
  }

  try {
    const body = await request.json();
    const query = typeof body.query === "string" ? body.query.trim().slice(0, 100) : "";
    if (query.length < 2) {
      return Response.json({ error: "Saisis au moins deux caractères." }, { status: 400, headers: corsHeaders });
    }

    const terms = searchTerms(query);
    const batches = await Promise.allSettled(terms.flatMap((term) => [
      searchCommons(term),
      searchOpenverse(term),
    ]));
    const photos = batches.flatMap((batch) => batch.status === "fulfilled" ? batch.value : []);
    const unique = [...new Map(photos.map((photo) => [photo.imageUrl, photo])).values()].slice(0, 48);
    if (unique.length === 0 && batches.every((batch) => batch.status === "rejected")) {
      return Response.json({ error: "Les banques d’images sont temporairement indisponibles." }, { status: 502, headers: corsHeaders });
    }
    return Response.json({ photos: unique }, { headers: corsHeaders });
  } catch (error) {
    console.error("Product image search error", error);
    return Response.json({ error: "Impossible d’effectuer la recherche photo." }, { status: 500, headers: corsHeaders });
  }
});
