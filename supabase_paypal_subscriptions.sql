-- PayPal subscription checkout mapping for BizGestion.
-- Run once in Supabase SQL Editor after supabase_business_subscriptions.sql.
alter table public.business_subscriptions
  add column if not exists provider_plan_id text;

-- Garde les abonnements de test et les abonnements réels distincts.
alter table public.business_subscriptions
  add column if not exists provider_environment text
  check (provider_environment in ('sandbox', 'live'));

update public.business_subscriptions
set provider_environment = 'sandbox'
where provider_environment is null
  and payment_provider = 'paypal'
  and provider_subscription_id is not null;

alter table public.business_subscriptions
  drop constraint if exists business_subscriptions_status_check;
alter table public.business_subscriptions
  add constraint business_subscriptions_status_check
  check (status in ('trialing', 'active', 'past_due', 'suspended', 'expired', 'canceled'));

create table if not exists public.paypal_subscription_links (
  provider_subscription_id text primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_code text not null check (plan_code in ('commerce', 'entreprise')),
  billing_period text not null check (billing_period in ('monthly', 'annual')),
  provider_plan_id text not null,
  environment text not null default 'sandbox' check (environment in ('sandbox', 'live')),
  status text not null default 'approval_pending'
    check (status in ('approval_pending', 'active', 'past_due', 'suspended', 'expired', 'canceled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.paypal_subscription_links
  add column if not exists environment text not null default 'sandbox'
  check (environment in ('sandbox', 'live'));

-- Permet aussi les abonnements payants du forfait Entreprise sur les bases
-- où la première version de cette table n'autorisait que Commerce.
alter table public.paypal_subscription_links
  drop constraint if exists paypal_subscription_links_plan_code_check;
alter table public.paypal_subscription_links
  add constraint paypal_subscription_links_plan_code_check
  check (plan_code in ('commerce', 'entreprise'));

alter table public.paypal_subscription_links enable row level security;
revoke all on public.paypal_subscription_links from public, anon, authenticated;
