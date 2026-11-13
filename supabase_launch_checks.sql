-- Contrôles de préparation BizGestion, sans modification de données.
-- À exécuter après les migrations, dans Supabase > SQL Editor.
with checks as (
  select 'Table commerces' as check_name,
         to_regclass('public.businesses') is not null as ok,
         coalesce(to_regclass('public.businesses')::text, 'absente') as detail
  union all
  select 'Table membres', to_regclass('public.business_members') is not null,
         coalesce(to_regclass('public.business_members')::text, 'absente')
  union all
  select 'Données commerce protégées par RLS', coalesce((
    select relrowsecurity from pg_class where oid = to_regclass('public.business_data')
  ), false), 'public.business_data'
  union all
  select 'Limites / abonnements installés', to_regclass('public.business_subscriptions') is not null,
         coalesce(to_regclass('public.business_subscriptions')::text, 'absente')
  union all
  select 'Création automatique de l’essai', exists (
    select 1
    from pg_trigger as trigger_row
    join pg_class as relation on relation.oid = trigger_row.tgrelid
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'businesses'
      and trigger_row.tgname = 'create_business_subscription_trial'
      and not trigger_row.tgisinternal
  ), 'trigger create_business_subscription_trial sur public.businesses'
  union all
  select 'Limites produits et ventes activées', exists (
    select 1
    from pg_trigger as trigger_row
    join pg_class as relation on relation.oid = trigger_row.tgrelid
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'business_data'
      and trigger_row.tgname = 'aaa_enforce_business_plan_data_limits'
      and not trigger_row.tgisinternal
  ), 'trigger aaa_enforce_business_plan_data_limits sur public.business_data'
  union all
  select 'Limites de membres activées', exists (
    select 1
    from pg_trigger as trigger_row
    join pg_class as relation on relation.oid = trigger_row.tgrelid
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'business_members'
      and trigger_row.tgname = 'aaa_enforce_business_plan_member_limit'
      and not trigger_row.tgisinternal
  ), 'trigger aaa_enforce_business_plan_member_limit sur public.business_members'
  union all
  select 'Invitation équipe installée', to_regclass('public.business_invitations') is not null,
         coalesce(to_regclass('public.business_invitations')::text, 'absente')
  union all
  select 'Invitation manuelle sans service de courriel',
         to_regprocedure('public.create_business_invitation(uuid,text,text)') is not null,
         'create_business_invitation(uuid,text,text)'
  union all
  select 'Inscription des invités reliée au commerce', exists (
    select 1
    from pg_trigger as trigger_row
    join pg_class as relation on relation.oid = trigger_row.tgrelid
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    join pg_proc as trigger_function on trigger_function.oid = trigger_row.tgfoid
    join pg_namespace as function_namespace on function_namespace.oid = trigger_function.pronamespace
    where namespace.nspname = 'auth'
      and relation.relname = 'users'
      and trigger_row.tgname = 'on_auth_user_created_bizgestion'
      and not trigger_row.tgisinternal
      and function_namespace.nspname = 'public'
      and trigger_function.proname = 'create_bizgestion_business_for_new_user'
      and position('business_invitations' in lower(pg_get_functiondef(trigger_function.oid))) > 0
  ), 'auth.users → public.create_bizgestion_business_for_new_user() avec rattachement des invitations'
  union all
  select 'Miroir indexé installé', to_regclass('public.business_records') is not null,
         coalesce(to_regclass('public.business_records')::text, 'absente')
  union all
  select 'Miroir protégé par RLS', coalesce((
    select relrowsecurity from pg_class where oid = to_regclass('public.business_records')
  ), false), 'public.business_records'
  union all
  select 'État de synchronisation installé', to_regclass('public.business_record_sync_state') is not null,
         coalesce(to_regclass('public.business_record_sync_state')::text, 'absente')
  union all
  select 'RPC de lecture sécurisée', to_regprocedure('public.load_business_records_snapshot(uuid)') is not null,
         'load_business_records_snapshot(uuid)'
  union all
  select 'Langue du commerce partagée avec les employés', exists (
    select 1 from pg_proc as procedure_row
    where procedure_row.oid = to_regprocedure('public.load_business_records_snapshot(uuid)')
      and position('businessProfile' in pg_get_functiondef(procedure_row.oid)) > 0
  ), 'load_business_records_snapshot inclut businessProfile'
  union all
  select 'RPC de sauvegarde sécurisée', to_regprocedure('public.save_business_records_snapshot(uuid,jsonb,bigint)') is not null,
         'save_business_records_snapshot(uuid,jsonb,bigint)'
  union all
  select 'RPC de sauvegarde par modifications', to_regprocedure('public.save_business_records_delta(uuid,jsonb,jsonb,jsonb,bigint)') is not null,
         'save_business_records_delta(uuid,jsonb,jsonb,jsonb,bigint)'
  union all
  select 'RPC des ventes paginées', to_regprocedure('public.load_business_sales_page(uuid,integer,integer)') is not null,
         'load_business_sales_page(uuid,integer,integer)'
  union all
  select 'RPC générique des collections paginées', to_regprocedure('public.load_business_record_page(uuid,text,integer,bigint)') is not null,
         'load_business_record_page(uuid,text,integer,bigint)'
  union all
  select 'Index d’ordre des collections', to_regclass('public.business_records_order_idx') is not null,
         coalesce(to_regclass('public.business_records_order_idx')::text, 'absent')
  union all
  select 'Curseur de pagination en bigint', coalesce((
    select data_type = 'bigint'
    from information_schema.columns
    where table_schema = 'public' and table_name = 'business_records'
      and column_name = 'position'
  ), false), 'public.business_records.position'
  union all
  select 'Fonction équipe disponible', to_regprocedure('public.list_business_access(uuid)') is not null,
         'list_business_access(uuid)'
  union all
  select 'Bucket photo privé disponible', exists (
    select 1 from storage.buckets where id = 'product-images' and public = false
  ), 'storage.buckets: product-images (privé)'
  union all
  select 'Signaux temps réel publiés', exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'business_data_updates'
  ), 'supabase_realtime: public.business_data_updates'
)
select check_name, ok, detail
from checks
order by ok, check_name;
