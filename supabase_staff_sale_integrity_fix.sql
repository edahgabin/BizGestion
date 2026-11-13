-- Corrige le déclencheur actif public.validate_staff_sale_integrity().
-- L'identifiant recordId est une métadonnée de synchronisation et ne fait pas
-- partie de l'identité du produit comparée à celui d'une vente.
-- Ce script conserve tout le reste de la fonction actuellement installée.

do $fix$
declare
  function_definition text;
  old_comparison constant text :=
    'product.value - ''quantity'' = (new_sale -> ''product'') - ''quantity''';
  new_comparison constant text :=
    '(product.value - ''quantity'' - ''recordId'') = ((new_sale -> ''product'') - ''quantity'' - ''recordId'')';
begin
  function_definition := pg_catalog.pg_get_functiondef(
    'public.validate_staff_sale_integrity()'::regprocedure
  );

  if pg_catalog.strpos(function_definition, new_comparison) > 0 then
    raise notice 'La comparaison de validate_staff_sale_integrity est déjà corrigée.';
    return;
  end if;

  if pg_catalog.strpos(function_definition, old_comparison) = 0 then
    raise exception 'Le code attendu dans validate_staff_sale_integrity est introuvable; aucune modification effectuée.';
  end if;

  function_definition := pg_catalog.replace(
    function_definition,
    old_comparison,
    new_comparison
  );
  execute function_definition;
  raise notice 'validate_staff_sale_integrity corrigée : recordId est ignoré dans la comparaison du produit.';
end;
$fix$;
