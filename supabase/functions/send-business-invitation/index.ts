const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[character] ?? character);
}

function getPublishableKey() {
  const legacyKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (legacyKey) return legacyKey;
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
    return keys.default ?? Object.values(keys)[0] ?? null;
  } catch {
    return null;
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Méthode non autorisée." });
  }

  const authorization = request.headers.get("Authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = getPublishableKey();
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const invitationFrom = Deno.env.get("INVITATION_FROM");
  const appUrl = Deno.env.get("BIZGESTION_APP_URL") ??
    "https://peaceful-seahorse-c8bdc5.netlify.app";

  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse(401, { error: "Connexion requise." });
  }
  if (!supabaseUrl || !publishableKey) {
    return jsonResponse(500, { error: "La connexion Supabase de la fonction n’est pas configurée." });
  }
  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { error: "Requête invalide." });
  }

  const businessId = typeof body.target_business_id === "string"
    ? body.target_business_id
    : "";
  const email = typeof body.invite_email === "string"
    ? body.invite_email.trim().toLowerCase()
    : "";
  const role = body.invite_role;
  if (!businessId || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) ||
    (role !== "admin" && role !== "staff")) {
    return jsonResponse(400, { error: "Commerce, adresse e-mail ou rôle invalide." });
  }

  try {
    const invitationResponse = await fetch(
      `${supabaseUrl}/rest/v1/rpc/create_business_invitation`,
      {
        method: "POST",
        headers: {
          apikey: publishableKey,
          Authorization: authorization,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          target_business_id: businessId,
          invite_email: email,
          invite_role: role,
        }),
      },
    );
    const invitationResult = await invitationResponse.json().catch(() => null);
    if (!invitationResponse.ok) {
      return jsonResponse(invitationResponse.status, {
        error: typeof invitationResult?.message === "string"
          ? invitationResult.message
          : "Impossible de préparer cette invitation.",
      });
    }

    const status = typeof invitationResult === "string"
      ? invitationResult
      : invitationResult?.status;
    if (![
      "member_added",
      "account_waiting_confirmation",
      "invitation_pending",
    ].includes(status)) {
      return jsonResponse(500, { error: "Réponse d’invitation inattendue." });
    }

    const appLink = new URL("/", appUrl);
    appLink.searchParams.set("invite", email);
    appLink.searchParams.set("create", status === "invitation_pending" ? "1" : "0");
    const safeEmail = escapeHtml(email);
    const accessLabel = role === "admin" ? "administrateur" : "employé";
    const subject = "Invitation à rejoindre un commerce sur BizGestion";
    const instruction = status === "invitation_pending"
      ? `Crée ton compte avec l’adresse ${email}. Après confirmation de ton adresse, le commerce sera associé automatiquement.`
      : status === "account_waiting_confirmation"
      ? `Ton accès est prêt. Termine d’abord la confirmation de l’adresse ${email}, puis connecte-toi à BizGestion.`
      : `Ton accès est prêt. Connecte-toi à BizGestion avec l’adresse ${email}.`;
    const html = `<!doctype html><html lang="fr"><body style="margin:0;background:#f4f6fb;font-family:Arial,sans-serif;color:#24333b"><div style="max-width:560px;margin:32px auto;padding:28px;background:#fff;border-radius:16px"><h1 style="color:#202c82;font-size:24px">Tu es invité sur BizGestion</h1><p>Tu as été ajouté comme <strong>${accessLabel}</strong> au commerce de ton équipe.</p><p>${escapeHtml(instruction)}</p><p style="margin:28px 0"><a href="${escapeHtml(appLink.toString())}" style="display:inline-block;background:#087f78;color:#fff;text-decoration:none;padding:14px 22px;border-radius:10px">${status === "invitation_pending" ? "Créer mon compte" : "Ouvrir BizGestion"}</a></p><p style="font-size:13px;color:#68717e">Si le bouton ne fonctionne pas, ouvre ce lien :<br><a href="${escapeHtml(appLink.toString())}">${escapeHtml(appLink.toString())}</a></p></div></body></html>`;
    const text = `Tu es invité sur BizGestion comme ${accessLabel}.\n\n${instruction}\n\nOuvre BizGestion ici : ${appLink.toString()}`;

    let emailSent = false;
    if (resendApiKey && invitationFrom) {
      const emailResponse = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: invitationFrom,
          to: [email],
          subject,
          html,
          text,
        }),
      });
      if (!emailResponse.ok) {
        const providerError = await emailResponse.json().catch(() => ({}));
        console.error("Envoi invitation BizGestion refuse par le fournisseur", providerError);
      } else {
        emailSent = true;
      }
    }

    return jsonResponse(200, {
      status,
      email_sent: emailSent,
      invitation_url: appLink.toString(),
    });
  } catch (error) {
    console.error("Envoi invitation BizGestion impossible", error);
    return jsonResponse(500, { error: "Impossible d’envoyer l’invitation pour le moment." });
  }
});
