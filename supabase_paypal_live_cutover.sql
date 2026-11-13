-- À exécuter une seule fois au passage de Sandbox à Live, après avoir résilié
-- les abonnements de test dans PayPal Sandbox.
-- Les dates d'essai et les enregistrements d'historique PayPal sont conservés.
-- Seul le forfait courant financé par un abonnement Sandbox est remis à l'essai.

update public.business_subscriptions
set plan_code = 'trial',
    status = 'trialing',
    payment_provider = null,
    provider_environment = null,
    provider_subscription_id = null,
    provider_plan_id = null,
    current_period_end = null,
    updated_at = now()
where payment_provider = 'paypal'
  and coalesce(provider_environment, 'sandbox') = 'sandbox'
  and provider_subscription_id is not null;
