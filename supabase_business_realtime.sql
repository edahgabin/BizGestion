-- Active les alertes de synchronisation entre appareils sans diffuser le contenu
-- commercial. Cette table ne contient que la revision, l'auteur et l'heure.

create table if not exists public.business_data_updates (
  business_id uuid primary key references public.businesses (id) on delete cascade,
  revision bigint not null,
  actor_id uuid references auth.users (id) on delete set null,
  occurred_at timestamptz not null default now()
);

insert into public.business_data_updates (business_id, revision, occurred_at)
select business_id, revision, updated_at
from public.business_data
on conflict (business_id) do nothing;

alter table public.business_data_updates enable row level security;
revoke all on public.business_data_updates from anon, authenticated;

drop policy if exists "Members can read commerce update signals" on public.business_data_updates;
create policy "Members can read commerce update signals"
  on public.business_data_updates for select to authenticated
  using (public.is_business_member(business_id));

grant select on public.business_data_updates to authenticated;

create or replace function public.publish_business_data_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.business_data_updates (business_id, revision, actor_id, occurred_at)
  values (new.business_id, new.revision, (select auth.uid()), now())
  on conflict (business_id) do update
    set revision = excluded.revision,
        actor_id = excluded.actor_id,
        occurred_at = excluded.occurred_at;
  return new;
end;
$$;

drop trigger if exists publish_business_data_update on public.business_data;
create trigger publish_business_data_update
  after update on public.business_data
  for each row execute procedure public.publish_business_data_update();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'business_data_updates'
  ) then
    alter publication supabase_realtime add table public.business_data_updates;
  end if;
end;
$$;
