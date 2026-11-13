-- Quotas du copilote IA : gratuit 5 demandes/jour; Commerce 1 695/mois;
-- Entreprise 2 825/mois. Les quotas payants sont des équivalents estimatifs
-- des enveloppes API de 300 FCFA et 500 FCFA par mois.
-- Exécuter ce script dans Supabase > SQL Editor avant de déployer la fonction.

create table if not exists public.business_ai_daily_usage (
  business_id uuid not null references public.businesses(id) on delete cascade,
  usage_date date not null,
  request_count integer not null default 0 check (request_count >= 0),
  primary key (business_id, usage_date)
);

alter table public.business_ai_daily_usage enable row level security;
revoke all on table public.business_ai_daily_usage from public, anon, authenticated;

create or replace function public.consume_business_ai_request(
  target_business_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  used_requests integer;
  used_month integer;
  member_role text;
  selected_plan text;
  selected_status text;
  monthly_limit integer;
  daily_limit integer;
  utc_today date := (pg_catalog.now() at time zone 'UTC')::date;
  utc_month_start date := date_trunc('month', pg_catalog.now() at time zone 'UTC')::date;
begin
  if (select auth.uid()) is null then
    raise exception 'Connexion requise.';
  end if;
  select role into member_role
  from public.business_members
  where business_id = target_business_id
    and user_id = (select auth.uid());
  if not found then
    raise exception 'Commerce introuvable ou accès refusé.';
  end if;
  if member_role <> 'owner' then
    raise exception 'L’IA en ligne est réservée au propriétaire du commerce.';
  end if;

  -- Sérialise les demandes d'un commerce pour éviter de dépasser son quota
  -- lorsque plusieurs membres posent une question au même moment.
  select subscription.plan_code, subscription.status
    into selected_plan, selected_status
  from public.business_subscriptions as subscription
  where subscription.business_id = target_business_id
  for update;

  if selected_plan = 'commerce' and selected_status = 'active' then
    monthly_limit := 1695;
    daily_limit := null;
  elsif selected_plan = 'entreprise' and selected_status = 'active' then
    monthly_limit := 2825;
    daily_limit := null;
  else
    monthly_limit := null;
    daily_limit := 5;
  end if;

  delete from public.business_ai_daily_usage as usage
  where usage.usage_date < utc_today - 90;

  if monthly_limit is not null then
    select coalesce(sum(usage.request_count), 0)::integer
      into used_month
    from public.business_ai_daily_usage as usage
    where usage.business_id = target_business_id
      and usage.usage_date >= utc_month_start;
    if used_month >= monthly_limit then
      return 0;
    end if;
  end if;

  insert into public.business_ai_daily_usage as daily_usage (
    business_id, usage_date, request_count
  ) values (
    target_business_id, utc_today, 1
  )
  on conflict (business_id, usage_date) do update
    set request_count = daily_usage.request_count + 1
    where daily_limit is null or daily_usage.request_count < daily_limit
  returning request_count into used_requests;

  return coalesce(used_requests, 0);
end;
$$;

revoke all on function public.consume_business_ai_request(uuid) from public, anon;
grant execute on function public.consume_business_ai_request(uuid) to authenticated;
