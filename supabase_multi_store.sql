-- BizGestion multi-store: independent data, owner dashboard, shared plan quotas.
-- Run once in Supabase SQL Editor after:
-- supabase_business_data.sql, supabase_business_subscriptions.sql,
-- supabase_paypal_subscriptions.sql, and supabase_google_play_subscriptions.sql.

alter table public.businesses
  add column if not exists location text not null default '';

-- A new store starts empty and inherits the owner's locale and active plan.
create or replace function public.create_business_branch(
  branch_name text,
  branch_location text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  source_business_id uuid;
  new_business_id uuid;
  profile_data jsonb;
  selected_plan text;
  allowed_stores integer;
  owned_store_count integer;
begin
  if actor_id is null then
    raise exception 'Connecte-toi pour créer une boutique.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(actor_id::text, 0)
  );

  if nullif(pg_catalog.btrim(branch_name), '') is null then
    raise exception 'Le nom de la boutique est obligatoire.';
  end if;

  select businesses.id, subscriptions.plan_code
    into source_business_id, selected_plan
  from public.businesses as businesses
  join public.business_members as members
    on members.business_id = businesses.id
   and members.user_id = actor_id
   and members.role = 'owner'
  join public.business_subscriptions as subscriptions
    on subscriptions.business_id = businesses.id
  where businesses.owner_id = actor_id
    and subscriptions.status in ('active', 'trialing')
    and (subscriptions.current_period_end is null
         or subscriptions.current_period_end > pg_catalog.now())
  order by case subscriptions.plan_code
             when 'entreprise' then 3
             when 'commerce' then 2
             when 'decouverte' then 1
             else 0
           end desc,
           businesses.created_at
  limit 1;

  if source_business_id is null then
    raise exception 'Aucun abonnement BizGestion actif ne permet de créer une boutique.';
  end if;

  allowed_stores := case selected_plan
    when 'commerce' then 4
    when 'entreprise' then 8
    else 2
  end;

  select count(*)::integer into owned_store_count
  from public.businesses as business
  where business.owner_id = actor_id
    and exists (
      select 1 from public.business_members as owner_membership
      where owner_membership.business_id = business.id
        and owner_membership.user_id = actor_id
        and owner_membership.role = 'owner'
    );

  if owned_store_count >= allowed_stores then
    raise exception 'Limite atteinte : le forfait actuel autorise % boutiques au total.', allowed_stores;
  end if;

  select pg_catalog.jsonb_build_object(
    'businessProfile',
    coalesce(
      data.data -> 'businessProfile',
      pg_catalog.jsonb_build_object(
        'countryCode', 'BJ',
        'currencyCode', 'XOF',
        'languageCode', 'fr'
      )
    )
  )
    into profile_data
  from public.business_data as data
  where data.business_id = source_business_id;

  insert into public.businesses (name, location, owner_id)
  values (pg_catalog.btrim(branch_name), coalesce(pg_catalog.btrim(branch_location), ''), actor_id)
  returning id into new_business_id;

  -- The business insert trigger creates a trial row; replace it before adding
  -- the owner membership, since the member-limit trigger reads this plan.
  insert into public.business_subscriptions (
    business_id, plan_code, status, trial_started_at, trial_ends_at,
    current_period_end, payment_provider, provider_subscription_id,
    provider_plan_id, provider_environment, updated_at
  )
  select
    new_business_id, source.plan_code, source.status, source.trial_started_at,
    source.trial_ends_at, source.current_period_end, source.payment_provider,
    source.provider_subscription_id, source.provider_plan_id,
    source.provider_environment, pg_catalog.now()
  from public.business_subscriptions as source
  where source.business_id = source_business_id
  on conflict (business_id) do update set
    plan_code = excluded.plan_code,
    status = excluded.status,
    trial_started_at = excluded.trial_started_at,
    trial_ends_at = excluded.trial_ends_at,
    current_period_end = excluded.current_period_end,
    payment_provider = excluded.payment_provider,
    provider_subscription_id = excluded.provider_subscription_id,
    provider_plan_id = excluded.provider_plan_id,
    provider_environment = excluded.provider_environment,
    updated_at = pg_catalog.now();

  insert into public.business_data (business_id, data)
  values (new_business_id, coalesce(profile_data, '{"businessProfile":{"countryCode":"BJ","currencyCode":"XOF","languageCode":"fr"}}'::jsonb));

  insert into public.business_members (business_id, user_id, role)
  values (new_business_id, actor_id, 'owner');

  return new_business_id;
