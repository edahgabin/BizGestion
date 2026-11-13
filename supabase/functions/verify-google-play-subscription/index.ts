import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function base64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function encodeText(value: string) {
  return base64Url(new TextEncoder().encode(value));
}

async function googleAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
}) {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${encodeText(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${encodeText(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }))}`;
  const pem = serviceAccount.private_key.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const keyBytes = Uint8Array.from(atob(pem), (character) => character.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  ));
  const assertion = `${unsigned}.${base64Url(signature)}`;
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const tokenBody = await tokenResponse.json().catch(() => ({}));
  if (!tokenResponse.ok || typeof tokenBody.access_token !== "string") {
    throw new Error("Google Play API authentication failed.");
  }
  return tokenBody.access_token as string;
}

const plans: Record<string, string> = {
  bizgestion_commerce_monthly: "commerce",
  bizgestion_commerce_annual: "commerce",
  bizgestion_entreprise_monthly: "entreprise",
  bizgestion_entreprise_annual: "entreprise",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return reply(405, { error: "Method not allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const packageName = Deno.env.get("ANDROID_PACKAGE_NAME");
  const serviceAccountJson = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
  if (!supabaseUrl || !serviceKey || !packageName || !serviceAccountJson) {
    return reply(503, { error: "Google Play subscription verification is not configured." });
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const accessToken = authorization.replace(/^Bearer\s+/i, "");
  if (!accessToken) return reply(401, { error: "Authentication required." });

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: authData, error: authError } = await admin.auth.getUser(accessToken);
  const user = authData.user;
  if (authError || !user) return reply(401, { error: "Invalid session." });

  try {
    const body = await request.json();
    const businessId = typeof body.business_id === "string" ? body.business_id : "";
    const productId = typeof body.product_id === "string" ? body.product_id : "";
    const purchaseToken = typeof body.purchase_token === "string" ? body.purchase_token : "";
    const planCode = plans[productId];
    if (!businessId || !purchaseToken || !planCode) {
      return reply(400, { error: "Invalid business, product, or purchase token." });
    }

    const { data: membership, error: membershipError } = await admin
      .from("business_members")
      .select("role")
      .eq("business_id", businessId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (membershipError) throw membershipError;
    if (membership?.role !== "owner") return reply(403, { error: "Only the business owner can activate a paid plan." });

    const account = JSON.parse(serviceAccountJson);
    const googleToken = await googleAccessToken(account);
    const googleResponse = await fetch(
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`,
      { headers: { Authorization: `Bearer ${googleToken}` } },
    );
    const subscription = await googleResponse.json().catch(() => ({}));
    if (!googleResponse.ok) return reply(402, { error: "Google Play could not verify this purchase." });

    const lineItems = Array.isArray(subscription.lineItems) ? subscription.lineItems : [];
    const matchedItem = lineItems.find((item: Record<string, unknown>) => item.productId === productId);
    const expiry = typeof matchedItem?.expiryTime === "string" ? matchedItem.expiryTime : null;
    const state = subscription.subscriptionState;
    const active = Boolean(matchedItem) && expiry !== null && Date.parse(expiry) > Date.now() &&
      ["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"].includes(state);
    if (!active) return reply(402, { verified: false, error: "This Google Play subscription is not active." });

    const tokenHash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(purchaseToken));
    const tokenHashHex = [...new Uint8Array(tokenHash)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
    const now = new Date().toISOString();
    const { data: existingLink, error: existingLinkError } = await admin
      .from("google_play_subscription_links")
      .select("business_id, user_id")
      .eq("purchase_token_hash", tokenHashHex)
      .maybeSingle();
    if (existingLinkError) throw existingLinkError;
    if (existingLink && (existingLink.business_id !== businessId || existingLink.user_id !== user.id)) {
      return reply(409, { error: "This Google Play purchase is already linked to another business account." });
    }
    const { error: linkError } = await admin.from("google_play_subscription_links").upsert({
      purchase_token_hash: tokenHashHex,
      business_id: businessId,
      user_id: user.id,
      product_id: productId,
      plan_code: planCode,
      status: "active",
      current_period_end: expiry,
      updated_at: now,
    }, { onConflict: "purchase_token_hash" });
    if (linkError) throw linkError;

    const { error: updateError } = await admin.from("business_subscriptions").update({
      plan_code: planCode,
      status: "active",
      payment_provider: "google_play",
      provider_environment: null,
      provider_subscription_id: tokenHashHex,
      provider_plan_id: productId,
      current_period_end: expiry,
      updated_at: now,
    }).eq("business_id", businessId);
    if (updateError) throw updateError;

    return reply(200, { verified: true, plan_code: planCode, current_period_end: expiry });
  } catch (error) {
    console.error("Google Play verification failed", error);
    return reply(500, { error: "Could not verify Google Play subscription." });
  }
});
