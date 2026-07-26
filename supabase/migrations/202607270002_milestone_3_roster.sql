create type public.shift_status as enum ('DRAFT', 'PUBLISHED', 'CANCELLED');

create table public.shifts (
  id uuid primary key default gen_random_uuid(),
  local_date date not null,
  start_time time not null,
  end_time time not null,
  location_id uuid not null references public.locations(id) on delete restrict,
  activity_type_id uuid not null references public.activity_types(id) on delete restrict,
  required_staff_count integer not null default 1 check (required_staff_count between 1 and 100),
  notes text,
  status public.shift_status not null default 'DRAFT',
  created_by uuid not null references public.staff(id) on delete restrict,
  updated_by uuid not null references public.staff(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz,
  cancelled_at timestamptz,
  constraint shift_time_order check (end_time > start_time),
  constraint shift_status_metadata check (
    (status = 'DRAFT' and cancelled_at is null)
    or (status = 'PUBLISHED' and published_at is not null and cancelled_at is null)
    or (status = 'CANCELLED' and cancelled_at is not null)
  )
);

create table public.shift_assignments (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null references public.shifts(id) on delete restrict,
  staff_id uuid not null references public.staff(id) on delete restrict,
  assigned_by uuid not null references public.staff(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  override_confirmed boolean not null default false,
  override_reason text,
  override_conflicts jsonb not null default '[]'::jsonb,
  removed_at timestamptz,
  removed_by uuid references public.staff(id) on delete restrict,
  removal_reason text,
  replaced_by_assignment_id uuid references public.shift_assignments(id) on delete restrict,
  constraint assignment_override_reason check (
    (not override_confirmed and override_reason is null and override_conflicts = '[]'::jsonb)
    or (override_confirmed and length(trim(override_reason)) > 0 and jsonb_array_length(override_conflicts) > 0)
  ),
  constraint assignment_removal_shape check (
    (removed_at is null and removed_by is null and removal_reason is null)
    or (removed_at is not null and removed_by is not null and length(trim(removal_reason)) > 0)
  )
);

create unique index shift_assignments_one_active_idx
  on public.shift_assignments(shift_id, staff_id) where removed_at is null;
create index shifts_week_idx on public.shifts(local_date, start_time);
create index shifts_location_idx on public.shifts(location_id, local_date);
create index shifts_activity_idx on public.shifts(activity_type_id, local_date);
create index assignments_staff_active_idx on public.shift_assignments(staff_id) where removed_at is null;
create index assignments_shift_active_idx on public.shift_assignments(shift_id) where removed_at is null;

create table public.roster_audit (
  id bigint generated always as identity primary key,
  actor_staff_id uuid not null references public.staff(id) on delete restrict,
  action text not null,
  shift_id uuid references public.shifts(id) on delete restrict,
  assignment_id uuid references public.shift_assignments(id) on delete restrict,
  subject_staff_id uuid references public.staff(id) on delete restrict,
  reason text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index roster_audit_shift_idx on public.roster_audit(shift_id, created_at);
create trigger shifts_updated_at before update on public.shifts
for each row execute function public.set_updated_at();

alter table public.shifts enable row level security;
alter table public.shift_assignments enable row level security;
alter table public.roster_audit enable row level security;

create policy shifts_supervisor_select on public.shifts for select to authenticated
using (public.is_supervisor());
create policy assignments_supervisor_select on public.shift_assignments for select to authenticated
using (public.is_supervisor());
create or replace function public.is_shift_published(p_shift_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.shifts where id=p_shift_id and status='PUBLISHED')
$$;
create policy assignments_employee_published_own on public.shift_assignments for select to authenticated
using (
  staff_id = public.current_staff_id()
  and removed_at is null
  and public.is_shift_published(shift_id)
);
create policy audit_supervisor_select on public.roster_audit for select to authenticated
using (public.is_supervisor());

create or replace function public.require_supervisor()
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_actor uuid := public.current_staff_id();
begin
  if v_actor is null or not public.is_supervisor() then
    raise exception 'Supervisor access required' using errcode = '42501';
  end if;
  return v_actor;
end;
$$;

create or replace function public.assignment_conflicts(p_shift_id uuid, p_staff_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_shift public.shifts%rowtype;
  v_staff public.staff%rowtype;
  v_conflicts jsonb := '[]'::jsonb;
  v_weekday integer;
  v_recurring_covers boolean;
  v_recurring_overlaps boolean;
  v_available_exception_covers boolean;
  v_unavailable_overlaps boolean;
begin
  perform public.require_supervisor();
  select * into v_shift from public.shifts where id = p_shift_id;
  if not found then raise exception 'Shift not found'; end if;
  if v_shift.end_time <= v_shift.start_time then
    return jsonb_build_array(jsonb_build_object('code','INVALID_SHIFT_TIME','message','Shift end time must be later than start time.','overridable',false));
  end if;
  if v_shift.status = 'CANCELLED' then
    return jsonb_build_array(jsonb_build_object('code','CANCELLED_SHIFT','message','Cancelled shifts cannot receive assignments.','overridable',false));
  end if;
  select * into v_staff from public.staff where id = p_staff_id;
  if not found then raise exception 'Employee not found'; end if;

  if not v_staff.is_active or v_staff.role <> 'employee' then
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('code','INACTIVE_EMPLOYEE','message','Employee is inactive or is not an employee.','overridable',false));
  end if;
  if not exists (select 1 from public.staff_locations where staff_id = p_staff_id and location_id = v_shift.location_id) then
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('code','LOCATION_NOT_ELIGIBLE','message','Employee is not eligible for this location.','overridable',true));
  end if;
  if not exists (select 1 from public.staff_activity_types where staff_id = p_staff_id and activity_type_id = v_shift.activity_type_id) then
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('code','ACTIVITY_NOT_ELIGIBLE','message','Employee is not eligible for this activity.','overridable',true));
  end if;
  if exists (
    select 1 from public.shift_assignments a
    where a.shift_id = p_shift_id and a.staff_id = p_staff_id and a.removed_at is null
  ) then
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('code','DUPLICATE_ASSIGNMENT','message','Employee is already assigned to this shift.','overridable',false));
  end if;
  if exists (
    select 1 from public.shift_assignments a
    join public.shifts s on s.id = a.shift_id
    where a.staff_id = p_staff_id and a.removed_at is null and a.shift_id <> p_shift_id
      and s.status <> 'CANCELLED' and s.local_date = v_shift.local_date
      and s.start_time < v_shift.end_time and v_shift.start_time < s.end_time
  ) then
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('code','OVERLAPPING_ASSIGNMENT','message','Employee has another active assignment at this time.','overridable',false));
  end if;

  v_weekday := extract(isodow from v_shift.local_date);
  select
    coalesce(bool_or(r.start_time <= v_shift.start_time and r.end_time >= v_shift.end_time), false),
    coalesce(bool_or(r.start_time < v_shift.end_time and v_shift.start_time < r.end_time), false)
  into v_recurring_covers, v_recurring_overlaps
  from public.recurring_availability r
  where r.staff_id = p_staff_id and r.weekday = v_weekday
    and r.effective_start_date <= v_shift.local_date
    and (r.effective_end_date is null or r.effective_end_date >= v_shift.local_date);

  select
    coalesce(bool_or(not e.is_full_day and e.kind = 'available' and e.start_time <= v_shift.start_time and e.end_time >= v_shift.end_time), false),
    coalesce(bool_or(e.kind = 'unavailable' and (e.is_full_day or (e.start_time < v_shift.end_time and v_shift.start_time < e.end_time))), false)
  into v_available_exception_covers, v_unavailable_overlaps
  from public.availability_exceptions e
  where e.staff_id = p_staff_id and e.local_date = v_shift.local_date;

  if v_unavailable_overlaps then
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('code','DATE_SPECIFIC_UNAVAILABLE','message','A date-specific exception makes the employee unavailable.','overridable',true));
  elsif not (v_recurring_covers or v_available_exception_covers) then
    if v_recurring_overlaps then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('code','PARTIALLY_AVAILABLE','message','Availability covers only part of the shift.','overridable',true));
    else
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object('code','OUTSIDE_RECURRING_AVAILABILITY','message','Recurring availability does not cover this shift.','overridable',true));
    end if;
  end if;
  return v_conflicts;
