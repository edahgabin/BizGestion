-- BizGestion: suivi de l'essai et limites par commerce.
-- Exécuter une fois dans Supabase > SQL Editor.
-- Cette migration ne prélève aucun paiement et ne bloque pas l'application à la fin de l'essai.

create table if not exists public.business_subscriptions (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  plan_code text not null default 'trial'
    check (plan_code in ('trial', 'decouverte', 'commerce', 'entreprise')),
  status text not null default 'trialing'
    check (status in ('trialing', 'active', 'expired', 'canceled')),
  trial_started_at timestamptz not null default now(),
  trial_ends_at timestamptz not null default (now() + interval '14 days'),
  current_period_end timestamptz,
  payment_provider text,
  provider_subscription_id text,
  updated_at timestamptz not null default now()
);

alter table public.business_subscriptions enable row level security;
revoke all on public.business_subscriptions from public, anon, authenticated;
grant select on public.business_subscriptions to authenticated;

drop policy if exists "Members can read their subscription" on public.business_subscriptions;
create policy "Members can read their subscription"
  on public.business_subscriptions for select to authenticated
  using (public.is_business_member(business_id));

-- Crée une période d'essai pour les commerces existants.
insert into public.business_subscriptions (business_id)
select id from public.businesses
on conflict (business_id) do nothing;

create or replace function public.create_business_subscription_trial()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.business_subscriptions (business_id)
  values (new.id)
  on conflict (business_id) do nothing;
  return new;
end;
$$;

drop trigger if exists create_business_subscription_trial on public.businesses;
create trigger create_business_subscription_trial
  after insert on public.businesses
  for each row execute procedure public.create_business_subscription_trial();

-- Limites provisoires proposées : essai/Découverte 50 produits, 500 reçus/mois,
-- 5 membres; Commerce 500, 10 000, 10; Entreprise 5 000, 100 000, 50.
-- La limite de reçus compte les tickets, pas chaque ligne de produit.
create or replace function public.enforce_business_plan_data_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_plan text;
  product_limit integer;
  monthly_receipt_limit integer;
  receipt_count integer;
  month_start timestamptz := date_trunc('month', now());
begin
  select plan_code into selected_plan
  from public.business_subscriptions
  where business_id = new.business_id;

  if selected_plan is null then
    raise exception 'Abonnement BizGestion introuvable. Exécute la migration des abonnements puis recharge l’application.';
  end if;

  case selected_plan
    when 'trial', 'decouverte' then
      product_limit := 50;
      monthly_receipt_limit := 500;
    when 'commerce' then
      product_limit := 500;
      monthly_receipt_limit := 10000;
    when 'entreprise' then
      product_limit := 5000;
      monthly_receipt_limit := 100000;
    else
      raise exception 'Forfait BizGestion inconnu.';
  end case;

  if jsonb_array_length(coalesce(new.data -> 'products', '[]'::jsonb)) > product_limit then
    raise exception 'Limite atteinte : ce forfait accepte % produits. Contacte BizGestion pour changer de forfait.', product_limit;
  end if;

  select count(distinct sale.value ->> 'receiptNumber')::integer into receipt_count
  from jsonb_array_elements(coalesce(new.data -> 'sales', '[]'::jsonb)) as sale(value)
  where (sale.value ->> 'date')::timestamptz >= month_start
    and (sale.value ->> 'date')::timestamptz < month_start + interval '1 month';

  if receipt_count > monthly_receipt_limit then
    raise exception 'Limite atteinte : ce forfait accepte % reçus par mois. Contacte BizGestion pour changer de forfait.', monthly_receipt_limit;
  end if;
  return new;
end;
$$;

drop trigger if exists aaa_enforce_business_plan_data_limits on public.business_data;
create trigger aaa_enforce_business_plan_data_limits
  before update on public.business_data
  for each row execute procedure public.enforce_business_plan_data_limits();

create or replace function public.enforce_business_plan_member_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_plan text;
  member_limit integer;
  current_members integer;
begin
  select plan_code into selected_plan
  from public.business_subscriptions
  where business_id = new.business_id;
  if selected_plan is null then
    raise exception 'Abonnement BizGestion introuvable. Exécute la migration des abonnements puis recharge l’application.';
  end if;

  member_limit := case selected_plan
    when 'trial' then 5
    when 'decouverte' then 5
    when 'commerce' then 10
    when 'entreprise' then 50
    else 0
  end;
  select count(*)::integer into current_members
  from public.business_members where business_id = new.business_id;
  if current_members >= member_limit then
    raise exception 'Limite atteinte : ce forfait accepte % membres. Contacte BizGestion pour changer de forfait.', member_limit;
  end if;
  return new;
end;
$$;

drop trigger if exists aaa_enforce_business_plan_member_limit on public.business_members;
create trigger aaa_enforce_business_plan_member_limit
  before insert on public.business_members
  for each row execute procedure public.enforce_business_plan_member_limit();
