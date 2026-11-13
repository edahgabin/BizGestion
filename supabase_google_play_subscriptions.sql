-- Google Play subscription verification links. Raw purchase tokens are never stored.
-- Run after supabase_business_subscriptions.sql and supabase_paypal_subscriptions.sql.
create table if not exists public.google_play_subscription_links (
  purchase_token_hash text primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null check (product_id in (
    'bizgestion_commerce_monthly',
    'bizgestion_commerce_annual',
    'bizgestion_entreprise_monthly',
    'bizgestion_entreprise_annual'
  )),
  plan_code text not null check (plan_code in ('commerce', 'entreprise')),
  status text not null check (status in ('active', 'canceled', 'expired', 'past_due')),
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.google_play_subscription_links enable row level security;
revoke all on public.google_play_subscription_links from public, anon, authenticated;

alter table public.business_subscriptions
  drop constraint if exists business_subscriptions_payment_provider_check;
alter table public.business_subscriptions
  add constraint business_subscriptions_payment_provider_check
  check (payment_provider is null or payment_provider in ('paypal', 'google_play'));
