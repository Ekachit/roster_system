create extension if not exists citext with schema extensions;

create type public.staff_role as enum ('supervisor', 'employee');

create table public.staff (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  email extensions.citext not null unique,
  full_name text not null check (length(trim(full_name)) > 0),
  role public.staff_role not null default 'employee',
  is_active boolean not null default true,
  created_by uuid references public.staff(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint staff_email_normalised check (email::text = lower(trim(email::text)))
);

create table public.staff_private_notes (
  staff_id uuid primary key references public.staff(id) on delete cascade,
  note text,
  updated_at timestamptz not null default now()
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  name extensions.citext not null unique check (length(trim(name::text)) > 0),
  is_active boolean not null default true,
  default_start_time time,
  default_end_time time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint locations_default_time_pair check (
    (default_start_time is null and default_end_time is null)
    or (default_start_time is not null and default_end_time > default_start_time)
  )
);

create table public.activity_types (
  id uuid primary key default gen_random_uuid(),
  name extensions.citext not null unique check (length(trim(name::text)) > 0),
  is_active boolean not null default true,
  default_start_time time,
  default_end_time time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint activity_types_default_time_pair check (
    (default_start_time is null and default_end_time is null)
    or (default_start_time is not null and default_end_time > default_start_time)
  )
);

create table public.staff_locations (
  staff_id uuid not null references public.staff(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (staff_id, location_id)
);

create table public.staff_activity_types (
  staff_id uuid not null references public.staff(id) on delete cascade,
  activity_type_id uuid not null references public.activity_types(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (staff_id, activity_type_id)
);

create index staff_auth_user_id_idx on public.staff(auth_user_id);
create index staff_locations_location_idx on public.staff_locations(location_id);
create index staff_activity_types_activity_idx on public.staff_activity_types(activity_type_id);

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger staff_updated_at before update on public.staff
for each row execute function public.set_updated_at();
create trigger staff_notes_updated_at before update on public.staff_private_notes
for each row execute function public.set_updated_at();
create trigger locations_updated_at before update on public.locations
for each row execute function public.set_updated_at();
create trigger activity_types_updated_at before update on public.activity_types
for each row execute function public.set_updated_at();

create or replace function public.current_staff_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select s.id
  from public.staff s
  join auth.users u on u.id = s.auth_user_id
  where s.auth_user_id = auth.uid()
    and lower(trim(u.email)) = lower(trim(s.email::text))
    and s.is_active
$$;

create or replace function public.is_supervisor()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.staff s
    where s.id = public.current_staff_id()
      and s.role = 'supervisor'
  )
$$;

create or replace function public.current_access_profile()
returns table (
  id uuid,
  email text,
  full_name text,
  role public.staff_role,
  is_active boolean,
  email_matches boolean
)
language sql stable security definer set search_path = '' as $$
  select
    s.id,
    s.email::text,
    s.full_name,
    s.role,
    s.is_active,
    lower(trim(u.email)) = lower(trim(s.email::text)) as email_matches
  from public.staff s
  join auth.users u on u.id = s.auth_user_id
  where s.auth_user_id = auth.uid()
$$;

create or replace function public.link_approved_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.email is not null and new.email_confirmed_at is not null then
    update public.staff
    set auth_user_id = new.id
    where email = lower(trim(new.email))
      and (auth_user_id is null or auth_user_id = new.id);
  end if;
  return new;
end;
$$;

create trigger link_approved_auth_user_after_auth
after insert or update of email_confirmed_at, email on auth.users
for each row execute function public.link_approved_auth_user();

create or replace function public.protect_staff_invariants()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.auth_user_id is distinct from new.auth_user_id
     and pg_trigger_depth() <= 1
     and coalesce(current_setting('role', true), '') not in ('postgres', 'supabase_admin', 'supabase_auth_admin') then
    raise exception 'Auth linkage cannot be changed through this operation';
  end if;
  if old.role = 'supervisor' and old.is_active
     and (new.role <> 'supervisor' or not new.is_active)
     and not exists (
       select 1
       from public.staff s
       join auth.users u on u.id = s.auth_user_id
       where s.id <> old.id
         and s.role = 'supervisor'
         and s.is_active
         and lower(trim(u.email)) = lower(trim(s.email::text))
     ) then
    raise exception 'The last active supervisor cannot be demoted or deactivated';
  end if;
  return new;
end;
$$;

create trigger protect_staff_before_update before update on public.staff
for each row execute function public.protect_staff_invariants();

alter table public.staff enable row level security;
alter table public.staff_private_notes enable row level security;
alter table public.locations enable row level security;
alter table public.activity_types enable row level security;
alter table public.staff_locations enable row level security;
alter table public.staff_activity_types enable row level security;

create policy staff_own_select on public.staff for select to authenticated
using (id = public.current_staff_id());
create policy staff_supervisor_all on public.staff for all to authenticated
using (public.is_supervisor()) with check (public.is_supervisor());

create policy notes_supervisor_all on public.staff_private_notes for all to authenticated
using (public.is_supervisor()) with check (public.is_supervisor());

create policy locations_active_select on public.locations for select to authenticated
using (public.current_staff_id() is not null and (is_active or public.is_supervisor()));
create policy locations_supervisor_insert on public.locations for insert to authenticated
with check (public.is_supervisor());
create policy locations_supervisor_update on public.locations for update to authenticated
using (public.is_supervisor()) with check (public.is_supervisor());

create policy activities_active_select on public.activity_types for select to authenticated
using (public.current_staff_id() is not null and (is_active or public.is_supervisor()));
create policy activities_supervisor_insert on public.activity_types for insert to authenticated
with check (public.is_supervisor());
create policy activities_supervisor_update on public.activity_types for update to authenticated
using (public.is_supervisor()) with check (public.is_supervisor());

create policy staff_locations_own_select on public.staff_locations for select to authenticated
using (staff_id = public.current_staff_id());
create policy staff_locations_supervisor_all on public.staff_locations for all to authenticated
using (public.is_supervisor()) with check (public.is_supervisor());
create policy staff_activities_own_select on public.staff_activity_types for select to authenticated
using (staff_id = public.current_staff_id());
create policy staff_activities_supervisor_all on public.staff_activity_types for all to authenticated
using (public.is_supervisor()) with check (public.is_supervisor());

create view public.supervisor_staff_directory
with (security_invoker = true, security_barrier = true) as
select s.id, s.email::text as email, s.full_name, s.role, s.is_active,
       s.auth_user_id is not null as is_linked,
       n.note as supervisor_notes
from public.staff s
left join public.staff_private_notes n on n.staff_id = s.id
where public.is_supervisor();

create or replace function public.save_staff_configuration(
  p_staff_id uuid,
  p_email text,
  p_full_name text,
  p_role public.staff_role,
  p_supervisor_notes text,
  p_location_ids uuid[],
  p_activity_type_ids uuid[]
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_staff_id uuid;
  v_existing_email text;
  v_is_linked boolean;
begin
  -- Serializes every command that can change supervisor role or active status.
  -- A later statement in a waiting transaction sees the preceding commit.
  lock table public.staff in share row exclusive mode;
  if not public.is_supervisor() then raise exception 'Supervisor access required'; end if;
  if length(trim(p_email)) = 0 or length(trim(p_full_name)) = 0 then
    raise exception 'Name and email are required';
  end if;
  if p_staff_id is null then
    insert into public.staff(email, full_name, role, created_by)
    values (lower(trim(p_email)), trim(p_full_name), p_role, public.current_staff_id())
    returning id into v_staff_id;
  else
    select s.email::text, s.auth_user_id is not null
    into v_existing_email, v_is_linked
    from public.staff s
    where s.id = p_staff_id;
    if not found then raise exception 'Staff profile not found'; end if;
    if v_is_linked and lower(trim(v_existing_email)) <> lower(trim(p_email)) then
      raise exception 'A linked staff email cannot be changed; use the administrator unlink-and-relink procedure';
    end if;
    update public.staff
    set email = lower(trim(p_email)), full_name = trim(p_full_name), role = p_role
    where id = p_staff_id returning id into v_staff_id;
  end if;
  insert into public.staff_private_notes(staff_id, note)
  values (v_staff_id, nullif(trim(p_supervisor_notes), ''))
  on conflict (staff_id) do update set note = excluded.note;
  delete from public.staff_locations where staff_id = v_staff_id;
  insert into public.staff_locations(staff_id, location_id)
  select v_staff_id, unnest(coalesce(p_location_ids, array[]::uuid[]));
  delete from public.staff_activity_types where staff_id = v_staff_id;
  insert into public.staff_activity_types(staff_id, activity_type_id)
  select v_staff_id, unnest(coalesce(p_activity_type_ids, array[]::uuid[]));
  return v_staff_id;
end;
$$;

create or replace function public.set_staff_active(p_staff_id uuid, p_is_active boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  lock table public.staff in share row exclusive mode;
  if not public.is_supervisor() then raise exception 'Supervisor access required'; end if;
  update public.staff set is_active = p_is_active where id = p_staff_id;
  if not found then raise exception 'Staff profile not found'; end if;
end;
$$;

revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;
grant select on public.staff, public.staff_private_notes, public.locations, public.activity_types,
  public.staff_locations, public.staff_activity_types to authenticated;
grant insert, update on public.locations, public.activity_types,
  public.staff_locations, public.staff_activity_types to authenticated;
grant insert, update on public.staff_private_notes to authenticated;
grant select on public.supervisor_staff_directory to authenticated;

revoke all on function public.current_staff_id() from public, anon;
revoke all on function public.is_supervisor() from public, anon;
revoke all on function public.current_access_profile() from public, anon;
revoke all on function public.save_staff_configuration(uuid, text, text, public.staff_role, text, uuid[], uuid[]) from public, anon;
revoke all on function public.set_staff_active(uuid, boolean) from public, anon;
revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.link_approved_auth_user() from public, anon, authenticated;
revoke all on function public.protect_staff_invariants() from public, anon, authenticated;
grant execute on function public.current_staff_id() to authenticated;
grant execute on function public.is_supervisor() to authenticated;
grant execute on function public.current_access_profile() to authenticated;
grant execute on function public.save_staff_configuration(uuid, text, text, public.staff_role, text, uuid[], uuid[]) to authenticated;
grant execute on function public.set_staff_active(uuid, boolean) to authenticated;
