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

function getPublishableKey() {
  const legacy = Deno.env.get("SUPABASE_ANON_KEY");
  if (legacy) return legacy;
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
    return keys.default ?? Object.values(keys)[0] ?? null;
  } catch {
    return null;
  }
}

function getPayPalConfig() {
  const environment = Deno.env.get("PAYPAL_ENV") ?? "sandbox";
  if (environment !== "sandbox" && environment !== "live") return null;
  const prefix = environment === "live" ? "PAYPAL_LIVE_" : "PAYPAL_";
  const read = (name: string) => Deno.env.get(`${prefix}${name}`);
  return {
    environment,
    base: environment === "live"
      ? "https://api-m.paypal.com"
      : "https://api-m.sandbox.paypal.com",
    clientId: read("CLIENT_ID"),
    clientSecret: read("CLIENT_SECRET"),
    planId: (planCode: string, period: string) =>
      read(`${planCode.toUpperCase()}_${period.toUpperCase()}_PLAN_ID`),
    returnOrigins: read("RETURN_ORIGINS"),
  };
}

type PayPalPlan = {
  name?: string;
  status?: string;
  billing_cycles?: Array<{
    tenure_type?: string;
    frequency?: { interval_unit?: string; interval_count?: number };
    pricing_scheme?: {
      fixed_price?: { value?: string; currency_code?: string };
    };
  }>;
};