end;
$$;

create or replace function public.shift_candidates(p_shift_id uuid)
returns table (
  staff_id uuid, full_name text, conflicts jsonb, fully_available boolean,
  eligible boolean, assignable_without_override boolean
) language sql stable security definer set search_path = '' as $$
  select s.id, s.full_name, c.value,
    not exists (select 1 from jsonb_array_elements(c.value) x where x->>'code' in ('OUTSIDE_RECURRING_AVAILABILITY','DATE_SPECIFIC_UNAVAILABLE','PARTIALLY_AVAILABLE','INACTIVE_EMPLOYEE')),
    not exists (select 1 from jsonb_array_elements(c.value) x where x->>'code' in ('INACTIVE_EMPLOYEE','LOCATION_NOT_ELIGIBLE','ACTIVITY_NOT_ELIGIBLE')),
    jsonb_array_length(c.value) = 0
  from public.staff s
  cross join lateral (select public.assignment_conflicts(p_shift_id, s.id) value) c
  where s.role = 'employee'
  order by jsonb_array_length(c.value), s.full_name
$$;

create or replace function public.save_shift(
  p_shift_id uuid, p_local_date date, p_start_time time, p_end_time time,
  p_location_id uuid, p_activity_type_id uuid, p_required_staff_count integer, p_notes text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := public.require_supervisor(); v_id uuid;
begin
  if p_local_date is null or p_start_time is null or p_end_time is null or p_end_time <= p_start_time then
    raise exception 'Invalid shift time';
  end if;
  if p_required_staff_count is null or p_required_staff_count < 1 then raise exception 'Required staff count must be at least 1'; end if;
  if not exists (select 1 from public.locations where id = p_location_id and is_active) then raise exception 'Active location required'; end if;
  if not exists (select 1 from public.activity_types where id = p_activity_type_id and is_active) then raise exception 'Active activity type required'; end if;
  if p_shift_id is null then
    insert into public.shifts(local_date,start_time,end_time,location_id,activity_type_id,required_staff_count,notes,created_by,updated_by)
    values(p_local_date,p_start_time,p_end_time,p_location_id,p_activity_type_id,p_required_staff_count,nullif(trim(p_notes),''),v_actor,v_actor)
    returning id into v_id;
    insert into public.roster_audit(actor_staff_id,action,shift_id) values(v_actor,'SHIFT_CREATED',v_id);
  else
    update public.shifts set local_date=p_local_date,start_time=p_start_time,end_time=p_end_time,
      location_id=p_location_id,activity_type_id=p_activity_type_id,required_staff_count=p_required_staff_count,
      notes=nullif(trim(p_notes),''),updated_by=v_actor
    where id=p_shift_id and status='DRAFT' returning id into v_id;
    if v_id is null then raise exception 'Only draft shifts can be edited'; end if;
    if exists (
      select 1 from public.shift_assignments a join public.shifts other on other.id=a.shift_id
      join public.shift_assignments changed on changed.staff_id=a.staff_id
      where changed.shift_id=v_id and changed.removed_at is null and a.removed_at is null
        and a.shift_id<>v_id and other.status<>'CANCELLED' and other.local_date=p_local_date
        and other.start_time<p_end_time and p_start_time<other.end_time
    ) then raise exception 'Edit would create overlapping active assignments'; end if;
    insert into public.roster_audit(actor_staff_id,action,shift_id) values(v_actor,'SHIFT_EDITED',v_id);
  end if;
  return v_id;
end;
$$;

create or replace function public.copy_shift(p_shift_id uuid, p_local_date date)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := public.require_supervisor(); v_source public.shifts%rowtype; v_id uuid;
begin
  select * into v_source from public.shifts where id=p_shift_id;
  if not found then raise exception 'Shift not found'; end if;
  insert into public.shifts(local_date,start_time,end_time,location_id,activity_type_id,required_staff_count,notes,created_by,updated_by)
  values(p_local_date,v_source.start_time,v_source.end_time,v_source.location_id,v_source.activity_type_id,v_source.required_staff_count,v_source.notes,v_actor,v_actor)
  returning id into v_id;
  insert into public.roster_audit(actor_staff_id,action,shift_id,details) values(v_actor,'SHIFT_COPIED',v_id,jsonb_build_object('source_shift_id',p_shift_id));
  return v_id;
end;
$$;

create or replace function public.set_shift_status(p_shift_id uuid, p_status public.shift_status, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := public.require_supervisor(); v_current public.shift_status;
begin
  select status into v_current from public.shifts where id=p_shift_id for update;
  if not found then raise exception 'Shift not found'; end if;
  if p_status='PUBLISHED' and v_current<>'DRAFT' then raise exception 'Only draft shifts can be published'; end if;
  if p_status='DRAFT' and v_current<>'PUBLISHED' then raise exception 'Only published shifts can be unpublished'; end if;
  if p_status='CANCELLED' and v_current='CANCELLED' then raise exception 'Shift is already cancelled'; end if;
  if p_status in ('DRAFT','CANCELLED') and length(trim(coalesce(p_reason,'')))=0 then raise exception 'A reason is required'; end if;
  update public.shifts set status=p_status,updated_by=v_actor,
    published_at=case when p_status='PUBLISHED' then now() else published_at end,
    cancelled_at=case when p_status='CANCELLED' then now() else null end
  where id=p_shift_id;
  insert into public.roster_audit(actor_staff_id,action,shift_id,reason,details)
  values(v_actor,'SHIFT_'||p_status::text,p_shift_id,nullif(trim(p_reason),''),jsonb_build_object('previous_status',v_current));
end;
$$;

create or replace function public.assign_employee(
  p_shift_id uuid, p_staff_id uuid, p_override_confirmed boolean, p_override_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := public.require_supervisor(); v_conflicts jsonb; v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('assignment:'||p_staff_id::text,0));
  v_conflicts := public.assignment_conflicts(p_shift_id,p_staff_id);
  if exists (select 1 from jsonb_array_elements(v_conflicts) x where not (x->>'overridable')::boolean) then
    raise exception 'Assignment has a non-overridable conflict: %',v_conflicts;
  end if;
  if jsonb_array_length(v_conflicts)>0 and (not coalesce(p_override_confirmed,false) or length(trim(coalesce(p_override_reason,'')))=0) then
    raise exception 'Override confirmation and written reason required';
  end if;
  insert into public.shift_assignments(shift_id,staff_id,assigned_by,override_confirmed,override_reason,override_conflicts)
  values(p_shift_id,p_staff_id,v_actor,jsonb_array_length(v_conflicts)>0,
    case when jsonb_array_length(v_conflicts)>0 then trim(p_override_reason) end,v_conflicts)
  returning id into v_id;
  insert into public.roster_audit(actor_staff_id,action,shift_id,assignment_id,subject_staff_id,reason,details)
  values(v_actor,case when jsonb_array_length(v_conflicts)>0 then 'ASSIGNMENT_OVERRIDDEN' else 'EMPLOYEE_ASSIGNED' end,
    p_shift_id,v_id,p_staff_id,nullif(trim(p_override_reason),''),jsonb_build_object('conflicts',v_conflicts));
  return v_id;
end;
$$;

create or replace function public.remove_employee(p_assignment_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := public.require_supervisor(); v_shift uuid; v_staff uuid;
begin
  if length(trim(coalesce(p_reason,'')))=0 then raise exception 'A removal reason is required'; end if;
  update public.shift_assignments set removed_at=now(),removed_by=v_actor,removal_reason=trim(p_reason)
  where id=p_assignment_id and removed_at is null returning shift_id,staff_id into v_shift,v_staff;
  if v_shift is null then raise exception 'Active assignment not found'; end if;
  insert into public.roster_audit(actor_staff_id,action,shift_id,assignment_id,subject_staff_id,reason)
  values(v_actor,'EMPLOYEE_REMOVED',v_shift,p_assignment_id,v_staff,trim(p_reason));
end;
$$;

create or replace function public.replace_employee(
  p_assignment_id uuid, p_replacement_staff_id uuid, p_override_confirmed boolean,
  p_override_reason text, p_replacement_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := public.require_supervisor(); v_shift uuid; v_old_staff uuid; v_new_id uuid; v_conflicts jsonb;
begin
  if length(trim(coalesce(p_replacement_reason,'')))=0 then raise exception 'A replacement reason is required'; end if;
  select shift_id,staff_id into v_shift,v_old_staff from public.shift_assignments where id=p_assignment_id and removed_at is null for update;
  if not found then raise exception 'Active assignment not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('assignment:'||p_replacement_staff_id::text,0));
  v_conflicts:=public.assignment_conflicts(v_shift,p_replacement_staff_id);
  if exists(select 1 from jsonb_array_elements(v_conflicts) x where not (x->>'overridable')::boolean) then raise exception 'Replacement has a non-overridable conflict: %',v_conflicts; end if;
  if jsonb_array_length(v_conflicts)>0 and (not coalesce(p_override_confirmed,false) or length(trim(coalesce(p_override_reason,'')))=0) then raise exception 'Override confirmation and written reason required'; end if;
  insert into public.shift_assignments(shift_id,staff_id,assigned_by,override_confirmed,override_reason,override_conflicts)
  values(v_shift,p_replacement_staff_id,v_actor,jsonb_array_length(v_conflicts)>0,
    case when jsonb_array_length(v_conflicts)>0 then trim(p_override_reason) end,v_conflicts) returning id into v_new_id;
  update public.shift_assignments set removed_at=now(),removed_by=v_actor,removal_reason=trim(p_replacement_reason),replaced_by_assignment_id=v_new_id
  where id=p_assignment_id;
  insert into public.roster_audit(actor_staff_id,action,shift_id,assignment_id,subject_staff_id,reason,details)
  values(v_actor,'EMPLOYEE_REPLACED',v_shift,p_assignment_id,v_old_staff,trim(p_replacement_reason),jsonb_build_object('replacement_assignment_id',v_new_id,'replacement_staff_id',p_replacement_staff_id,'conflicts',v_conflicts));
  return v_new_id;
end;
$$;

revoke all on public.shifts, public.shift_assignments, public.roster_audit from anon, authenticated;
grant select on public.shifts, public.shift_assignments, public.roster_audit to authenticated;
revoke all on function public.require_supervisor() from public, anon;
revoke all on function public.is_shift_published(uuid) from public, anon;
revoke all on function public.assignment_conflicts(uuid,uuid) from public, anon;
revoke all on function public.shift_candidates(uuid) from public, anon;
revoke all on function public.save_shift(uuid,date,time,time,uuid,uuid,integer,text) from public, anon;
revoke all on function public.copy_shift(uuid,date) from public, anon;
revoke all on function public.set_shift_status(uuid,public.shift_status,text) from public, anon;
revoke all on function public.assign_employee(uuid,uuid,boolean,text) from public, anon;
revoke all on function public.remove_employee(uuid,text) from public, anon;
revoke all on function public.replace_employee(uuid,uuid,boolean,text,text) from public, anon;
grant execute on function public.assignment_conflicts(uuid,uuid), public.shift_candidates(uuid),
  public.save_shift(uuid,date,time,time,uuid,uuid,integer,text), public.copy_shift(uuid,date),
  public.set_shift_status(uuid,public.shift_status,text), public.assign_employee(uuid,uuid,boolean,text),
  public.remove_employee(uuid,text), public.replace_employee(uuid,uuid,boolean,text,text) to authenticated;
grant execute on function public.is_shift_published(uuid) to authenticated;
