-- Corrige la comparaison des recordId techniques ajoutés par la synchronisation.
-- À exécuter dans Supabase SQL Editor après supabase_business_data.sql.

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
