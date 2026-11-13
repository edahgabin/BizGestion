import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = { "Access-Control-Allow-Origin": "*" };

function json(status: number, body: Record<string, unknown>) {
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
    base: environment === "live"
      ? "https://api-m.paypal.com"
      : "https://api-m.sandbox.paypal.com",
    clientId: read("CLIENT_ID"),
    clientSecret: read("CLIENT_SECRET"),
    webhookId: read("WEBHOOK_ID"),
    planId: (planCode: string, period: string) =>
      read(`${planCode.toUpperCase()}_${period.toUpperCase()}_PLAN_ID`) ?? "",
  };
}

async function updateBusinessSubscription(
  admin: ReturnType<typeof createClient>,
  input: {
    relatedId: string;
    businessId: string;
    planCode: string;
    providerPlanId: string;
    environment: string;
    nextStatus: string;
    periodEnd: string | null;
  },
) {
  const now = new Date().toISOString();
  const { error: updateLinkError } = await admin.from("paypal_subscription_links")
    .update({ status: input.nextStatus, updated_at: now })
    .eq("provider_subscription_id", input.relatedId);
  if (updateLinkError) throw updateLinkError;

  const { error: updateSubscriptionError } = await admin
    .from("business_subscriptions")
    .update({
      plan_code: input.planCode,
      status: input.nextStatus,
      payment_provider: "paypal",
      provider_environment: input.environment,
      provider_subscription_id: input.relatedId,
      provider_plan_id: input.providerPlanId,
      current_period_end: input.periodEnd,
      updated_at: now,
    })
    .eq("business_id", input.businessId);
  if (updateSubscriptionError) throw updateSubscriptionError;
  return json(200, { received: true, updated: true });
}

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
  if (!response.ok || typeof payload.access_token !== "string") throw new Error("PayPal OAuth failed");
  return payload.access_token as string;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "Method not allowed" });
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = getPublishableKey();
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const paypalConfig = getPayPalConfig();
  const clientId = paypalConfig?.clientId;
  const paypalSecret = paypalConfig?.clientSecret;
  const webhookId = paypalConfig?.webhookId;
  if (!supabaseUrl || !publishableKey || !serviceRoleKey || !clientId || !paypalSecret || !webhookId) {
    return json(503, { error: "Webhook PayPal non configuré" });
  }

  try {
    const event = await request.json();
    const headers = request.headers;
    const verifyBody = {
      auth_algo: headers.get("paypal-auth-algo"),
      cert_url: headers.get("paypal-cert-url"),
      transmission_id: headers.get("paypal-transmission-id"),
      transmission_sig: headers.get("paypal-transmission-sig"),
      transmission_time: headers.get("paypal-transmission-time"),
      webhook_id: webhookId,
      webhook_event: event,
    };
    if (Object.values(verifyBody).some((value) => value == null)) {
      return json(400, { error: "Signature PayPal incomplète" });
    }

    if (!paypalConfig) return json(503, { error: "PayPal environment must be sandbox or live" });
    const base = paypalConfig.base;
    const token = await getPayPalToken(base, clientId, paypalSecret);
    const verifyResponse = await fetch(`${base}/v1/notifications/verify-webhook-signature`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(verifyBody),
    });
    const verification = await verifyResponse.json().catch(() => ({}));
    if (!verifyResponse.ok || verification.verification_status !== "SUCCESS") {
      console.error("PayPal webhook signature rejected", verification);
      return json(401, { error: "Signature PayPal invalide" });
    }

    const eventType = typeof event.event_type === "string" ? event.event_type : "";
    const resource = event.resource && typeof event.resource === "object" ? event.resource : {};
    const resourceId = typeof resource.id === "string" ? resource.id : "";
    const relatedId = typeof resource.billing_agreement_id === "string"
      ? resource.billing_agreement_id
      : resourceId;
    const statusByEvent: Record<string, string> = {
      "BILLING.SUBSCRIPTION.ACTIVATED": "active",
      "BILLING.SUBSCRIPTION.CANCELLED": "canceled",
      "BILLING.SUBSCRIPTION.SUSPENDED": "suspended",
      "BILLING.SUBSCRIPTION.EXPIRED": "expired",
      "BILLING.SUBSCRIPTION.PAYMENT.FAILED": "past_due",
      "PAYMENT.SALE.COMPLETED": "active",
    };
    const nextStatus = statusByEvent[eventType];
    if (!nextStatus) return json(200, { received: true, ignored: true });
    if (!relatedId) return json(400, { error: "Identifiant d’abonnement absent" });

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: link, error: linkError } = await admin
      .from("paypal_subscription_links")
      .select("business_id, plan_code, provider_plan_id, environment")
      .eq("provider_subscription_id", relatedId)
      .maybeSingle();
    if (linkError) throw linkError;
    if (link && link.environment !== Deno.env.get("PAYPAL_ENV")) {
      console.warn("Ignoring PayPal event for a different environment", relatedId);
      return json(200, { received: true, ignored: true });
    }
    if (!link) {
      // An activation notification can race with the checkout function saving its mapping.
      // Use the signed event's custom_id + plan_id to recover that mapping safely.
      const businessId = typeof resource.custom_id === "string" ? resource.custom_id : "";
      const providerPlanId = typeof resource.plan_id === "string" ? resource.plan_id : "";
      const planMappings = [
        {
          planId: paypalConfig.planId("commerce", "monthly"),
          planCode: "commerce",
          billingPeriod: "monthly",
        },
        {
          planId: paypalConfig.planId("commerce", "annual"),
          planCode: "commerce",
          billingPeriod: "annual",
        },
        {
          planId: paypalConfig.planId("entreprise", "monthly"),
          planCode: "entreprise",
          billingPeriod: "monthly",
        },
        {
          planId: paypalConfig.planId("entreprise", "annual"),
          planCode: "entreprise",
          billingPeriod: "annual",
        },
      ];
      const mapping = planMappings.find((item) => item.planId === providerPlanId);
      if (!businessId || !providerPlanId || !mapping) {
        console.warn("No BizGestion mapping for PayPal subscription", relatedId);
        return json(200, { received: true, mapped: false });
      }
      const { data: recovered, error: recoverError } = await admin
        .from("business_subscriptions")
        .select("business_id")
        .eq("business_id", businessId)
        .maybeSingle();
      if (recoverError) throw recoverError;
      if (!recovered) return json(200, { received: true, mapped: false });
      // Do not synthesize an auth.users ID from PayPal's payer ID: the two identifiers
      // belong to different systems. The checkout function will store the link shortly.
      return await updateBusinessSubscription(admin, {
        relatedId,
        businessId,
        planCode: mapping.planCode,
        providerPlanId,
        environment: Deno.env.get("PAYPAL_ENV") ?? "sandbox",
        nextStatus,
        periodEnd: typeof resource.billing_info?.next_billing_time === "string"
          ? resource.billing_info.next_billing_time
          : null,
      });
    }

    const periodEnd = typeof resource.billing_info?.next_billing_time === "string"
      ? resource.billing_info.next_billing_time
      : null;
    return await updateBusinessSubscription(admin, {
      relatedId,
      businessId: link.business_id,
      planCode: link.plan_code,
      providerPlanId: link.provider_plan_id,
      environment: link.environment,
      nextStatus,
      periodEnd,
    });
  } catch (error) {
    console.error("PayPal webhook processing failed", error);
    return json(500, { error: "Webhook processing failed" });
  }
});