end;
$$;

revoke all on function public.create_business_branch(text, text) from public, anon;
grant execute on function public.create_business_branch(text, text) to authenticated;

-- Owner-only read model. Each row is one store; sales, purchases, expenses,
-- stock, and customer balances never cross store boundaries. Monetary totals
-- are returned in that store's currency for the UI to group safely.
create or replace function public.get_owned_business_summaries(p_month_start date)
returns table (
  business_id uuid,
  name text,
  location text,
  currency_code text,
  products_count bigint,
  sales_count bigint,
  revenue numeric,
  expenses numeric,
  net_profit numeric,
  customer_credit numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    businesses.id as business_id,
    businesses.name,
    businesses.location,
    coalesce(data.data #>> '{businessProfile,currencyCode}', 'XOF') as currency_code,
    pg_catalog.jsonb_array_length(coalesce(data.data -> 'products', '[]'::jsonb))::bigint as products_count,
    sales_summary.sales_count,
    sales_summary.revenue,
    expense_summary.expenses,
    sales_summary.gross_profit - expense_summary.expenses as net_profit,
    credit_summary.customer_credit
  from public.businesses as businesses
  join public.business_members as members
    on members.business_id = businesses.id
   and members.user_id = (select auth.uid())
   and members.role = 'owner'
  join public.business_data as data on data.business_id = businesses.id
  cross join lateral (
    select
      count(distinct sale.value ->> 'receiptNumber')::bigint as sales_count,
      coalesce(sum(coalesce((sale.value ->> 'total')::numeric, 0)), 0) as revenue,
      coalesce(sum(
        coalesce((sale.value ->> 'total')::numeric, 0)
        - coalesce((sale.value ->> 'stockQuantity')::numeric, 0)
          * coalesce((sale.value #>> '{product,purchasePrice}')::numeric, 0)
      ), 0) as gross_profit
    from pg_catalog.jsonb_array_elements(coalesce(data.data -> 'sales', '[]'::jsonb)) as sale(value)
    where coalesce(sale.value ->> 'date', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
      and pg_catalog.substring(sale.value ->> 'date', 1, 10)::date >= pg_catalog.date_trunc('month', p_month_start::timestamp)::date
      and pg_catalog.substring(sale.value ->> 'date', 1, 10)::date < (pg_catalog.date_trunc('month', p_month_start::timestamp) + interval '1 month')::date
  ) as sales_summary
  cross join lateral (
    select coalesce(sum(coalesce((expense.value ->> 'amount')::numeric, 0)), 0) as expenses
    from pg_catalog.jsonb_array_elements(coalesce(data.data -> 'expenses', '[]'::jsonb)) as expense(value)
    where coalesce(expense.value ->> 'date', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
      and pg_catalog.substring(expense.value ->> 'date', 1, 10)::date >= pg_catalog.date_trunc('month', p_month_start::timestamp)::date
      and pg_catalog.substring(expense.value ->> 'date', 1, 10)::date < (pg_catalog.date_trunc('month', p_month_start::timestamp) + interval '1 month')::date
  ) as expense_summary
  cross join lateral (
    select coalesce(sum(coalesce((sale.value ->> 'balance')::numeric, 0)), 0) as customer_credit
    from pg_catalog.jsonb_array_elements(coalesce(data.data -> 'sales', '[]'::jsonb)) as sale(value)
  ) as credit_summary
  where businesses.owner_id = (select auth.uid())
  order by businesses.created_at, businesses.name;
$$;

revoke all on function public.get_owned_business_summaries(date) from public, anon;
grant execute on function public.get_owned_business_summaries(date) to authenticated;

-- Keep compatibility with older app versions that request the current month.
create or replace function public.get_owned_business_summaries()
returns table (
  business_id uuid,
  name text,
  location text,
  currency_code text,
  products_count bigint,
  sales_count bigint,
  revenue numeric,
  expenses numeric,
  net_profit numeric,
  customer_credit numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.get_owned_business_summaries(
    pg_catalog.date_trunc('month', pg_catalog.now())::date
  );
$$;

revoke all on function public.get_owned_business_summaries() from public, anon;
grant execute on function public.get_owned_business_summaries() to authenticated;

-- Subscription counters are shared across all stores owned by the same user.
create or replace function public.get_owned_business_usage()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'products_used', coalesce(sum(pg_catalog.jsonb_array_length(
      coalesce(data.data -> 'products', '[]'::jsonb)
    )), 0),
    'receipts_this_month', coalesce(sum((
      select count(distinct sale.value ->> 'receiptNumber')
      from pg_catalog.jsonb_array_elements(
        coalesce(data.data -> 'sales', '[]'::jsonb)
      ) as sale(value)
      where (sale.value ->> 'date')::timestamptz >= pg_catalog.date_trunc('month', pg_catalog.now())
        and (sale.value ->> 'date')::timestamptz < pg_catalog.date_trunc('month', pg_catalog.now()) + interval '1 month'
    )), 0),
    'total_receipts', coalesce(sum((
      select count(distinct sale.value ->> 'receiptNumber')
      from pg_catalog.jsonb_array_elements(
        coalesce(data.data -> 'sales', '[]'::jsonb)
      ) as sale(value)
    )), 0)
  )
  from public.businesses as business
  join public.business_members as membership
    on membership.business_id = business.id
   and membership.user_id = (select auth.uid())
   and membership.role = 'owner'
  join public.business_data as data on data.business_id = business.id
  where business.owner_id = (select auth.uid());
$$;

revoke all on function public.get_owned_business_usage() from public, anon;
grant execute on function public.get_owned_business_usage() to authenticated;

-- Enforce product and receipt limits across all of an owner's stores.
create or replace function public.enforce_owner_plan_data_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_user_id uuid;
  selected_plan text;
  product_limit integer;
  monthly_receipt_limit integer;
  product_count bigint;
  receipt_count bigint;
begin
  select business.owner_id, subscription.plan_code
    into owner_user_id, selected_plan
  from public.businesses as business
  join public.business_subscriptions as subscription
    on subscription.business_id = business.id
  where business.id = new.business_id;

  if owner_user_id is null or selected_plan is null then
    raise exception 'Abonnement BizGestion introuvable.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(owner_user_id::text, 0)
  );

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

  select coalesce(sum(pg_catalog.jsonb_array_length(
      coalesce(case when business.id = new.business_id then new.data else data.data end -> 'products', '[]'::jsonb)
    )), 0)
    into product_count
  from public.businesses as business
  join public.business_data as data on data.business_id = business.id
  where business.owner_id = owner_user_id;

  select coalesce(sum((
      select count(distinct sale.value ->> 'receiptNumber')
      from pg_catalog.jsonb_array_elements(
        coalesce(case when business.id = new.business_id then new.data else data.data end -> 'sales', '[]'::jsonb)
      ) as sale(value)
      where (sale.value ->> 'date')::timestamptz >= pg_catalog.date_trunc('month', pg_catalog.now())
        and (sale.value ->> 'date')::timestamptz < pg_catalog.date_trunc('month', pg_catalog.now()) + interval '1 month'
    )), 0)
    into receipt_count
  from public.businesses as business
  join public.business_data as data on data.business_id = business.id
  where business.owner_id = owner_user_id;

  if product_count > product_limit then
    raise exception 'Limite atteinte : le forfait accepte % produits au total pour toutes les boutiques.', product_limit;
  end if;
  if receipt_count > monthly_receipt_limit then
    raise exception 'Limite atteinte : le forfait accepte % reçus par mois au total pour toutes les boutiques.', monthly_receipt_limit;
  end if;
  return new;
end;
$$;

drop trigger if exists aaa_enforce_business_plan_data_limits on public.business_data;
drop trigger if exists aaa_enforce_owner_plan_data_limits on public.business_data;
create trigger aaa_enforce_owner_plan_data_limits
  before insert or update on public.business_data
  for each row execute procedure public.enforce_owner_plan_data_limits();

revoke all on function public.enforce_owner_plan_data_limits() from public, anon, authenticated;

-- Keep an owner's paid plan consistent across all their stores. This trigger
-- also handles renewal, cancellation, and plan changes received from PayPal or
-- Google Play, while pg_trigger_depth prevents a recursive update loop.
create or replace function public.sync_owner_enterprise_subscriptions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_user_id uuid;
begin
  if pg_catalog.pg_trigger_depth() > 1 then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.plan_code is not distinct from new.plan_code
     and old.status is not distinct from new.status
     and old.trial_started_at is not distinct from new.trial_started_at
     and old.trial_ends_at is not distinct from new.trial_ends_at
     and old.current_period_end is not distinct from new.current_period_end
     and old.payment_provider is not distinct from new.payment_provider
     and old.provider_subscription_id is not distinct from new.provider_subscription_id
     and old.provider_plan_id is not distinct from new.provider_plan_id
     and old.provider_environment is not distinct from new.provider_environment then
    return new;
  end if;

  select businesses.owner_id into owner_user_id
  from public.businesses as businesses
  where businesses.id = new.business_id;

  if owner_user_id is null then
    return new;
  end if;

  -- The businesses trigger inserts a temporary trial subscription before the
  -- new branch has an owner membership. Never let that placeholder overwrite
  -- the active subscription on the owner's existing stores.
  if not exists (
    select 1 from public.business_members as source_owner_membership
    where source_owner_membership.business_id = new.business_id
      and source_owner_membership.user_id = owner_user_id
      and source_owner_membership.role = 'owner'
  ) then
    return new;
  end if;

  update public.business_subscriptions as sibling
  set plan_code = new.plan_code,
      status = new.status,
      trial_started_at = new.trial_started_at,
      trial_ends_at = new.trial_ends_at,
      current_period_end = new.current_period_end,
      payment_provider = new.payment_provider,
      provider_subscription_id = new.provider_subscription_id,
      provider_plan_id = new.provider_plan_id,
      provider_environment = new.provider_environment,
      updated_at = pg_catalog.now()
  from public.businesses as business
  where business.id = sibling.business_id
    and business.owner_id = owner_user_id
    and sibling.business_id <> new.business_id
    and exists (
      select 1 from public.business_members as owner_membership
      where owner_membership.business_id = business.id
        and owner_membership.user_id = owner_user_id
        and owner_membership.role = 'owner'
    )
    and (
      sibling.plan_code is distinct from new.plan_code
      or sibling.status is distinct from new.status
      or sibling.trial_started_at is distinct from new.trial_started_at
      or sibling.trial_ends_at is distinct from new.trial_ends_at
      or sibling.current_period_end is distinct from new.current_period_end
      or sibling.payment_provider is distinct from new.payment_provider
      or sibling.provider_subscription_id is distinct from new.provider_subscription_id
      or sibling.provider_plan_id is distinct from new.provider_plan_id
      or sibling.provider_environment is distinct from new.provider_environment
    );

  return new;
end;
$$;

drop trigger if exists sync_owner_enterprise_subscriptions on public.business_subscriptions;
create trigger sync_owner_enterprise_subscriptions
  after insert or update on public.business_subscriptions
  for each row execute procedure public.sync_owner_enterprise_subscriptions();

revoke all on function public.sync_owner_enterprise_subscriptions() from public, anon, authenticated;