async function getPayPalToken(base: string, clientId: string, secret: string) {
  const response = await fetch(`${base}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${clientId}:${secret}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || typeof payload.access_token !== "string") {
    throw new Error("PayPal n’a pas accepté les identifiants API configurés.");
  }
  return payload.access_token as string;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return reply(405, { error: "Méthode non autorisée." });

  const authorization = request.headers.get("Authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = getPublishableKey();
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const paypalConfig = getPayPalConfig();
  const clientId = paypalConfig?.clientId;
  const paypalSecret = paypalConfig?.clientSecret;
  if (!authorization?.startsWith("Bearer ")) return reply(401, { error: "Connecte-toi avant de choisir un forfait." });
  if (!supabaseUrl || !publishableKey || !serviceRoleKey || !clientId || !paypalSecret) {
    return reply(503, { error: "La connexion sécurisée PayPal n’est pas encore configurée dans Supabase." });
  }

  try {
    const userClient = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const accessToken = authorization.substring("Bearer ".length);
    const { data: userData, error: userError } = await userClient.auth.getUser(accessToken);
    if (userError || !userData.user) return reply(401, { error: "Session expirée. Reconnecte-toi." });

    const body = await request.json().catch(() => null);
    const businessId = typeof body?.business_id === "string" ? body.business_id : "";
    const planCode = body?.plan_code;
    const period = body?.billing_period;
    if (!businessId || !["commerce", "entreprise"].includes(planCode) ||
      (period !== "monthly" && period !== "annual")) {
      return reply(400, { error: "Commerce ou période d’abonnement invalide." });
    }
    if (!paypalConfig) return reply(503, { error: "L’environnement PayPal doit être sandbox ou live." });
    if (body?.paypal_environment !== paypalConfig.environment) {
      return reply(409, { error: "La version de BizGestion et l’environnement PayPal ne correspondent pas. Recharge l’application avant de continuer." });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: membership, error: membershipError } = await admin
      .from("business_members")
      .select("role")
      .eq("business_id", businessId)
      .eq("user_id", userData.user.id)
      .maybeSingle();
    if (membershipError || !membership || !["owner", "admin"].includes(membership.role)) {
      return reply(403, { error: "Seul le propriétaire ou un administrateur peut gérer l’abonnement." });
    }

    const { data: currentSubscription, error: subscriptionError } = await admin
      .from("business_subscriptions")
      .select("status, provider_environment")
      .eq("business_id", businessId)
      .maybeSingle();
    if (subscriptionError) throw subscriptionError;
    const currentEnvironment = currentSubscription?.provider_environment ?? "sandbox";
    if (currentSubscription?.status === "active" &&
      currentEnvironment === paypalConfig.environment) {
      return reply(409, { error: "Ce commerce possède déjà un forfait actif." });
    }
    const recentCutoff = new Date(Date.now() - 15 * 60 * 1000).toISOString();
    const { data: pendingCheckout, error: pendingError } = await admin
      .from("paypal_subscription_links")
      .select("provider_subscription_id")
      .eq("business_id", businessId)
      .eq("status", "approval_pending")
      .eq("environment", paypalConfig.environment)
      .gte("created_at", recentCutoff)
      .limit(1);
    if (pendingError) throw pendingError;
    if (pendingCheckout?.length) {
      return reply(409, { error: "Une demande PayPal est déjà en attente. Termine-la ou réessaie dans quelques minutes." });
    }

    const planId = paypalConfig.planId(planCode, period);
    if (!planId) return reply(503, { error: "Le plan PayPal demandé n’est pas configuré." });

    const base = paypalConfig.base;
    const token = await getPayPalToken(base, clientId, paypalSecret);
    const planResponse = await fetch(
      `${base}/v1/billing/plans/${encodeURIComponent(planId)}`,
      { headers: { Authorization: `Bearer ${token}` } },
    );
    const selectedPlan = await planResponse.json().catch(() => ({})) as PayPalPlan;
    const expectedPlanName = planCode === "entreprise" ? "entreprise" : "commerce";
    const expectedAmount = planCode === "entreprise"
      ? (period === "annual" ? 120 : 12)
      : (period === "annual" ? 40 : 4);
    const regularCycle = Array.isArray(selectedPlan.billing_cycles)
      ? selectedPlan.billing_cycles.find((cycle) => cycle.tenure_type === "REGULAR")
      : null;
    const configuredAmount = Number(regularCycle?.pricing_scheme?.fixed_price?.value);
    const expectedFrequency = period === "annual" ? "YEAR" : "MONTH";
    if (!planResponse.ok ||
      typeof selectedPlan.name !== "string" ||
      !selectedPlan.name.toLowerCase().includes(expectedPlanName) ||
      selectedPlan.status !== "ACTIVE" ||
      regularCycle?.frequency?.interval_unit !== expectedFrequency ||
      Number(regularCycle?.frequency?.interval_count ?? 1) !== 1 ||
      regularCycle?.pricing_scheme?.fixed_price?.currency_code !== "USD" ||
      !Number.isFinite(configuredAmount) || configuredAmount !== expectedAmount) {
      console.error("PayPal plan configuration mismatch", {
        requestedPlan: planCode,
        requestedPeriod: period,
        returnedPlanName: selectedPlan.name,
        returnedPlanStatus: selectedPlan.status,
        returnedAmount: regularCycle?.pricing_scheme?.fixed_price?.value,
        returnedCurrency: regularCycle?.pricing_scheme?.fixed_price?.currency_code,
        returnedFrequency: regularCycle?.frequency,
      });
      return reply(503, {
        error: `Le plan PayPal configuré pour ${planCode === "entreprise" ? "Entreprise" : "Commerce"} ne correspond pas au tarif attendu (${expectedAmount} USD/${period === "annual" ? "an" : "mois"}). Vérifie son identifiant dans les secrets Supabase.`,
      });
    }

    const origin = request.headers.get("Origin") ?? "";
    const allowed = (paypalConfig.returnOrigins ?? (paypalConfig.environment === "sandbox"
      ? "https://peaceful-seahorse-c8bdc5.netlify.app,http://localhost:5000,http://127.0.0.1:5000"
      : ""))
      .split(",").map((value) => value.trim()).filter(Boolean);
    if (paypalConfig.environment === "live" && allowed.some((value) => {
      try {
        const url = new URL(value);
        return url.protocol !== "https:" || ["localhost", "127.0.0.1"].includes(url.hostname);
      } catch {
        return true;
      }
    })) return reply(503, { error: "Les adresses de retour PayPal Live doivent être des URL HTTPS publiques." });
    if (paypalConfig.environment === "live" && origin && !allowed.includes(origin)) {
      return reply(403, { error: "Les paiements Live doivent être démarrés depuis l’adresse officielle de BizGestion." });
    }
    const appOrigin = allowed.includes(origin) ? origin : allowed[0];
    if (!appOrigin) return reply(503, { error: "L’adresse de retour BizGestion n’est pas configurée." });
    const returnUrl = new URL("/", appOrigin);
    returnUrl.searchParams.set("paypal_subscription", "return");
    const cancelUrl = new URL("/", appOrigin);
    cancelUrl.searchParams.set("paypal_subscription", "cancel");

    const createResponse = await fetch(`${base}/v1/billing/subscriptions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        "PayPal-Request-Id": crypto.randomUUID(),
      },
      body: JSON.stringify({
        plan_id: planId,
        custom_id: businessId,
        application_context: {
          brand_name: "BizGestion",
          user_action: "SUBSCRIBE_NOW",
          return_url: returnUrl.toString(),
          cancel_url: cancelUrl.toString(),
        },
      }),
    });
    const created = await createResponse.json().catch(() => ({}));
    if (!createResponse.ok || typeof created.id !== "string") {
      console.error("PayPal create subscription failed", createResponse.status, created);
      return reply(502, { error: "PayPal n’a pas pu préparer l’abonnement. Vérifie les identifiants API et le plan configuré pour cet environnement." });
    }
    const approval = Array.isArray(created.links)
      ? created.links.find((link: Record<string, unknown>) => link.rel === "approve")
      : null;
    if (!approval || typeof approval.href !== "string") {
      return reply(502, { error: "PayPal n’a pas renvoyé de lien d’approbation." });
    }

    const { data: latestSubscription, error: latestSubscriptionError } = await admin
      .from("business_subscriptions")
      .select("status, provider_subscription_id")
      .eq("business_id", businessId)
      .maybeSingle();
    if (latestSubscriptionError) throw latestSubscriptionError;
    const alreadyActivated = latestSubscription?.provider_subscription_id === created.id &&
      latestSubscription.status === "active";
    const { error: linkError } = await admin.from("paypal_subscription_links").upsert({
      provider_subscription_id: created.id,
      business_id: businessId,
      user_id: userData.user.id,
      plan_code: planCode,
      billing_period: period,
      environment: paypalConfig.environment,
      provider_plan_id: planId,
      status: alreadyActivated ? "active" : "approval_pending",
      updated_at: new Date().toISOString(),
    });
    if (linkError) {
      console.error("Unable to save PayPal subscription mapping", linkError);
      return reply(500, { error: "BizGestion n’a pas pu enregistrer le lien de paiement. Réessaie." });
    }
    return reply(200, {
      approval_url: approval.href,
      subscription_id: created.id,
      plan_code: planCode,
      billing_period: period,
      environment: paypalConfig.environment,
    });
  } catch (error) {
    console.error("create-paypal-subscription error", error);
    return reply(500, { error: "Impossible de préparer l’abonnement pour le moment." });
  }
});
