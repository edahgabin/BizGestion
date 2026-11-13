-- Migration additive vers des lignes indexées, sans toucher aux données source.
-- business_data reste la source de vérité et le format du cache local reste
-- inchangé. Les ventes sont lues par page; les autres collections sont encore
-- chargées sous forme de snapshot complet.

create table if not exists public.business_records (
  business_id uuid not null references public.businesses (id) on delete cascade,
  collection text not null check (collection in (
    'products', 'suppliers', 'purchases', 'sales', 'payments', 'refunds',
    'expenses', 'stocktakes', 'cashMovements'
  )),
  record_key text not null,
  position bigint not null,
  occurred_at timestamptz,
  payload jsonb not null,
  migrated_at timestamptz not null default now(),
  primary key (business_id, collection, record_key)
);

alter table public.business_records
  add column if not exists position bigint not null default 0;
alter table public.business_records
  alter column position type bigint;

create index if not exists business_records_timeline_idx
  on public.business_records (business_id, collection, occurred_at desc);
create index if not exists business_records_order_idx
  on public.business_records (business_id, collection, position);
create index if not exists business_sales_receipt_order_idx
  on public.business_records (
    business_id, (payload ->> 'receiptNumber'), position
  ) where collection = 'sales';

alter table public.business_records enable row level security;
revoke all on public.business_records from anon, authenticated;

