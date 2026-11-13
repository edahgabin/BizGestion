-- Gestion initiale de l’équipe BizGestion.
-- Exécuter ce fichier dans Supabase > SQL Editor, après supabase_business_data.sql.

create table if not exists public.business_invitations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  invite_email text not null,
  role text not null check (role in ('admin', 'staff')),
  invited_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  accepted_at timestamptz
);

create unique index if not exists business_invitations_pending_email_key
  on public.business_invitations (business_id, lower(invite_email))
  where accepted_at is null;

alter table public.business_invitations enable row level security;
revoke all on table public.business_invitations from anon, authenticated;

drop function if exists public.create_business_invitation(uuid, text, text);
create function public.create_business_invitation(
  target_business_id uuid,
  invite_email text,
  invite_role text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text := lower(trim(invite_email));
  existing_user_id uuid;
  existing_email_confirmed_at timestamptz;
  selected_plan text;
  member_limit integer;
  reserved_seats integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Connexion requise.';
  end if;
  if invite_role not in ('admin', 'staff') then
    raise exception 'Rôle d’invitation invalide.';
  end if;
  if normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Adresse e-mail invalide.';
  end if;
  if not exists (
    select 1 from public.business_members
    where business_id = target_business_id
      and user_id = (select auth.uid())
      and role in ('owner', 'admin')
  ) then
    raise exception 'Seuls le propriétaire et les administrateurs peuvent inviter des membres.';
  end if;
  select users.id, users.email_confirmed_at
    into existing_user_id, existing_email_confirmed_at
  from auth.users as users
  where lower(users.email) = normalized_email
  order by users.created_at desc
  limit 1;

  if existing_user_id is not null then
    if exists (
      select 1 from public.business_members as members
      where members.business_id = target_business_id
        and members.user_id = existing_user_id
    ) then
      raise exception 'Cette personne est déjà membre de ce commerce.';
    end if;

    delete from public.business_invitations
    where business_id = target_business_id
      and lower(business_invitations.invite_email) = normalized_email
      and accepted_at is null;

    insert into public.business_members (business_id, user_id, role)
    values (target_business_id, existing_user_id, invite_role);

    return case
      when existing_email_confirmed_at is null then 'account_waiting_confirmation'
      else 'member_added'
    end;
  end if;

  select plan_code into selected_plan
  from public.business_subscriptions
  where business_id = target_business_id;

  if selected_plan is null then
    raise exception 'Abonnement BizGestion introuvable. Exécute le script des abonnements dans Supabase.';
  end if;

  member_limit := case selected_plan
    when 'trial' then 5
    when 'decouverte' then 5
    when 'commerce' then 10
    when 'entreprise' then 50
    else 0
  end;

  select
    (select count(*) from public.business_members as members
     where members.business_id = target_business_id)
    +
    (select count(*) from public.business_invitations as invitations
     where invitations.business_id = target_business_id
       and invitations.accepted_at is null
       and lower(invitations.invite_email) <> normalized_email)
    into reserved_seats;

  if reserved_seats >= member_limit then
    raise exception 'Limite atteinte : ce forfait accepte % membres, invitations en attente comprises.', member_limit;
  end if;

  delete from public.business_invitations
  where business_id = target_business_id
    and lower(business_invitations.invite_email) = normalized_email
    and accepted_at is null;

  insert into public.business_invitations (business_id, invite_email, role, invited_by)
  values (target_business_id, normalized_email, invite_role, (select auth.uid()));
  return 'invitation_pending';
end;
$$;

create or replace function public.list_business_access(target_business_id uuid)
returns table(email text, role text, status text, created_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.business_members as current_member
    where current_member.business_id = target_business_id
      and current_member.user_id = (select auth.uid())
      and current_member.role in ('owner', 'admin')
  ) then
    raise exception 'Accès réservé au propriétaire et aux administrateurs.';
  end if;

  return query
    select users.email::text,
      members.role,
      case when users.email_confirmed_at is null
        then 'Compte en attente de confirmation'::text
        else 'Membre'::text
      end,
      members.created_at
    from public.business_members as members
    join auth.users as users on users.id = members.user_id
    where members.business_id = target_business_id
    union all
    select invitations.invite_email, invitations.role, 'Invitation en attente'::text, invitations.created_at
    from public.business_invitations as invitations
    where invitations.business_id = target_business_id and invitations.accepted_at is null
    order by 4 desc;
end;
$$;

create or replace function public.revoke_business_access(
  target_business_id uuid,
  target_email text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role text;
  target_role text;
  target_user_id uuid;
  normalized_email text := lower(trim(target_email));
  pending_role text;
begin
  select members.role into actor_role
  from public.business_members as members
  where members.business_id = target_business_id
    and members.user_id = (select auth.uid());

  if actor_role is null or actor_role not in ('owner', 'admin') then
    raise exception 'Seuls le propriétaire et les administrateurs peuvent retirer un accès.';
  end if;
  if normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Adresse e-mail invalide.';
  end if;

  select members.user_id, members.role
    into target_user_id, target_role
  from public.business_members as members
  join auth.users as users on users.id = members.user_id
  where members.business_id = target_business_id
    and lower(users.email) = normalized_email
  limit 1;

  if target_user_id is not null then
    if target_user_id = (select auth.uid()) then
      raise exception 'Tu ne peux pas retirer ton propre accès ici.';
    end if;
    if target_role = 'owner' then
      raise exception 'Le compte propriétaire ne peut pas être retiré.';
    end if;
    if actor_role = 'admin' and target_role <> 'staff' then
      raise exception 'Un administrateur peut retirer uniquement l’accès d’un employé.';
    end if;

    delete from public.business_members
    where business_id = target_business_id and user_id = target_user_id;
    delete from public.business_invitations
    where business_id = target_business_id
      and lower(invite_email) = normalized_email
      and accepted_at is null;
    return;
  end if;

  select invitations.role into pending_role
  from public.business_invitations as invitations
  where invitations.business_id = target_business_id
    and lower(invitations.invite_email) = normalized_email
    and invitations.accepted_at is null
  order by invitations.created_at desc
  limit 1;
  if pending_role is null then
    raise exception 'Membre ou invitation introuvable.';
  end if;
  if actor_role = 'admin' and pending_role <> 'staff' then
    raise exception 'Un administrateur peut annuler uniquement une invitation d’employé.';
  end if;

  delete from public.business_invitations
  where business_id = target_business_id
    and lower(invite_email) = normalized_email
    and accepted_at is null;
end;
$$;

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

-- Keep the signup hook present when this team migration is applied on its own.
-- New invited users are attached by the invitation-aware trigger above.
drop trigger if exists on_auth_user_created_bizgestion on auth.users;
create trigger on_auth_user_created_bizgestion
  after insert on auth.users
  for each row execute procedure public.create_bizgestion_business_for_new_user();

revoke all on function public.create_business_invitation(uuid, text, text) from public, anon;
grant execute on function public.create_business_invitation(uuid, text, text) to authenticated;
grant execute on function public.list_business_access(uuid) to authenticated;
revoke all on function public.revoke_business_access(uuid, text) from public, anon;
grant execute on function public.revoke_business_access(uuid, text) to authenticated;
