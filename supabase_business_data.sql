-- Première base multi-commerce pour BizGestion.
-- À exécuter dans l'éditeur SQL Supabase du projet.

create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.business_members (
  business_id uuid not null references public.businesses (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'staff')),
  created_at timestamptz not null default now(),
  primary key (business_id, user_id)
);

create table if not exists public.business_data (
  business_id uuid primary key references public.businesses (id) on delete cascade,
  data jsonb not null default '{"products":[],"purchases":[],"sales":[],"payments":[],"expenses":[],"stocktakes":[]}'::jsonb,
  revision bigint not null default 0,
  updated_at timestamptz not null default now()
);

create or replace function public.is_business_member(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.business_members
    where business_id = target_business_id and user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_business_member(uuid) from public;
grant execute on function public.is_business_member(uuid) to authenticated;

create or replace function public.create_bizgestion_business_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_business_id uuid;
  new_business_name text;
  invited_role text;
  invitation_id uuid;
begin
  -- Le script fonctionne aussi avant l'installation du module Équipe.
  -- Une fois la table créée, une invitation en attente est automatiquement utilisée.
  if pg_catalog.to_regclass('public.business_invitations') is not null then
    select invitations.business_id, invitations.role, invitations.id
      into new_business_id, invited_role, invitation_id
    from public.business_invitations as invitations
    where lower(invitations.invite_email) = lower(coalesce(new.email, ''))
      and invitations.accepted_at is null
    order by invitations.created_at
    limit 1
    for update;

    if invitation_id is not null then
      insert into public.business_members (business_id, user_id, role)
      values (new_business_id, new.id, invited_role);
      update public.business_invitations
        set accepted_at = now()
        where id = invitation_id;
      return new;
    end if;
  end if;

  new_business_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'business_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Mon commerce'
  );
  insert into public.businesses (name, owner_id)
  values (new_business_name, new.id)
  returning id into new_business_id;
  insert into public.business_members (business_id, user_id, role)
  values (new_business_id, new.id, 'owner');
  insert into public.business_data (business_id, data)
  values (
    new_business_id,
    jsonb_build_object(
      'businessProfile', jsonb_build_object(
        'countryCode', coalesce(nullif(upper(trim(new.raw_user_meta_data ->> 'country_code')), ''), 'BJ'),
        'currencyCode', coalesce(nullif(upper(trim(new.raw_user_meta_data ->> 'currency_code')), ''), 'XOF'),
        'languageCode', coalesce(nullif(new.raw_user_meta_data ->> 'language_code', ''), 'fr')
      )
    )
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_bizgestion on auth.users;
create trigger on_auth_user_created_bizgestion
  after insert on auth.users
  for each row execute procedure public.create_bizgestion_business_for_new_user();

-- Associe aussi un commerce aux utilisateurs déjà inscrits avant cette migration.
do $$
declare
  existing_user record;
  new_business_id uuid;
begin
  for existing_user in
    select users.id, users.email, users.raw_user_meta_data
    from auth.users as users
    where not exists (
      select 1 from public.business_members as members
      where members.user_id = users.id
    )
  loop
    insert into public.businesses (name, owner_id)
    values (
      coalesce(
        nullif(trim(existing_user.raw_user_meta_data ->> 'business_name'), ''),
        nullif(split_part(coalesce(existing_user.email, ''), '@', 1), ''),
        'Mon commerce'
      ),
      existing_user.id
    )
    returning id into new_business_id;
    insert into public.business_members (business_id, user_id, role)
    values (new_business_id, existing_user.id, 'owner');
    insert into public.business_data (business_id) values (new_business_id);
  end loop;
end;
$$;

create or replace function public.bump_business_data_revision()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.revision := old.revision + 1;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists bump_business_data_revision on public.business_data;
create trigger bump_business_data_revision
  before update on public.business_data
  for each row execute procedure public.bump_business_data_revision();

-- Les employés peuvent enregistrer des ventes, encaisser des crédits et
-- confirmer les retraits. Les autres changements restent réservés aux
-- propriétaires et administrateurs. Le contrôle est fait en base, pas seulement
-- dans l'interface Flutter.
create or replace function public.guard_business_data_by_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  member_role text;
  old_products jsonb;
  new_products jsonb;
  old_sales jsonb;
  new_sales jsonb;
  old_payments jsonb;
  new_payments jsonb;
  old_count integer;
  new_count integer;
  old_payment_count integer;
  new_payment_count integer;
  i integer;
  old_item jsonb;
  new_item jsonb;
  expected_stock numeric;
  rebuilt_products jsonb := '[]'::jsonb;
  received_delta numeric := 0;
  payment_delta numeric := 0;
  old_received numeric;
  new_received numeric;
  old_balance numeric;
  new_balance numeric;
  old_pickup text;
  new_pickup text;
begin
  select members.role into member_role
  from public.business_members as members
  where members.business_id = old.business_id
    and members.user_id = (select auth.uid());

  if member_role in ('owner', 'admin') then
    return new;
  end if;
  if member_role is distinct from 'staff' then
    raise exception 'Accès refusé pour modifier les données de ce commerce.';
  end if;

  old_products := coalesce(old.data -> 'products', '[]'::jsonb);
  new_products := coalesce(new.data -> 'products', '[]'::jsonb);
  old_sales := coalesce(old.data -> 'sales', '[]'::jsonb);
  new_sales := coalesce(new.data -> 'sales', '[]'::jsonb);
  old_payments := coalesce(old.data -> 'payments', '[]'::jsonb);
  new_payments := coalesce(new.data -> 'payments', '[]'::jsonb);

  if jsonb_typeof(old_products) <> 'array' or jsonb_typeof(new_products) <> 'array'
     or jsonb_typeof(old_sales) <> 'array' or jsonb_typeof(new_sales) <> 'array'
     or jsonb_typeof(old_payments) <> 'array' or jsonb_typeof(new_payments) <> 'array' then
    raise exception 'Format des données BizGestion invalide.';
  end if;

  old_count := jsonb_array_length(old_sales);
  new_count := jsonb_array_length(new_sales);
  old_payment_count := jsonb_array_length(old_payments);
  new_payment_count := jsonb_array_length(new_payments);
  if new_count < old_count or new_payment_count < old_payment_count then
    raise exception 'Un employé ne peut pas supprimer l’historique des ventes ou des paiements.';
  end if;

  if jsonb_array_length(old_products) <> jsonb_array_length(new_products) then
    raise exception 'Un employé ne peut pas ajouter ou supprimer des produits du catalogue.';
  end if;

  -- Le coût d'achat n'est pas transmis au compte Employé. On le restaure depuis
  -- la ligne serveur avant de vérifier puis d'enregistrer son changement.
  for i in 0 .. jsonb_array_length(old_products) - 1 loop
    old_item := old_products -> i;
    new_item := new_products -> i;
    if (old_item - 'quantity' - 'purchasePrice' - 'recordId') is distinct from (new_item - 'quantity' - 'purchasePrice' - 'recordId') then
      raise exception 'Les prix et les paramètres des produits sont réservés au propriétaire ou à un administrateur.';
    end if;
    new_item := jsonb_set(new_item, '{purchasePrice}', coalesce(old_item -> 'purchasePrice', '0'::jsonb), true);
    rebuilt_products := rebuilt_products || jsonb_build_array(new_item);
  end loop;
  new_products := rebuilt_products;

  -- Les coûts historiques cachés dans les reçus employés sont également restaurés.
  for i in 0 .. old_count - 1 loop
    old_item := old_sales -> i;
    new_sales := jsonb_set(
      new_sales,
      array[(new_count - old_count + i)::text, 'product', 'purchasePrice'],
      coalesce(old_item #> '{product,purchasePrice}', '0'::jsonb),
      true
    );
  end loop;
  if new_count > old_count then
    for i in 0 .. new_count - old_count - 1 loop
      select product.value -> 'purchasePrice' into old_item
      from jsonb_array_elements(new_products) as product(value)
      where product.value ->> 'name' = new_sales -> i -> 'product' ->> 'name'
        and product.value ->> 'category' = new_sales -> i -> 'product' ->> 'category'
      limit 1;
      new_sales := jsonb_set(new_sales, array[i::text, 'product', 'purchasePrice'], coalesce(old_item, '0'::jsonb), true);
    end loop;
  end if;

  -- Conserve les modules confidentiels côté serveur, même si l'Employé ne les reçoit pas.
  new.data := (old.data - 'products' - 'sales' - 'payments')
    || jsonb_build_object('products', new_products, 'sales', new_sales, 'payments', new_payments);

  -- L'application place les ventes et paiements récents au début des listes.
  -- Les anciennes entrées doivent donc rester exactement à la fin.
  for i in 0 .. old_count - 1 loop
    old_item := old_sales -> i;
    new_item := new_sales -> (new_count - old_count + i);
    if (old_item - array['received','balance','dueDate','pickupStatus','collectedAt','recordId'])
       is distinct from (new_item - array['received','balance','dueDate','pickupStatus','collectedAt','recordId']) then
      raise exception 'Un employé ne peut pas modifier une vente déjà enregistrée.';
    end if;

    old_received := coalesce((old_item ->> 'received')::numeric, 0);
    new_received := coalesce((new_item ->> 'received')::numeric, 0);
    old_balance := coalesce((old_item ->> 'balance')::numeric, 0);
    new_balance := coalesce((new_item ->> 'balance')::numeric, 0);
    if new_received < old_received or new_balance < 0
       or abs((new_received - old_received) - (old_balance - new_balance)) > 0.01
       or new_received > coalesce((new_item ->> 'total')::numeric, 0) + 0.01 then
      raise exception 'Le montant du paiement ne correspond pas au solde du reçu.';
    end if;
    if new_balance <= 0.01 and new_item -> 'dueDate' <> 'null'::jsonb then
      raise exception 'Un reçu payé ne peut pas conserver une échéance.';
    end if;
    if new_balance > 0.01 and new_item -> 'dueDate' is distinct from old_item -> 'dueDate' then
      raise exception 'Seul le paiement du reçu peut modifier son échéance.';
    end if;
    received_delta := received_delta + (new_received - old_received);

    old_pickup := coalesce(old_item ->> 'pickupStatus', 'Remis au client');
    new_pickup := coalesce(new_item ->> 'pickupStatus', 'Remis au client');
    if old_pickup is distinct from new_pickup then
      if old_pickup <> 'À retirer' or new_pickup <> 'Retiré'
         or new_item -> 'collectedAt' is null or new_item -> 'collectedAt' = 'null'::jsonb then
        raise exception 'Seul le retrait d’un colis en attente peut être confirmé.';
      end if;
    elsif new_item -> 'collectedAt' is distinct from old_item -> 'collectedAt' then
      raise exception 'La date de retrait ne peut changer qu’à la confirmation du colis.';
    end if;
  end loop;

  -- Chaque paiement déjà présent doit rester identique.
  for i in 0 .. old_payment_count - 1 loop
    if (old_payments -> i) - 'recordId' is distinct from (new_payments -> (new_payment_count - old_payment_count + i)) - 'recordId' then
      raise exception 'Un employé ne peut pas modifier un paiement déjà enregistré.';
    end if;
  end loop;

  -- Vérifie les nouveaux paiements et relie leur total aux soldes réellement réduits.
  if new_payment_count > old_payment_count then
    for i in 0 .. new_payment_count - old_payment_count - 1 loop
      if coalesce((new_payments -> i ->> 'amount')::numeric, 0) <= 0 then
        raise exception 'Le montant du paiement doit être supérieur à zéro.';
      end if;
      payment_delta := payment_delta + (new_payments -> i ->> 'amount')::numeric;
    end loop;
  end if;
  if abs(payment_delta - received_delta) > 0.01 then
    raise exception 'Les paiements ajoutés ne correspondent pas aux soldes mis à jour.';
  end if;

  -- Les nouveaux reçus sont ajoutés au début; leurs quantités sont déduites du stock.
  if new_count > old_count then
    for i in 0 .. new_count - old_count - 1 loop
      if coalesce((new_sales -> i ->> 'quantity')::numeric, 0) <= 0
         or coalesce((new_sales -> i ->> 'stockQuantity')::numeric, 0) <= 0
         or coalesce((new_sales -> i ->> 'unitPrice')::numeric, 0) < 0
         or coalesce((new_sales -> i ->> 'total')::numeric, 0) < 0
         or coalesce((new_sales -> i ->> 'received')::numeric, 0) < 0
         or coalesce((new_sales -> i ->> 'received')::numeric, 0) > coalesce((new_sales -> i ->> 'total')::numeric, 0) + 0.01
         or abs((new_sales -> i ->> 'total')::numeric -
                (new_sales -> i ->> 'quantity')::numeric * (new_sales -> i ->> 'unitPrice')::numeric) > 0.01
         or abs((new_sales -> i ->> 'balance')::numeric -
                ((new_sales -> i ->> 'total')::numeric - (new_sales -> i ->> 'received')::numeric)) > 0.01 then
        raise exception 'Les montants d’une nouvelle vente sont incohérents.';
      end if;
      if not exists (
        select 1 from jsonb_array_elements(new_products) as product(value)
        where (product.value - 'quantity' - 'recordId') =
              ((new_sales -> i -> 'product') - 'quantity' - 'recordId')
          and product.value ->> 'name' = new_sales -> i -> 'product' ->> 'name'
          and product.value ->> 'category' = new_sales -> i -> 'product' ->> 'category'
      ) then
        raise exception 'Une vente doit porter sur un produit actuel du commerce.';
      end if;
    end loop;
  end if;

  for i in 0 .. jsonb_array_length(old_products) - 1 loop
    old_item := old_products -> i;
    new_item := new_products -> i;
    expected_stock := 0;
    if new_count > old_count then
      select coalesce(sum((new_sales -> s.ordinality::integer ->> 'stockQuantity')::numeric), 0)
        into expected_stock
      from generate_series(0, new_count - old_count - 1) as s(ordinality)
      where new_sales -> s.ordinality::integer -> 'product' ->> 'name' = old_item ->> 'name'
        and new_sales -> s.ordinality::integer -> 'product' ->> 'category' = old_item ->> 'category';
    end if;
    if coalesce((new_item ->> 'quantity')::numeric, -1) < -0.01
       or abs(((old_item ->> 'quantity')::numeric - (new_item ->> 'quantity')::numeric) - expected_stock) > 0.01 then
      raise exception 'Le stock peut uniquement diminuer en fonction des ventes enregistrées.';
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists guard_business_data_by_role on public.business_data;
create trigger guard_business_data_by_role
  before update on public.business_data
  for each row execute procedure public.guard_business_data_by_role();

-- Les clients lisent les données par cette fonction. Le compte Employé reçoit
-- uniquement les informations nécessaires aux ventes et aux paiements clients.
create or replace function public.load_business_snapshot(target_business_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored_data jsonb;
  visible_data jsonb;
  stored_revision bigint;
  member_role text;
begin
  select data.data, data.revision, members.role
    into stored_data, stored_revision, member_role
  from public.business_data as data
  join public.business_members as members on members.business_id = data.business_id
  where data.business_id = target_business_id
    and members.user_id = (select auth.uid());
  if not found then
    raise exception 'Commerce introuvable ou accès refusé.';
  end if;

  if member_role in ('owner', 'admin') then
    visible_data := stored_data;
  else
    visible_data := jsonb_build_object(
      'receiptSequence', coalesce(stored_data -> 'receiptSequence', '0'::jsonb),
      'paymentSequence', coalesce(stored_data -> 'paymentSequence', '0'::jsonb),
      'businessProfile', coalesce(stored_data -> 'businessProfile', '{}'::jsonb),
      'products', coalesce((
        select jsonb_agg(product.value || jsonb_build_object('purchasePrice', 0) order by product.ordinality)
        from jsonb_array_elements(coalesce(stored_data -> 'products', '[]'::jsonb)) with ordinality as product(value, ordinality)
      ), '[]'::jsonb),
      'sales', coalesce((
        select jsonb_agg(jsonb_set(sale.value, '{product,purchasePrice}', '0'::jsonb, true) order by sale.ordinality)
        from jsonb_array_elements(coalesce(stored_data -> 'sales', '[]'::jsonb)) with ordinality as sale(value, ordinality)
      ), '[]'::jsonb),
      'payments', coalesce(stored_data -> 'payments', '[]'::jsonb),
      'purchases', '[]'::jsonb,
      'expenses', '[]'::jsonb,
      'refunds', '[]'::jsonb,
      'stocktakes', '[]'::jsonb,
      'cashMovements', '[]'::jsonb
    );
  end if;
  return jsonb_build_object('data', visible_data, 'revision', stored_revision);
end;
$$;

create or replace function public.save_business_snapshot(
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
begin
  if not public.is_business_member(target_business_id) then
    raise exception 'Commerce introuvable ou accès refusé.';
  end if;
  update public.business_data
    set data = new_data
    where business_id = target_business_id and revision = expected_revision
    returning revision into saved_revision;
  if saved_revision is null then
    raise exception 'Conflit de synchronisation : recharge BizGestion avant de réessayer.';
  end if;
  return saved_revision;
end;
$$;

revoke all on function public.load_business_snapshot(uuid) from public;
revoke all on function public.save_business_snapshot(uuid, jsonb, bigint) from public;
grant execute on function public.load_business_snapshot(uuid) to authenticated;
grant execute on function public.save_business_snapshot(uuid, jsonb, bigint) to authenticated;

alter table public.businesses enable row level security;
alter table public.business_members enable row level security;
alter table public.business_data enable row level security;

drop policy if exists "Members can read their businesses" on public.businesses;
create policy "Members can read their businesses"
  on public.businesses for select to authenticated
  using (public.is_business_member(id));

drop policy if exists "Owners and admins can update their businesses" on public.businesses;
create policy "Owners and admins can update their businesses"
  on public.businesses for update to authenticated
  using (
    exists (
      select 1 from public.business_members
      where business_id = id and user_id = (select auth.uid())
        and role in ('owner', 'admin')
    )
  )
  with check (
    exists (
      select 1 from public.business_members
      where business_id = id and user_id = (select auth.uid())
        and role in ('owner', 'admin')
    )
  );

drop policy if exists "Members can read their memberships" on public.business_members;
create policy "Members can read their memberships"
  on public.business_members for select to authenticated
  using (public.is_business_member(business_id));

drop policy if exists "Members can read their commerce data" on public.business_data;
create policy "Members can read their commerce data"
  on public.business_data for select to authenticated
  using (public.is_business_member(business_id));

drop policy if exists "Members can update their commerce data" on public.business_data;
create policy "Members can update their commerce data"
  on public.business_data for update to authenticated
  using (public.is_business_member(business_id))
  with check (public.is_business_member(business_id));

grant usage on schema public to authenticated;
grant select on public.businesses to authenticated;
grant update (name) on public.businesses to authenticated;
grant select on public.business_members to authenticated;
revoke all on public.business_data from anon, authenticated;

-- Journal d’activité du commerce : sections modifiées et auteur, sans montants
-- ni contenu des enregistrements. Seuls owner/admin peuvent le consulter.
create table if not exists public.business_activity_log (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  sections text[] not null default '{}',
  occurred_at timestamptz not null default now()
);

alter table public.business_activity_log enable row level security;
revoke all on public.business_activity_log from anon, authenticated;

create or replace function public.log_business_data_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_sections text[];
  section_name text;
begin
  foreach section_name in array array[
    'products', 'sales', 'payments', 'customers', 'purchases', 'expenses',
    'refunds', 'stocktakes', 'cashMovements'
  ] loop
    if coalesce(old.data -> section_name, 'null'::jsonb)
       is distinct from coalesce(new.data -> section_name, 'null'::jsonb) then
      changed_sections := array_append(changed_sections, section_name);
    end if;
  end loop;

  if coalesce(array_length(changed_sections, 1), 0) > 0 then
    insert into public.business_activity_log (business_id, actor_id, sections)
    values (new.business_id, (select auth.uid()), changed_sections);
  end if;
  return new;
end;
$$;

drop trigger if exists log_business_data_activity on public.business_data;
create trigger log_business_data_activity
  after update on public.business_data
  for each row execute procedure public.log_business_data_activity();

create or replace function public.list_business_activity(
  target_business_id uuid,
  max_rows integer default 40
)
returns table (
  id uuid,
  actor_email text,
  role_label text,
  sections text[],
  occurred_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.business_members as member
    where member.business_id = target_business_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin')
  ) then
    raise exception 'Accès refusé au journal d’activité.';
  end if;

  return query
    select activity.id,
      coalesce(account.email::text, 'Compte inconnu'),
      case member.role
        when 'owner' then 'Propriétaire'
        when 'admin' then 'Administrateur'
        else 'Membre'
      end,
      activity.sections,
      activity.occurred_at
    from public.business_activity_log as activity
    left join auth.users as account on account.id = activity.actor_id
    left join public.business_members as member
      on member.business_id = activity.business_id and member.user_id = activity.actor_id
    where activity.business_id = target_business_id
    order by activity.occurred_at desc
    limit least(greatest(coalesce(max_rows, 40), 1), 100);
end;
$$;

revoke all on function public.list_business_activity(uuid, integer) from public;
grant execute on function public.list_business_activity(uuid, integer) to authenticated;
