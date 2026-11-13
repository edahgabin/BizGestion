-- Stockage privé des photos produits BizGestion.
-- Les fichiers sont organisés sous : <business_id>/<nom de fichier>.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists "BizGestion members can view product images" on storage.objects;
create policy "BizGestion members can view product images"
on storage.objects for select to authenticated
using (
  bucket_id = 'product-images'
  and exists (
    select 1 from public.business_members as member
    where member.business_id::text = (storage.foldername(name))[1]
      and member.user_id = auth.uid()
  )
);

drop policy if exists "BizGestion members can add product images" on storage.objects;
drop policy if exists "BizGestion admins can add product images" on storage.objects;
create policy "BizGestion admins can add product images"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'product-images'
  and exists (
    select 1 from public.business_members as member
    where member.business_id::text = (storage.foldername(name))[1]
      and member.user_id = auth.uid()
      and member.role in ('owner', 'admin')
  )
);

drop policy if exists "BizGestion members can remove product images" on storage.objects;
drop policy if exists "BizGestion admins can remove product images" on storage.objects;
create policy "BizGestion admins can remove product images"
on storage.objects for delete to authenticated
using (
  bucket_id = 'product-images'
  and exists (
    select 1 from public.business_members as member
    where member.business_id::text = (storage.foldername(name))[1]
      and member.user_id = auth.uid()
      and member.role in ('owner', 'admin')
  )
);