-- Reconstruit une copie du commerce depuis l’instantané courant. Le contenu et
-- la position préservent les entrées identiques. business_data reste intact.
create or replace function public.migrate_business_snapshot_to_records(
  target_business_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_data jsonb;
  member_role text;
  migrated_rows bigint;
  counts jsonb;
begin
  select members.role into member_role
  from public.business_members as members
  where members.business_id = target_business_id
    and members.user_id = (select auth.uid());

  if member_role is null or member_role not in ('owner', 'admin') then
    raise exception 'Seul le propriétaire ou un administrateur peut préparer la migration.';
  end if;

  select data.data into source_data
  from public.business_data as data
  where data.business_id = target_business_id
  for share;
  if source_data is null then
    raise exception 'Aucune donnée à migrer pour ce commerce.';
  end if;

  delete from public.business_records as records
  where records.business_id = target_business_id;

  insert into public.business_records (
    business_id, collection, record_key, position, occurred_at, payload
  )
  select
    target_business_id,
    source.collection,
    coalesce(
      nullif(item.value ->> 'recordId', ''),
      pg_catalog.md5(
        item.value::text || ':' ||
        pg_catalog.row_number() over (
          partition by source.collection, item.value::text
          order by item.ordinality
        )::text
      )
    ),
    item.ordinality::bigint,
    nullif(item.value ->> 'date', '')::timestamptz,
    item.value
  from (
    values
      ('products', case when pg_catalog.jsonb_typeof(source_data -> 'products') = 'array' then source_data -> 'products' else '[]'::jsonb end),
      ('suppliers', case when pg_catalog.jsonb_typeof(source_data -> 'suppliers') = 'array' then source_data -> 'suppliers' else '[]'::jsonb end),
      ('purchases', case when pg_catalog.jsonb_typeof(source_data -> 'purchases') = 'array' then source_data -> 'purchases' else '[]'::jsonb end),
      ('sales', case when pg_catalog.jsonb_typeof(source_data -> 'sales') = 'array' then source_data -> 'sales' else '[]'::jsonb end),
      ('payments', case when pg_catalog.jsonb_typeof(source_data -> 'payments') = 'array' then source_data -> 'payments' else '[]'::jsonb end),
      ('refunds', case when pg_catalog.jsonb_typeof(source_data -> 'refunds') = 'array' then source_data -> 'refunds' else '[]'::jsonb end),
      ('expenses', case when pg_catalog.jsonb_typeof(source_data -> 'expenses') = 'array' then source_data -> 'expenses' else '[]'::jsonb end),
      ('stocktakes', case when pg_catalog.jsonb_typeof(source_data -> 'stocktakes') = 'array' then source_data -> 'stocktakes' else '[]'::jsonb end),
      ('cashMovements', case when pg_catalog.jsonb_typeof(source_data -> 'cashMovements') = 'array' then source_data -> 'cashMovements' else '[]'::jsonb end)
  ) as source(collection, records)
  cross join lateral pg_catalog.jsonb_array_elements(source.records)
    with ordinality as item(value, ordinality);

  get diagnostics migrated_rows = row_count;

  select coalesce(pg_catalog.jsonb_object_agg(summary.collection, summary.row_count), '{}'::jsonb)
    into counts
  from (
    select records.collection, count(*) as row_count
    from public.business_records as records
    where records.business_id = target_business_id
    group by records.collection
  ) as summary;

  return pg_catalog.jsonb_build_object(
    'business_id', target_business_id,
    'migrated_rows', migrated_rows,
    'collections', counts
  );
end;
$$;

revoke all on function public.migrate_business_snapshot_to_records(uuid) from public;
grant execute on function public.migrate_business_snapshot_to_records(uuid) to authenticated;

-- L’accès à business_records reste fermé directement ; Flutter passera par les
-- fonctions sécurisées ci-dessous.

-- État de synchronisation entre la source historique JSONB et les lignes.
create table if not exists public.business_record_sync_state (
  business_id uuid primary key references public.businesses (id) on delete cascade,
  source_revision bigint not null,
  synced_at timestamptz not null default now()
);
alter table public.business_record_sync_state enable row level security;
revoke all on public.business_record_sync_state from anon, authenticated;

-- Fonction interne : reconstruit le miroir indexé dans la même transaction.
create or replace function public.refresh_business_records_from_snapshot(
  target_business_id uuid,
  source_data jsonb,
  source_revision bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_collection record;
  existing_records jsonb;
  current_min_position bigint;
begin
  for source_collection in
    select source.collection, source.records
    from (
      values
        ('products', case when pg_catalog.jsonb_typeof(source_data -> 'products') = 'array' then source_data -> 'products' else '[]'::jsonb end),
        ('suppliers', case when pg_catalog.jsonb_typeof(source_data -> 'suppliers') = 'array' then source_data -> 'suppliers' else '[]'::jsonb end),
        ('purchases', case when pg_catalog.jsonb_typeof(source_data -> 'purchases') = 'array' then source_data -> 'purchases' else '[]'::jsonb end),
        ('sales', case when pg_catalog.jsonb_typeof(source_data -> 'sales') = 'array' then source_data -> 'sales' else '[]'::jsonb end),
        ('payments', case when pg_catalog.jsonb_typeof(source_data -> 'payments') = 'array' then source_data -> 'payments' else '[]'::jsonb end),
        ('refunds', case when pg_catalog.jsonb_typeof(source_data -> 'refunds') = 'array' then source_data -> 'refunds' else '[]'::jsonb end),
        ('expenses', case when pg_catalog.jsonb_typeof(source_data -> 'expenses') = 'array' then source_data -> 'expenses' else '[]'::jsonb end),
        ('stocktakes', case when pg_catalog.jsonb_typeof(source_data -> 'stocktakes') = 'array' then source_data -> 'stocktakes' else '[]'::jsonb end),
        ('cashMovements', case when pg_catalog.jsonb_typeof(source_data -> 'cashMovements') = 'array' then source_data -> 'cashMovements' else '[]'::jsonb end)
    ) as source(collection, records)
  loop
    select coalesce(pg_catalog.jsonb_agg(records.payload order by records.position), '[]'::jsonb)
      into existing_records
    from public.business_records as records
    where records.business_id = target_business_id
      and records.collection = source_collection.collection;

    if existing_records is distinct from source_collection.records then
      -- Keep unchanged records in place. The occurrence suffix distinguishes
      -- identical rows while keeping their keys stable when unrelated rows are
      -- inserted or removed elsewhere in the collection.
      delete from public.business_records as records
      where records.business_id = target_business_id
        and records.collection = source_collection.collection
        and not exists (
          select 1
          from (
             select coalesce(
                      nullif(incoming.value ->> 'recordId', ''),
                      pg_catalog.md5(
                        incoming.value::text || ':' ||
                        pg_catalog.row_number() over (
                          partition by incoming.value::text
                          order by incoming.ordinality
                        )::text
                      )
                    ) as record_key
            from pg_catalog.jsonb_array_elements(source_collection.records)
              with ordinality as incoming(value, ordinality)
          ) as desired
          where desired.record_key = records.record_key
        );

      select coalesce(min(records.position), 1)
        into current_min_position
      from public.business_records as records
      where records.business_id = target_business_id
        and records.collection = source_collection.collection;

      -- Give only newly observed records positions before the existing ones.
      -- Existing rows keep their position when a new item is prepended.
      insert into public.business_records (
        business_id, collection, record_key, position, occurred_at, payload
      )
      select
        target_business_id,
        source_collection.collection,
        incoming.record_key,
        current_min_position - incoming.new_count + incoming.new_order - 1,
        nullif(incoming.value ->> 'date', '')::timestamptz,
        incoming.value
      from (
        select desired.*,
               pg_catalog.row_number() over (order by desired.ordinality) as new_order,
               pg_catalog.count(*) over () as new_count
        from (
          select incoming.value,
                 incoming.ordinality,
                 coalesce(
                   nullif(incoming.value ->> 'recordId', ''),
                   pg_catalog.md5(
                     incoming.value::text || ':' ||
                     pg_catalog.row_number() over (
                       partition by incoming.value::text
                       order by incoming.ordinality
                     )::text
                   )
                 ) as record_key
          from pg_catalog.jsonb_array_elements(source_collection.records)
            with ordinality as incoming(value, ordinality)
        ) as desired
        where not exists (
          select 1
          from public.business_records as current_record
          where current_record.business_id = target_business_id
            and current_record.collection = source_collection.collection
            and current_record.record_key = desired.record_key
        )
      ) as incoming;

      -- A full snapshot can change an existing record without changing its
      -- key (for example, a product's quantity after replenishment). Keep its
      -- ordering, but refresh the stored payload and date from the snapshot.
      update public.business_records as records
      set occurred_at = nullif(incoming.value ->> 'date', '')::timestamptz,
          payload = incoming.value
      from (
        select incoming.value,
               coalesce(
                 nullif(incoming.value ->> 'recordId', ''),
                 pg_catalog.md5(
                   incoming.value::text || ':' ||
                   pg_catalog.row_number() over (
                     partition by incoming.value::text
                     order by incoming.ordinality
                   )::text
                 )
               ) as record_key
        from pg_catalog.jsonb_array_elements(source_collection.records)
          with ordinality as incoming(value, ordinality)
      ) as incoming
      where records.business_id = target_business_id
        and records.collection = source_collection.collection
        and records.record_key = incoming.record_key
        and records.payload is distinct from incoming.value;
    end if;
  end loop;

  insert into public.business_record_sync_state (business_id, source_revision)
  values (target_business_id, source_revision)
  on conflict (business_id) do update
    set source_revision = excluded.source_revision,
        synced_at = now();
end;
$$;
revoke all on function public.refresh_business_records_from_snapshot(uuid, jsonb, bigint) from public;
revoke all on function public.refresh_business_records_from_snapshot(uuid, jsonb, bigint) from authenticated;

-- Charge la même forme JSON qu’avant, mais depuis les lignes indexées. Les
-- métadonnées restent lues depuis la ligne source. Le rôle Employé ne reçoit
-- jamais les coûts ni les collections réservées à la gestion.
create or replace function public.load_business_records_snapshot(target_business_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_data jsonb;
  visible_data jsonb;
  record_collections jsonb;
  source_revision bigint;
  synced_revision bigint;
  member_role text;
begin
  select data.data, data.revision, members.role
    into source_data, source_revision, member_role
  from public.business_data as data
  join public.business_members as members
    on members.business_id = data.business_id
  where data.business_id = target_business_id
    and members.user_id = (select auth.uid())
  for share of data;
  if not found then
    raise exception 'Commerce introuvable ou accès refusé.';
  end if;

  select state.source_revision into synced_revision
  from public.business_record_sync_state as state
  where state.business_id = target_business_id;
  if synced_revision is distinct from source_revision then
    perform public.refresh_business_records_from_snapshot(
      target_business_id, source_data, source_revision
    );
  end if;

  select coalesce(pg_catalog.jsonb_object_agg(rows.collection, rows.items), '{}'::jsonb)
    into record_collections
  from (
    select records.collection,
           pg_catalog.jsonb_agg(
             records.payload || pg_catalog.jsonb_build_object('recordId', records.record_key)
             order by records.position
           ) as items
    from public.business_records as records
    where records.business_id = target_business_id
    group by records.collection
  ) as rows;

  visible_data := (source_data - array[
    'products', 'suppliers', 'purchases', 'sales', 'payments', 'refunds',
    'expenses', 'stocktakes', 'cashMovements'
  ]) || record_collections || pg_catalog.jsonb_build_object(
    'products', coalesce(record_collections -> 'products', '[]'::jsonb),
    'suppliers', coalesce(record_collections -> 'suppliers', '[]'::jsonb),
    'purchases', coalesce(record_collections -> 'purchases', '[]'::jsonb),
    'sales', coalesce(record_collections -> 'sales', '[]'::jsonb),
    'payments', coalesce(record_collections -> 'payments', '[]'::jsonb),
    'refunds', coalesce(record_collections -> 'refunds', '[]'::jsonb),
    'expenses', coalesce(record_collections -> 'expenses', '[]'::jsonb),
    'stocktakes', coalesce(record_collections -> 'stocktakes', '[]'::jsonb),
    'cashMovements', coalesce(record_collections -> 'cashMovements', '[]'::jsonb)
  );

  if member_role = 'staff' then
    visible_data := pg_catalog.jsonb_set(visible_data, '{products}', coalesce((
      select pg_catalog.jsonb_agg(
        product.payload || pg_catalog.jsonb_build_object('recordId', product.record_key, 'purchasePrice', 0)
        order by product.position
      )
      from public.business_records as product
      where product.business_id = target_business_id and product.collection = 'products'
    ), '[]'::jsonb), true);
    visible_data := pg_catalog.jsonb_set(visible_data, '{sales}', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_set(
          sale.payload || pg_catalog.jsonb_build_object('recordId', sale.record_key),
          '{product,purchasePrice}', '0'::jsonb, true
        )
        order by sale.position
      )
      from public.business_records as sale
      where sale.business_id = target_business_id and sale.collection = 'sales'
    ), '[]'::jsonb), true);
    visible_data := visible_data || pg_catalog.jsonb_build_object(
      'suppliers', '[]'::jsonb,
      'purchases', '[]'::jsonb,
      'refunds', '[]'::jsonb,
      'expenses', '[]'::jsonb,
      'stocktakes', '[]'::jsonb,
      'cashMovements', '[]'::jsonb
    );
    -- Staff share the commerce locale and receipt settings; they do not own
    -- these values, so clients must always read them from the cloud snapshot.
    visible_data := visible_data || pg_catalog.jsonb_build_object(
      'businessProfile', coalesce(source_data -> 'businessProfile', '{}'::jsonb)
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'data', visible_data,
    'revision', source_revision
  );
end;
$$;

-- Sauvegarde réutilisant les validations, limites d’abonnement et règles de
-- rôle de l’ancienne fonction, puis synchronise les lignes avant le commit.
create or replace function public.save_business_records_snapshot(
  target_business_id uuid,
  new_data jsonb,
  expected_revision bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  saved_revision bigint;
  saved_data jsonb;
begin
  saved_revision := public.save_business_snapshot(
    target_business_id, new_data, expected_revision
  );
  select data.data into saved_data
  from public.business_data as data
  where data.business_id = target_business_id;
  perform public.refresh_business_records_from_snapshot(
    target_business_id, saved_data, saved_revision
  );
  return saved_revision;
end;
$$;

revoke all on function public.load_business_records_snapshot(uuid) from public;
revoke all on function public.save_business_records_snapshot(uuid, jsonb, bigint) from public;
grant execute on function public.load_business_records_snapshot(uuid) to authenticated;
grant execute on function public.save_business_records_snapshot(uuid, jsonb, bigint) to authenticated;

-- Envoie uniquement les lignes ajoutées ou modifiées et les clés supprimées.
-- Le snapshot historique est encore reconstruit côté serveur pour préserver
-- les lecteurs des anciennes versions et les contrôles d'abonnement existants.
create or replace function public.save_business_records_delta(
  target_business_id uuid,
  record_changes jsonb,
  deleted_records jsonb,
  metadata_changes jsonb,
  expected_revision bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_data jsonb;
  current_revision bigint;
  member_role text;
  source_sync_revision bigint;
  collection_name text;
  current_min_position bigint;
  saved_revision bigint;
  merged_data jsonb;
  record_collections jsonb;
begin
  select data.data, data.revision, members.role
    into source_data, current_revision, member_role
  from public.business_data as data
  join public.business_members as members
    on members.business_id = data.business_id
  where data.business_id = target_business_id
    and members.user_id = (select auth.uid())
  for update of data;

  if not found then
    raise exception 'Commerce introuvable ou accès refusé.';
  end if;
  if member_role not in ('owner', 'admin') then
    raise exception 'La sauvegarde par modifications est réservée au propriétaire et à l’administrateur.';
  end if;
  if current_revision is distinct from expected_revision then
    raise exception 'Conflit de synchronisation : recharge BizGestion avant de réessayer.';
  end if;
  if pg_catalog.jsonb_typeof(coalesce(record_changes, '{}'::jsonb)) <> 'object'
     or pg_catalog.jsonb_typeof(coalesce(deleted_records, '{}'::jsonb)) <> 'object'
     or pg_catalog.jsonb_typeof(coalesce(metadata_changes, '{}'::jsonb)) <> 'object' then
    raise exception 'Format de synchronisation BizGestion invalide.';
  end if;
  if (coalesce(metadata_changes, '{}'::jsonb) - array[
    'receiptSequence', 'paymentSequence', 'businessProfile'
  ]) <> '{}'::jsonb then
    raise exception 'Les métadonnées BizGestion contiennent une clé non autorisée.';
  end if;
  if exists (
    select 1 from pg_catalog.jsonb_object_keys(coalesce(record_changes, '{}'::jsonb)) as item(key)
    where item.key not in (
      'products', 'suppliers', 'purchases', 'sales', 'payments', 'refunds',
      'expenses', 'stocktakes', 'cashMovements'
    )
  ) or exists (
    select 1 from pg_catalog.jsonb_object_keys(coalesce(deleted_records, '{}'::jsonb)) as item(key)
    where item.key not in (
      'products', 'suppliers', 'purchases', 'sales', 'payments', 'refunds',
      'expenses', 'stocktakes', 'cashMovements'
    )
  ) then
    raise exception 'La synchronisation contient une collection inconnue.';
  end if;

  select state.source_revision into source_sync_revision
  from public.business_record_sync_state as state
  where state.business_id = target_business_id;
  if source_sync_revision is distinct from current_revision then
    perform public.refresh_business_records_from_snapshot(
      target_business_id, source_data, current_revision
    );
  end if;

  for collection_name in
    select pg_catalog.unnest(array[
      'products', 'suppliers', 'purchases', 'sales', 'payments', 'refunds',
      'expenses', 'stocktakes', 'cashMovements'
    ])
  loop
    if record_changes ? collection_name then
      if pg_catalog.jsonb_typeof(record_changes -> collection_name) <> 'array' then
        raise exception 'Liste de modifications invalide pour %.', collection_name;
      end if;
      if exists (
        select 1
        from pg_catalog.jsonb_array_elements(record_changes -> collection_name) as item(value)
        where pg_catalog.jsonb_typeof(item.value) <> 'object'
          or nullif(item.value ->> 'recordId', '') is null
      ) then
        raise exception 'Identifiant manquant dans les modifications de %.', collection_name;
      end if;
      if exists (
        select item.value ->> 'recordId'
        from pg_catalog.jsonb_array_elements(record_changes -> collection_name) as item(value)
        group by item.value ->> 'recordId'
        having count(*) > 1
      ) then
        raise exception 'Identifiant répété dans les modifications de %.', collection_name;
      end if;

      select coalesce(pg_catalog.min(records.position), 1)
        into current_min_position
      from public.business_records as records
      where records.business_id = target_business_id
        and records.collection = collection_name;

      with incoming as (
        select item.value, item.ordinality
        from pg_catalog.jsonb_array_elements(record_changes -> collection_name)
          with ordinality as item(value, ordinality)
      ), new_rows as (
        select incoming.value, incoming.ordinality,
          pg_catalog.row_number() over (order by incoming.ordinality) as new_order,
          pg_catalog.count(*) over () as new_count
        from incoming
        where not exists (
          select 1 from public.business_records as existing
          where existing.business_id = target_business_id
            and existing.collection = collection_name
            and existing.record_key = incoming.value ->> 'recordId'
        )
      )
      insert into public.business_records (
        business_id, collection, record_key, position, occurred_at, payload
      )
      select target_business_id, collection_name, value ->> 'recordId',
        current_min_position - new_count + new_order - 1,
        nullif(value ->> 'date', '')::timestamptz, value
      from new_rows
      on conflict (business_id, collection, record_key) do update
        set occurred_at = excluded.occurred_at,
            payload = excluded.payload;

      -- Existing keys are deliberately excluded from the insert above so new
      -- rows can receive positions at the start of the collection. They still
      -- need their payload refreshed when a product quantity or other field
      -- changes (the common case for stock replenishment).
      update public.business_records as records
      set occurred_at = nullif(incoming.value ->> 'date', '')::timestamptz,
          payload = incoming.value
      from pg_catalog.jsonb_array_elements(record_changes -> collection_name)
        as incoming(value)
      where records.business_id = target_business_id
        and records.collection = collection_name
        and records.record_key = incoming.value ->> 'recordId'
        and records.payload is distinct from incoming.value;
    end if;

    if deleted_records ? collection_name then
      if pg_catalog.jsonb_typeof(deleted_records -> collection_name) <> 'array'
         or exists (
           select 1
           from pg_catalog.jsonb_array_elements(deleted_records -> collection_name) as item(value)
           where pg_catalog.jsonb_typeof(item.value) <> 'string'
             or nullif(item.value #>> '{}', '') is null
         ) then
        raise exception 'Liste de suppressions invalide pour %.', collection_name;
      end if;
      delete from public.business_records as records
      using pg_catalog.jsonb_array_elements_text(deleted_records -> collection_name) as item(record_key)
      where records.business_id = target_business_id
        and records.collection = collection_name
        and records.record_key = item.record_key;
    end if;
  end loop;

  select coalesce(pg_catalog.jsonb_object_agg(rows.collection, rows.items), '{}'::jsonb)
    into record_collections
  from (
    select records.collection,
      pg_catalog.jsonb_agg(
        records.payload || pg_catalog.jsonb_build_object('recordId', records.record_key)
        order by records.position
      ) as items
    from public.business_records as records
    where records.business_id = target_business_id
    group by records.collection
  ) as rows;

  merged_data := (source_data - array[
    'products', 'suppliers', 'purchases', 'sales', 'payments', 'refunds',
    'expenses', 'stocktakes', 'cashMovements'
  ]) || record_collections || pg_catalog.jsonb_build_object(
    'products', coalesce(record_collections -> 'products', '[]'::jsonb),
    'suppliers', coalesce(record_collections -> 'suppliers', '[]'::jsonb),
    'purchases', coalesce(record_collections -> 'purchases', '[]'::jsonb),
    'sales', coalesce(record_collections -> 'sales', '[]'::jsonb),
    'payments', coalesce(record_collections -> 'payments', '[]'::jsonb),
    'refunds', coalesce(record_collections -> 'refunds', '[]'::jsonb),
    'expenses', coalesce(record_collections -> 'expenses', '[]'::jsonb),
    'stocktakes', coalesce(record_collections -> 'stocktakes', '[]'::jsonb),
    'cashMovements', coalesce(record_collections -> 'cashMovements', '[]'::jsonb)
  ) || coalesce(metadata_changes, '{}'::jsonb);

  saved_revision := public.save_business_snapshot(
    target_business_id, merged_data, expected_revision
  );
  insert into public.business_record_sync_state (business_id, source_revision)
  values (target_business_id, saved_revision)
  on conflict (business_id) do update
    set source_revision = excluded.source_revision,
        synced_at = now();
  return saved_revision;
end;
$$;

revoke all on function public.save_business_records_delta(uuid, jsonb, jsonb, jsonb, bigint) from public;
grant execute on function public.save_business_records_delta(uuid, jsonb, jsonb, jsonb, bigint) to authenticated;

-- Pagination de l’historique par reçu complet (les lignes d’un même reçu ne
-- sont jamais séparées entre deux pages). Les totaux restent calculés sur tout
-- l’historique côté serveur.
create or replace function public.load_business_sales_page(
  target_business_id uuid,
  page_size integer default 30,
  page_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  member_role text;
  safe_page_size integer := greatest(1, least(coalesce(page_size, 30), 100));
  safe_page_offset integer := greatest(0, coalesce(page_offset, 0));
  receipt_total bigint;
  received_total numeric;
  due_total numeric;
  page_rows jsonb;
begin
  select members.role into member_role
  from public.business_members as members
  where members.business_id = target_business_id
    and members.user_id = (select auth.uid());
  if member_role is null then
    raise exception 'Commerce introuvable ou accès refusé.';
  end if;

  select count(distinct records.payload ->> 'receiptNumber'),
         coalesce(sum((records.payload ->> 'received')::numeric), 0),
         coalesce(sum((records.payload ->> 'balance')::numeric), 0)
    into receipt_total, received_total, due_total
  from public.business_records as records
  where records.business_id = target_business_id
    and records.collection = 'sales';

  with receipt_pages as (
    select records.payload ->> 'receiptNumber' as receipt_number,
           min(records.position) as first_position
    from public.business_records as records
    where records.business_id = target_business_id
      and records.collection = 'sales'
    group by records.payload ->> 'receiptNumber'
    order by min(records.position)
    offset safe_page_offset limit safe_page_size
  )
  select coalesce(pg_catalog.jsonb_agg(
    (case when member_role = 'staff'
      then pg_catalog.jsonb_set(records.payload, '{product,purchasePrice}', '0'::jsonb, true)
      else records.payload
    end) || pg_catalog.jsonb_build_object('recordId', records.record_key)
    order by records.position
  ), '[]'::jsonb)
  into page_rows
  from public.business_records as records
  join receipt_pages as page
    on page.receipt_number = records.payload ->> 'receiptNumber'
  where records.business_id = target_business_id
    and records.collection = 'sales';

  return pg_catalog.jsonb_build_object(
    'sales', page_rows,
    'totalReceipts', receipt_total,
    'totalReceived', received_total,
    'totalDue', due_total,
    'offset', safe_page_offset,
    'pageSize', safe_page_size,
    'hasMore', safe_page_offset + safe_page_size < receipt_total
  );
end;
$$;

revoke all on function public.load_business_sales_page(uuid, integer, integer) from public;
grant execute on function public.load_business_sales_page(uuid, integer, integer) to authenticated;

-- Lecture par curseur des autres collections. Les employés ne peuvent lire que
-- les produits et ventes; les champs de coût restent masqués comme dans le snapshot.
create or replace function public.load_business_record_page(
  target_business_id uuid,
  target_collection text,
  page_size integer default 50,
  page_after_position bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  safe_page_size integer := greatest(1, least(coalesce(page_size, 50), 100));
  member_role text;
  source_data jsonb;
  source_revision bigint;
  synced_revision bigint;
  next_position bigint;
  page_has_more boolean;
  page_rows jsonb;
begin
  if target_collection is null or target_collection not in (
    'products', 'suppliers', 'purchases', 'sales', 'payments', 'refunds',
    'expenses', 'stocktakes', 'cashMovements'
  ) then
    raise exception 'Collection BizGestion inconnue.';
  end if;

  select data.revision, members.role
    into source_revision, member_role
  from public.business_data as data
  join public.business_members as members
    on members.business_id = data.business_id
  where data.business_id = target_business_id
    and members.user_id = (select auth.uid())
  for share of data;
  if not found then
    raise exception 'Commerce introuvable ou accès refusé.';
  end if;
  if member_role = 'staff' and target_collection not in ('products', 'sales') then
    raise exception 'Accès refusé à cette collection.';
  end if;

  select state.source_revision into synced_revision
  from public.business_record_sync_state as state
  where state.business_id = target_business_id;
  if synced_revision is distinct from source_revision then
    select data.data into source_data
    from public.business_data as data
    where data.business_id = target_business_id;
    perform public.refresh_business_records_from_snapshot(
      target_business_id, source_data, source_revision
    );
  end if;

  with candidates as materialized (
    select records.position, records.record_key, records.payload
    from public.business_records as records
    where records.business_id = target_business_id
      and records.collection = target_collection
      and (page_after_position is null or records.position > page_after_position)
    order by records.position
    limit safe_page_size + 1
  ), numbered as materialized (
    select candidates.position, candidates.record_key, candidates.payload,
      pg_catalog.row_number() over (order by candidates.position) as page_number
    from candidates
  ), visible as (
    select numbered.position, numbered.record_key,
      case
        when member_role = 'staff' and target_collection = 'products'
          then numbered.payload || pg_catalog.jsonb_build_object('recordId', numbered.record_key, 'purchasePrice', 0)
        when member_role = 'staff' and target_collection = 'sales'
          then pg_catalog.jsonb_set(numbered.payload, '{product,purchasePrice}', '0'::jsonb, true)
            || pg_catalog.jsonb_build_object('recordId', numbered.record_key)
        else numbered.payload || pg_catalog.jsonb_build_object('recordId', numbered.record_key)
      end as payload
    from numbered
    where numbered.page_number <= safe_page_size
  )
  select
    coalesce(pg_catalog.jsonb_agg(visible.payload order by visible.position), '[]'::jsonb),
    max(visible.position),
    coalesce((select count(*) > safe_page_size from candidates), false)
  into page_rows, next_position, page_has_more
  from visible;

  return pg_catalog.jsonb_build_object(
    'collection', target_collection,
    'records', page_rows,
    'nextCursor', next_position,
    'hasMore', page_has_more
  );
end;
$$;

revoke all on function public.load_business_record_page(uuid, text, integer, bigint) from public;
grant execute on function public.load_business_record_page(uuid, text, integer, bigint) to authenticated;

-- Repair existing normalized rows after deploying the corrected full-snapshot
-- refresh logic. This also makes already saved stock changes visible at once.
do $$
declare
  business_row record;
begin
  for business_row in
    select data.business_id, data.data, data.revision
    from public.business_data as data
  loop
    perform public.refresh_business_records_from_snapshot(
      business_row.business_id,
      business_row.data,
      business_row.revision
    );
  end loop;
end;
$$;
