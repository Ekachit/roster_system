create type public.release_request_status as enum (
  'PENDING',
  'APPROVED',
  'REJECTED',
  'CANCELLED'
);

create table public.release_requests (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.shift_assignments(id) on delete restrict,
  staff_id uuid not null references public.staff(id) on delete restrict,
  reason text not null check (length(trim(reason)) > 0),
  note text,
  status public.release_request_status not null default 'PENDING',
  submitted_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.staff(id) on delete restrict,
  resolution_reason text,
  replacement_assignment_id uuid references public.shift_assignments(id) on delete restrict,
  constraint release_request_resolution_shape check (
    (
      status = 'PENDING'
      and resolved_at is null
      and resolved_by is null
      and resolution_reason is null
      and replacement_assignment_id is null
    )
    or (
      status in ('APPROVED', 'REJECTED', 'CANCELLED')
      and resolved_at is not null
      and resolved_by is not null
      and length(trim(resolution_reason)) > 0
      and (status <> 'REJECTED' or replacement_assignment_id is null)
    )
  )
);

create unique index release_requests_one_pending_assignment_idx
  on public.release_requests(assignment_id)
  where status = 'PENDING';
create index release_requests_staff_submitted_idx
  on public.release_requests(staff_id, submitted_at desc);
create index release_requests_status_submitted_idx
  on public.release_requests(status, submitted_at);

alter table public.release_requests enable row level security;

create policy release_requests_employee_own_select on public.release_requests
for select to authenticated using (staff_id = public.current_staff_id());

create policy release_requests_supervisor_select on public.release_requests
for select to authenticated using (public.is_supervisor());

revoke all on public.release_requests from anon, authenticated;

alter table public.roster_audit
  add column release_request_id uuid references public.release_requests(id) on delete restrict,
  add column entity_type text,
  add column entity_id uuid,
  add column before_data jsonb not null default '{}'::jsonb,
  add column after_data jsonb not null default '{}'::jsonb;

update public.roster_audit
set
  entity_type = case
    when release_request_id is not null then 'RELEASE_REQUEST'
    when assignment_id is not null then 'ASSIGNMENT'
    when shift_id is not null then 'SHIFT'
    when subject_staff_id is not null then 'STAFF'
    else 'AUDIT_EVENT'
  end,
  entity_id = coalesce(release_request_id, assignment_id, shift_id, subject_staff_id);

alter table public.roster_audit
  add constraint roster_audit_entity_type_nonblank
    check (entity_type is null or length(trim(entity_type)) > 0);

create index roster_audit_entity_idx
  on public.roster_audit(entity_type, entity_id, created_at desc);
create index roster_audit_request_idx
  on public.roster_audit(release_request_id, created_at desc)
  where release_request_id is not null;

create or replace function public.normalise_roster_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.entity_type is null then
    new.entity_type := case
      when new.release_request_id is not null then 'RELEASE_REQUEST'
      when new.assignment_id is not null then 'ASSIGNMENT'
      when new.shift_id is not null then 'SHIFT'
      when new.subject_staff_id is not null then 'STAFF'
      else 'AUDIT_EVENT'
    end;
  end if;

  if new.entity_id is null then
    new.entity_id := coalesce(
      new.release_request_id,
      new.assignment_id,
      new.shift_id,
      new.subject_staff_id
    );
  end if;

  new.before_data := coalesce(new.before_data, '{}'::jsonb);
  new.after_data := coalesce(new.after_data, '{}'::jsonb);
  return new;
end;
$$;

create trigger roster_audit_normalise_before_insert
before insert on public.roster_audit
for each row execute function public.normalise_roster_audit();

create or replace function public.protect_release_request_invariants()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assignment_staff_id uuid;
begin
  if tg_op = 'INSERT' then
    select assignment.staff_id
    into v_assignment_staff_id
    from public.shift_assignments assignment
    where assignment.id = new.assignment_id;

    if v_assignment_staff_id is null or v_assignment_staff_id <> new.staff_id then
      raise exception 'Release request employee must own the assignment';
    end if;
  else
    if new.assignment_id <> old.assignment_id
       or new.staff_id <> old.staff_id
       or new.reason <> old.reason
       or new.note is distinct from old.note
       or new.submitted_at <> old.submitted_at then
      raise exception 'Submitted release request details are immutable';
    end if;
    if old.status <> 'PENDING'
       or new.status not in ('APPROVED', 'REJECTED', 'CANCELLED') then
      raise exception 'Only pending release requests can be resolved';
    end if;
  end if;
  return new;
end;
$$;

create trigger release_requests_protect_invariants
before insert or update on public.release_requests
for each row execute function public.protect_release_request_invariants();

create or replace function public.lock_release_workflow(p_shift_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_shift_id is null then raise exception 'Shift is required'; end if;
  perform pg_advisory_xact_lock(
    hashtextextended('release-shift:' || p_shift_id::text, 0)
  );
end;
$$;

create or replace function public.release_request_submission_open(
  p_shift_id uuid,
  p_at timestamptz default now()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.shifts shift
    where shift.id = p_shift_id
      and shift.status = 'PUBLISHED'
      and p_at < (
        (shift.local_date + shift.end_time)
        at time zone 'Australia/Melbourne'
      )
  )
$$;

create or replace function public.submit_release_request(
  p_assignment_id uuid,
  p_reason text,
  p_note text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff_id uuid := public.current_staff_id();
  v_shift_id uuid;
  v_request_id uuid;
begin
  if v_staff_id is null
     or not exists (
       select 1 from public.staff
       where id = v_staff_id and role = 'employee' and is_active
     ) then
    raise exception 'Active employee access required' using errcode = '42501';
  end if;

  if length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'A release reason is required';
  end if;

  select assignment.shift_id
  into v_shift_id
  from public.shift_assignments assignment
  where assignment.id = p_assignment_id
    and assignment.staff_id = v_staff_id;

  if v_shift_id is null then
    raise exception 'Active published assignment not found' using errcode = '42501';
  end if;

  perform public.lock_release_workflow(v_shift_id);

  select assignment.shift_id
  into v_shift_id
  from public.shift_assignments assignment
  join public.shifts shift on shift.id = assignment.shift_id
  where assignment.id = p_assignment_id
    and assignment.staff_id = v_staff_id
    and assignment.removed_at is null
    and shift.status = 'PUBLISHED'
    and public.release_request_submission_open(shift.id, now())
  for update of assignment;

  if v_shift_id is null then
    raise exception 'Active published assignment not found' using errcode = '42501';
  end if;

  insert into public.release_requests(assignment_id, staff_id, reason, note)
  values (
    p_assignment_id,
    v_staff_id,
    trim(p_reason),
    nullif(trim(coalesce(p_note, '')), '')
  )
  returning id into v_request_id;

  insert into public.roster_audit(
    actor_staff_id,
    action,
    shift_id,
    assignment_id,
    subject_staff_id,
    release_request_id,
    entity_type,
    entity_id,
    reason,
    after_data
  )
  values (
    v_staff_id,
    'RELEASE_REQUEST_CREATED',
    v_shift_id,
    p_assignment_id,
    v_staff_id,
    v_request_id,
    'RELEASE_REQUEST',
    v_request_id,
    trim(p_reason),
    jsonb_build_object('status', 'PENDING')
  );

  return v_request_id;
exception
  when unique_violation then
    raise exception 'A pending release request already exists for this assignment'
      using errcode = '23505';
end;
$$;

create or replace function public.employee_release_request_assignments()
returns table (
  assignment_id uuid,
  shift_id uuid,
  shift_title text,
  local_date date,
  start_time time,
  end_time time,
  location_name text,
  activity_name text,
  assignment_kind public.assignment_kind
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_staff_id uuid := public.current_staff_id();
begin
  if v_staff_id is null
     or not exists (
       select 1 from public.staff
       where id = v_staff_id and role = 'employee' and is_active
     ) then
    raise exception 'Active employee access required' using errcode = '42501';
  end if;

  return query
    select
      assignment.id,
      shift.id,
      shift.shift_title,
      shift.local_date,
      shift.start_time,
      shift.end_time,
      location.name::text,
      activity.name::text,
      assignment.assignment_kind
    from public.shift_assignments assignment
    join public.shifts shift on shift.id = assignment.shift_id
    join public.locations location on location.id = shift.location_id
    join public.activity_types activity on activity.id = shift.activity_type_id
    where assignment.staff_id = v_staff_id
      and assignment.removed_at is null
      and shift.status = 'PUBLISHED'
      and public.release_request_submission_open(shift.id, now())
      and not exists (
        select 1
        from public.release_requests request
        where request.assignment_id = assignment.id
          and request.status = 'PENDING'
      )
    order by shift.local_date, shift.start_time, shift.id;
end;
$$;

create or replace function public.employee_release_requests()
returns table (
  request_id uuid,
  assignment_id uuid,
  shift_id uuid,
  shift_title text,
  local_date date,
  start_time time,
  end_time time,
  location_name text,
  activity_name text,
  assignment_kind public.assignment_kind,
  reason text,
  note text,
  status public.release_request_status,
  submitted_at timestamptz,
  resolved_at timestamptz,
  resolution_reason text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_staff_id uuid := public.current_staff_id();
begin
  if v_staff_id is null
     or not exists (select 1 from public.staff where id = v_staff_id and role = 'employee') then
    raise exception 'Employee access required' using errcode = '42501';
  end if;

  return query
    select
      request.id,
      assignment.id,
      shift.id,
      shift.shift_title,
      shift.local_date,
      shift.start_time,
      shift.end_time,
      location.name::text,
      activity.name::text,
      assignment.assignment_kind,
      request.reason,
      request.note,
      request.status,
      request.submitted_at,
      request.resolved_at,
      request.resolution_reason
    from public.release_requests request
    join public.shift_assignments assignment on assignment.id = request.assignment_id
    join public.shifts shift on shift.id = assignment.shift_id
    join public.locations location on location.id = shift.location_id
    join public.activity_types activity on activity.id = shift.activity_type_id
    where request.staff_id = v_staff_id
    order by request.submitted_at desc, request.id;
end;
$$;

create or replace function public.supervisor_release_requests(
  p_status public.release_request_status default null
)
returns table (
  request_id uuid,
  assignment_id uuid,
  shift_id uuid,
  staff_id uuid,
  employee_name text,
  shift_title text,
  local_date date,
  start_time time,
  end_time time,
  location_name text,
  activity_name text,
  assignment_kind public.assignment_kind,
  assignment_active boolean,
  shift_status public.shift_status,
  reason text,
  note text,
  status public.release_request_status,
  submitted_at timestamptz,
  resolved_at timestamptz,
  resolved_by_name text,
  resolution_reason text,
  replacement_assignment_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_supervisor();

  return query
    select
      request.id,
      assignment.id,
      shift.id,
      employee.id,
      employee.full_name,
      shift.shift_title,
      shift.local_date,
      shift.start_time,
      shift.end_time,
      location.name::text,
      activity.name::text,
      assignment.assignment_kind,
      assignment.removed_at is null,
      shift.status,
      request.reason,
      request.note,
      request.status,
      request.submitted_at,
      request.resolved_at,
      resolver.full_name,
      request.resolution_reason,
      request.replacement_assignment_id
    from public.release_requests request
    join public.shift_assignments assignment on assignment.id = request.assignment_id
    join public.shifts shift on shift.id = assignment.shift_id
    join public.staff employee on employee.id = request.staff_id
    join public.locations location on location.id = shift.location_id
    join public.activity_types activity on activity.id = shift.activity_type_id
    left join public.staff resolver on resolver.id = request.resolved_by
    where p_status is null or request.status = p_status
    order by
      case request.status when 'PENDING' then 0 else 1 end,
      request.submitted_at,
      request.id;
end;
$$;

create or replace function public.release_request_candidates(p_request_id uuid)
returns table (
  staff_id uuid,
  full_name text,
  conflicts jsonb,
  fully_available boolean,
  eligible boolean,
  assignable_without_override boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_shift_id uuid;
begin
  perform public.require_supervisor();
  select assignment.shift_id
  into v_shift_id
  from public.release_requests request
  join public.shift_assignments assignment on assignment.id = request.assignment_id
  where request.id = p_request_id and request.status = 'PENDING';

  if v_shift_id is null then
    raise exception 'Pending release request not found';
  end if;

  return query select * from public.shift_candidates(v_shift_id);
end;
$$;

create or replace function public.reject_release_request(
  p_request_id uuid,
  p_rejection_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_supervisor();
  v_request public.release_requests%rowtype;
  v_assignment_id uuid;
  v_shift_id uuid;
begin
  if length(trim(coalesce(p_rejection_reason, ''))) = 0 then
    raise exception 'A rejection reason is required';
  end if;

  select request.assignment_id, assignment.shift_id
  into v_assignment_id, v_shift_id
  from public.release_requests request
  join public.shift_assignments assignment on assignment.id = request.assignment_id
  where request.id = p_request_id;

  if v_shift_id is null then raise exception 'Pending release request not found'; end if;

  perform public.lock_release_workflow(v_shift_id);

  perform 1
  from public.shift_assignments assignment
  where assignment.id = v_assignment_id
  for update;

  select request.*
  into v_request
  from public.release_requests request
  where request.id = p_request_id
    and request.assignment_id = v_assignment_id
    and request.status = 'PENDING'
  for update;

  if not found then raise exception 'Pending release request not found'; end if;

  update public.release_requests
  set
    status = 'REJECTED',
    resolved_at = now(),
    resolved_by = v_actor,
    resolution_reason = trim(p_rejection_reason)
  where id = p_request_id;

  insert into public.roster_audit(
    actor_staff_id,
    action,
    shift_id,
    assignment_id,
    subject_staff_id,
    release_request_id,
    entity_type,
    entity_id,
    reason,
    before_data,
    after_data
  )
  values (
    v_actor,
    'RELEASE_REQUEST_REJECTED',
    v_shift_id,
    v_request.assignment_id,
    v_request.staff_id,
    p_request_id,
    'RELEASE_REQUEST',
    p_request_id,
    trim(p_rejection_reason),
    jsonb_build_object('status', 'PENDING'),
    jsonb_build_object('status', 'REJECTED')
  );
end;
$$;

create or replace function public.approve_release_request_remove(
  p_request_id uuid,
  p_approval_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_supervisor();
  v_request public.release_requests%rowtype;
  v_assignment_id uuid;
  v_shift_id uuid;
begin
  if length(trim(coalesce(p_approval_reason, ''))) = 0 then
    raise exception 'An approval reason is required';
  end if;

  select request.assignment_id, assignment.shift_id
  into v_assignment_id, v_shift_id
  from public.release_requests request
  join public.shift_assignments assignment on assignment.id = request.assignment_id
  where request.id = p_request_id;

  if v_shift_id is null then raise exception 'Pending release request not found'; end if;

  perform public.lock_release_workflow(v_shift_id);

  perform 1
  from public.shift_assignments assignment
  where assignment.id = v_assignment_id
    and assignment.removed_at is null
  for update;

  if not found then raise exception 'Active assignment not found'; end if;

  select request.*
  into v_request
  from public.release_requests request
  where request.id = p_request_id
    and request.assignment_id = v_assignment_id
    and request.status = 'PENDING'
  for update;

  if not found then raise exception 'Pending release request not found'; end if;

  if not exists (
    select 1 from public.shift_assignments assignment
    where assignment.id = v_assignment_id
      and assignment.staff_id = v_request.staff_id
      and assignment.removed_at is null
  ) then
    raise exception 'Active assignment not found';
  end if;

  update public.shift_assignments
  set
    removed_at = now(),
    removed_by = v_actor,
    removal_reason = trim(p_approval_reason)
  where id = v_request.assignment_id;

  update public.release_requests
  set
    status = 'APPROVED',
    resolved_at = now(),
    resolved_by = v_actor,
    resolution_reason = trim(p_approval_reason)
  where id = p_request_id;

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
    reason, before_data, after_data
  )
  values (
    v_actor, 'EMPLOYEE_REMOVED', v_shift_id, v_request.assignment_id, v_request.staff_id,
    trim(p_approval_reason),
    jsonb_build_object('active', true),
    jsonb_build_object('active', false)
  );

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
    release_request_id, entity_type, entity_id, reason, before_data, after_data
  )
  values (
    v_actor, 'RELEASE_REQUEST_APPROVED', v_shift_id, v_request.assignment_id, v_request.staff_id,
    p_request_id, 'RELEASE_REQUEST', p_request_id, trim(p_approval_reason),
    jsonb_build_object('status', 'PENDING'),
    jsonb_build_object('status', 'APPROVED', 'outcome', 'REMOVED')
  );
end;
$$;

create or replace function public.approve_release_request_replace(
  p_request_id uuid,
  p_replacement_staff_id uuid,
  p_override_confirmed boolean,
  p_override_reason text,
  p_approval_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_supervisor();
  v_request public.release_requests%rowtype;
  v_assignment_id uuid;
  v_shift_id uuid;
  v_assignment_kind public.assignment_kind;
  v_conflicts jsonb;
  v_new_assignment_id uuid;
begin
  if length(trim(coalesce(p_approval_reason, ''))) = 0 then
    raise exception 'An approval reason is required';
  end if;
  if p_replacement_staff_id is null then raise exception 'A replacement employee is required'; end if;

  select request.assignment_id, assignment.shift_id
  into v_assignment_id, v_shift_id
  from public.release_requests request
  join public.shift_assignments assignment on assignment.id = request.assignment_id
  where request.id = p_request_id;

  if v_shift_id is null then raise exception 'Pending release request not found'; end if;

  perform public.lock_release_workflow(v_shift_id);

  select assignment.assignment_kind
  into v_assignment_kind
  from public.shift_assignments assignment
  where assignment.id = v_assignment_id
    and assignment.removed_at is null
  for update;

  if not found then raise exception 'Active assignment not found'; end if;

  select request.*
  into v_request
  from public.release_requests request
  where request.id = p_request_id
    and request.assignment_id = v_assignment_id
    and request.status = 'PENDING'
  for update;

  if not found then raise exception 'Pending release request not found'; end if;
  if not exists (
    select 1 from public.shift_assignments assignment
    where assignment.id = v_assignment_id
      and assignment.staff_id = v_request.staff_id
      and assignment.removed_at is null
  ) then
    raise exception 'Active assignment not found';
  end if;
  if p_replacement_staff_id = v_request.staff_id then
    raise exception 'Replacement employee must be different';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('assignment:' || p_replacement_staff_id::text, 0)
  );
  v_conflicts := public.assignment_conflicts(v_shift_id, p_replacement_staff_id);

  if exists (
    select 1
    from jsonb_array_elements(v_conflicts) conflict
    where not (conflict->>'overridable')::boolean
  ) then
    raise exception 'Replacement has a non-overridable conflict: %', v_conflicts;
  end if;

  if jsonb_array_length(v_conflicts) > 0
     and (
       not coalesce(p_override_confirmed, false)
       or length(trim(coalesce(p_override_reason, ''))) = 0
     ) then
    raise exception 'Override confirmation and written reason required';
  end if;

  insert into public.shift_assignments(
    shift_id,
    staff_id,
    assignment_kind,
    assigned_by,
    override_confirmed,
    override_reason,
    override_conflicts
  )
  values (
    v_shift_id,
    p_replacement_staff_id,
    v_assignment_kind,
    v_actor,
    jsonb_array_length(v_conflicts) > 0,
    case when jsonb_array_length(v_conflicts) > 0 then trim(p_override_reason) end,
    v_conflicts
  )
  returning id into v_new_assignment_id;

  update public.shift_assignments
  set
    removed_at = now(),
    removed_by = v_actor,
    removal_reason = trim(p_approval_reason),
    replaced_by_assignment_id = v_new_assignment_id
  where id = v_request.assignment_id;

  update public.release_requests
  set
    status = 'APPROVED',
    resolved_at = now(),
    resolved_by = v_actor,
    resolution_reason = trim(p_approval_reason),
    replacement_assignment_id = v_new_assignment_id
  where id = p_request_id;

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
    reason, after_data
  )
  values (
    v_actor, 'EMPLOYEE_ASSIGNED', v_shift_id, v_new_assignment_id, p_replacement_staff_id,
    nullif(trim(coalesce(p_override_reason, '')), ''),
    jsonb_build_object('assignment_kind', v_assignment_kind, 'conflicts', v_conflicts)
  );

  if jsonb_array_length(v_conflicts) > 0 then
    insert into public.roster_audit(
      actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
      reason, details, after_data
    )
    values (
      v_actor, 'ASSIGNMENT_OVERRIDDEN', v_shift_id, v_new_assignment_id, p_replacement_staff_id,
      trim(p_override_reason), jsonb_build_object('conflicts', v_conflicts),
      jsonb_build_object('override_confirmed', true)
    );
  end if;

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
    reason, before_data, after_data
  )
  values (
    v_actor, 'EMPLOYEE_REMOVED', v_shift_id, v_request.assignment_id, v_request.staff_id,
    trim(p_approval_reason),
    jsonb_build_object('active', true),
    jsonb_build_object('active', false, 'replacement_assignment_id', v_new_assignment_id)
  );

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
    reason, details, before_data, after_data
  )
  values (
    v_actor, 'EMPLOYEE_REPLACED', v_shift_id, v_request.assignment_id, v_request.staff_id,
    trim(p_approval_reason),
    jsonb_build_object(
      'replacement_assignment_id', v_new_assignment_id,
      'replacement_staff_id', p_replacement_staff_id,
      'conflicts', v_conflicts
    ),
    jsonb_build_object('staff_id', v_request.staff_id),
    jsonb_build_object('staff_id', p_replacement_staff_id)
  );

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
    release_request_id, entity_type, entity_id, reason, before_data, after_data
  )
  values (
    v_actor, 'RELEASE_REQUEST_APPROVED', v_shift_id, v_request.assignment_id, v_request.staff_id,
    p_request_id, 'RELEASE_REQUEST', p_request_id, trim(p_approval_reason),
    jsonb_build_object('status', 'PENDING'),
    jsonb_build_object(
      'status', 'APPROVED',
      'outcome', 'REPLACED',
      'replacement_assignment_id', v_new_assignment_id
    )
  );

  return v_new_assignment_id;
end;
$$;

create or replace function public.assign_employee(
  p_shift_id uuid,
  p_staff_id uuid,
  p_assignment_kind public.assignment_kind,
  p_override_confirmed boolean,
  p_override_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_supervisor();
  v_conflicts jsonb;
  v_id uuid;
begin
  perform public.lock_release_workflow(p_shift_id);
  perform pg_advisory_xact_lock(hashtextextended('assignment:' || p_staff_id::text, 0));
  v_conflicts := public.assignment_conflicts(p_shift_id, p_staff_id);
  if exists (
    select 1 from jsonb_array_elements(v_conflicts) conflict
    where not (conflict->>'overridable')::boolean
  ) then
    raise exception 'Assignment has a non-overridable conflict: %', v_conflicts;
  end if;
  if jsonb_array_length(v_conflicts) > 0
     and (
       not coalesce(p_override_confirmed, false)
       or length(trim(coalesce(p_override_reason, ''))) = 0
     ) then
    raise exception 'Override confirmation and written reason required';
  end if;

  insert into public.shift_assignments(
    shift_id, staff_id, assignment_kind, assigned_by,
    override_confirmed, override_reason, override_conflicts
  )
  values (
    p_shift_id, p_staff_id, p_assignment_kind, v_actor,
    jsonb_array_length(v_conflicts) > 0,
    case when jsonb_array_length(v_conflicts) > 0 then trim(p_override_reason) end,
    v_conflicts
  )
  returning id into v_id;

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
    reason, after_data
  )
  values (
    v_actor, 'EMPLOYEE_ASSIGNED', p_shift_id, v_id, p_staff_id,
    nullif(trim(coalesce(p_override_reason, '')), ''),
    jsonb_build_object('assignment_kind', p_assignment_kind)
  );

  if jsonb_array_length(v_conflicts) > 0 then
    insert into public.roster_audit(
      actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
      reason, details, after_data
    )
    values (
      v_actor, 'ASSIGNMENT_OVERRIDDEN', p_shift_id, v_id, p_staff_id,
      trim(p_override_reason), jsonb_build_object('conflicts', v_conflicts),
      jsonb_build_object('override_confirmed', true)
    );
  end if;

  return v_id;
end;
$$;

create or replace function public.cancel_pending_release_requests_for_assignment(
  p_assignment_id uuid,
  p_actor uuid,
  p_resolution_reason text,
  p_replacement_assignment_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_request record;
  v_shift_id uuid;
begin
  select assignment.shift_id
  into v_shift_id
  from public.shift_assignments assignment
  where assignment.id = p_assignment_id;

  for v_request in
    update public.release_requests
    set
      status = 'CANCELLED',
      resolved_at = now(),
      resolved_by = p_actor,
      resolution_reason = trim(p_resolution_reason),
      replacement_assignment_id = p_replacement_assignment_id
    where assignment_id = p_assignment_id
      and status = 'PENDING'
    returning *
  loop
    v_count := v_count + 1;
    insert into public.roster_audit(
      actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
      release_request_id, entity_type, entity_id, reason, before_data, after_data
    )
    values (
      p_actor, 'RELEASE_REQUEST_CANCELLED', v_shift_id, p_assignment_id, v_request.staff_id,
      v_request.id, 'RELEASE_REQUEST', v_request.id, trim(p_resolution_reason),
      jsonb_build_object('status', 'PENDING'),
      jsonb_build_object(
        'status', 'CANCELLED',
        'outcome', case when p_replacement_assignment_id is null then 'OBSOLETE' else 'REPLACED_EXTERNALLY' end,
        'replacement_assignment_id', p_replacement_assignment_id
      )
    );
  end loop;
  return v_count;
end;
$$;

create or replace function public.save_shift(
  p_shift_id uuid,
  p_shift_title text,
  p_local_date date,
  p_start_time time,
  p_end_time time,
  p_location_id uuid,
  p_activity_type_id uuid,
  p_required_staff_count integer,
  p_notes text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_supervisor();
  v_id uuid;
  v_before public.shifts%rowtype;
  v_after public.shifts%rowtype;
begin
  if length(trim(coalesce(p_shift_title, ''))) = 0 then raise exception 'Shift title is required'; end if;
  if p_local_date is null
     or p_start_time is null
     or p_end_time is null
     or p_end_time <= p_start_time
     or not public.is_valid_melbourne_local_time(p_local_date, p_start_time)
     or not public.is_valid_melbourne_local_time(p_local_date, p_end_time) then
    raise exception 'Invalid shift time';
  end if;
  if p_required_staff_count is null or p_required_staff_count < 1 then
    raise exception 'Required staff count must be at least 1';
  end if;
  if not exists (select 1 from public.locations where id = p_location_id and is_active) then
    raise exception 'Active location required';
  end if;
  if not exists (select 1 from public.activity_types where id = p_activity_type_id and is_active) then
    raise exception 'Active activity type required';
  end if;

  if p_shift_id is null then
    insert into public.shifts(
      shift_title, local_date, start_time, end_time, location_id,
      activity_type_id, required_staff_count, notes, created_by, updated_by
    )
    values (
      trim(p_shift_title), p_local_date, p_start_time, p_end_time, p_location_id,
      p_activity_type_id, p_required_staff_count,
      nullif(trim(coalesce(p_notes, '')), ''), v_actor, v_actor
    )
    returning * into v_after;
    v_id := v_after.id;
  else
    select * into v_before
    from public.shifts
    where id = p_shift_id and status = 'DRAFT'
    for update;
    if not found then raise exception 'Only draft shifts can be edited'; end if;

    update public.shifts
    set
      shift_title = trim(p_shift_title),
      local_date = p_local_date,
      start_time = p_start_time,
      end_time = p_end_time,
      location_id = p_location_id,
      activity_type_id = p_activity_type_id,
      required_staff_count = p_required_staff_count,
      notes = nullif(trim(coalesce(p_notes, '')), ''),
      updated_by = v_actor
    where id = p_shift_id
    returning * into v_after;
    v_id := v_after.id;

    if exists (
      select 1
      from public.shift_assignments assignment
      join public.shifts other_shift on other_shift.id = assignment.shift_id
      join public.shift_assignments changed
        on changed.staff_id = assignment.staff_id
      where changed.shift_id = v_id
        and changed.removed_at is null
        and assignment.removed_at is null
        and assignment.shift_id <> v_id
        and other_shift.status <> 'CANCELLED'
        and other_shift.local_date = p_local_date
        and other_shift.start_time < p_end_time
        and p_start_time < other_shift.end_time
    ) then
      raise exception 'Edit would create overlapping active assignments';
    end if;
  end if;

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, details, before_data, after_data
  )
  values (
    v_actor,
    case when p_shift_id is null then 'SHIFT_CREATED' else 'SHIFT_EDITED' end,
    v_id,
    jsonb_build_object('shift_title', trim(p_shift_title)),
    case when p_shift_id is null then '{}'::jsonb else jsonb_build_object(
      'shift_title', v_before.shift_title,
      'local_date', v_before.local_date,
      'start_time', v_before.start_time,
      'end_time', v_before.end_time,
      'location_id', v_before.location_id,
      'activity_type_id', v_before.activity_type_id,
      'required_staff_count', v_before.required_staff_count,
      'notes', v_before.notes
    ) end,
    jsonb_build_object(
      'shift_title', v_after.shift_title,
      'local_date', v_after.local_date,
      'start_time', v_after.start_time,
      'end_time', v_after.end_time,
      'location_id', v_after.location_id,
      'activity_type_id', v_after.activity_type_id,
      'required_staff_count', v_after.required_staff_count,
      'notes', v_after.notes
    )
  );

  return v_id;
end;
$$;

create or replace function public.remove_employee(p_assignment_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_supervisor();
  v_shift uuid;
  v_staff uuid;
begin
  if length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'A removal reason is required';
  end if;

  select assignment.shift_id
  into v_shift
  from public.shift_assignments assignment
  where assignment.id = p_assignment_id;

  if v_shift is null then raise exception 'Active assignment not found'; end if;

  perform public.lock_release_workflow(v_shift);

  select assignment.shift_id, assignment.staff_id
  into v_shift, v_staff
  from public.shift_assignments assignment
  where assignment.id = p_assignment_id
    and assignment.removed_at is null
  for update;

  if not found then raise exception 'Active assignment not found'; end if;

  update public.shift_assignments
  set removed_at = now(), removed_by = v_actor, removal_reason = trim(p_reason)
  where id = p_assignment_id;

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
    reason, before_data, after_data
  )
  values (
    v_actor, 'EMPLOYEE_REMOVED', v_shift, p_assignment_id, v_staff, trim(p_reason),
    jsonb_build_object('active', true), jsonb_build_object('active', false)
  );

  perform public.cancel_pending_release_requests_for_assignment(
    p_assignment_id,
    v_actor,
    'Cancelled because the assignment was independently removed: ' || trim(p_reason),
    null
  );
end;
$$;

create or replace function public.replace_employee(
  p_assignment_id uuid,
  p_replacement_staff_id uuid,
  p_assignment_kind public.assignment_kind,
  p_override_confirmed boolean,
  p_override_reason text,
  p_replacement_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_supervisor();
  v_shift uuid;
  v_old_staff uuid;
  v_old_kind public.assignment_kind;
  v_new_id uuid;
  v_conflicts jsonb;
begin
  if length(trim(coalesce(p_replacement_reason, ''))) = 0 then
    raise exception 'A replacement reason is required';
  end if;
  select assignment.shift_id
  into v_shift
  from public.shift_assignments assignment
  where assignment.id = p_assignment_id;
  if v_shift is null then raise exception 'Active assignment not found'; end if;

  perform public.lock_release_workflow(v_shift);

  select shift_id, staff_id, assignment_kind
  into v_shift, v_old_staff, v_old_kind
  from public.shift_assignments
  where id = p_assignment_id and removed_at is null
  for update;
  if not found then raise exception 'Active assignment not found'; end if;
  if p_replacement_staff_id = v_old_staff then raise exception 'Replacement employee must be different'; end if;
  if p_assignment_kind is distinct from v_old_kind then
    raise exception 'Replacement assignment kind must match the original assignment';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('assignment:' || p_replacement_staff_id::text, 0));
  v_conflicts := public.assignment_conflicts(v_shift, p_replacement_staff_id);
  if exists (
    select 1 from jsonb_array_elements(v_conflicts) conflict
    where not (conflict->>'overridable')::boolean
  ) then
    raise exception 'Replacement has a non-overridable conflict: %', v_conflicts;
  end if;
  if jsonb_array_length(v_conflicts) > 0
     and (
       not coalesce(p_override_confirmed, false)
       or length(trim(coalesce(p_override_reason, ''))) = 0
     ) then
    raise exception 'Override confirmation and written reason required';
  end if;

  insert into public.shift_assignments(
    shift_id, staff_id, assignment_kind, assigned_by,
    override_confirmed, override_reason, override_conflicts
  )
  values (
    v_shift, p_replacement_staff_id, v_old_kind, v_actor,
    jsonb_array_length(v_conflicts) > 0,
    case when jsonb_array_length(v_conflicts) > 0 then trim(p_override_reason) end,
    v_conflicts
  )
  returning id into v_new_id;

  update public.shift_assignments
  set
    removed_at = now(),
    removed_by = v_actor,
    removal_reason = trim(p_replacement_reason),
    replaced_by_assignment_id = v_new_id
  where id = p_assignment_id;

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
    reason, after_data
  )
  values (
    v_actor, 'EMPLOYEE_ASSIGNED', v_shift, v_new_id, p_replacement_staff_id,
    nullif(trim(coalesce(p_override_reason, '')), ''),
    jsonb_build_object('assignment_kind', v_old_kind)
  );

  if jsonb_array_length(v_conflicts) > 0 then
    insert into public.roster_audit(
      actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
      reason, details, after_data
    )
    values (
      v_actor, 'ASSIGNMENT_OVERRIDDEN', v_shift, v_new_id, p_replacement_staff_id,
      trim(p_override_reason), jsonb_build_object('conflicts', v_conflicts),
      jsonb_build_object('override_confirmed', true)
    );
  end if;

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
    reason, before_data, after_data
  )
  values (
    v_actor, 'EMPLOYEE_REMOVED', v_shift, p_assignment_id, v_old_staff,
    trim(p_replacement_reason),
    jsonb_build_object('active', true),
    jsonb_build_object('active', false, 'replacement_assignment_id', v_new_id)
  );

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, assignment_id, subject_staff_id,
    reason, details, before_data, after_data
  )
  values (
    v_actor, 'EMPLOYEE_REPLACED', v_shift, p_assignment_id, v_old_staff,
    trim(p_replacement_reason),
    jsonb_build_object(
      'replacement_assignment_id', v_new_id,
      'replacement_staff_id', p_replacement_staff_id,
      'conflicts', v_conflicts
    ),
    jsonb_build_object('staff_id', v_old_staff),
    jsonb_build_object('staff_id', p_replacement_staff_id)
  );

  perform public.cancel_pending_release_requests_for_assignment(
    p_assignment_id,
    v_actor,
    'Cancelled because the assignment was independently replaced: ' || trim(p_replacement_reason),
    v_new_id
  );

  return v_new_id;
end;
$$;

create or replace function public.set_shift_status(
  p_shift_id uuid,
  p_status public.shift_status,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_supervisor();
  v_current public.shift_status;
  v_assignment record;
  v_action text;
begin
  perform public.lock_release_workflow(p_shift_id);

  select status into v_current
  from public.shifts
  where id = p_shift_id
  for update;
  if not found then raise exception 'Shift not found'; end if;
  if p_status = 'PUBLISHED' and v_current <> 'DRAFT' then raise exception 'Only draft shifts can be published'; end if;
  if p_status = 'DRAFT' and v_current <> 'PUBLISHED' then raise exception 'Only published shifts can be unpublished'; end if;
  if p_status = 'CANCELLED' and v_current = 'CANCELLED' then raise exception 'Shift is already cancelled'; end if;
  if p_status in ('DRAFT', 'CANCELLED')
     and length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'A reason is required';
  end if;

  update public.shifts
  set
    status = p_status,
    updated_by = v_actor,
    published_at = case when p_status = 'PUBLISHED' then now() else published_at end,
    cancelled_at = case when p_status = 'CANCELLED' then now() else null end
  where id = p_shift_id;

  v_action := case p_status
    when 'PUBLISHED' then 'SHIFT_PUBLISHED'
    when 'DRAFT' then 'SHIFT_UNPUBLISHED'
    when 'CANCELLED' then 'SHIFT_CANCELLED'
  end;

  insert into public.roster_audit(
    actor_staff_id, action, shift_id, reason, details, before_data, after_data
  )
  values (
    v_actor, v_action, p_shift_id, nullif(trim(coalesce(p_reason, '')), ''),
    jsonb_build_object('previous_status', v_current),
    jsonb_build_object('status', v_current),
    jsonb_build_object('status', p_status)
  );

  if p_status = 'CANCELLED' then
    for v_assignment in
      select assignment.id
      from public.shift_assignments assignment
      where assignment.shift_id = p_shift_id
        and assignment.removed_at is null
      order by assignment.id
      for update
    loop
      perform public.cancel_pending_release_requests_for_assignment(
        v_assignment.id,
        v_actor,
        'Cancelled because the shift was independently cancelled: ' || trim(p_reason),
        null
      );
    end loop;
  end if;
end;
$$;

create or replace function public.save_recurring_availability(
  p_id uuid,
  p_weekday smallint,
  p_start_time time,
  p_end_time time,
  p_effective_start_date date,
  p_effective_end_date date,
  p_note text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff_id uuid := public.current_staff_id();
  v_id uuid;
  v_before public.recurring_availability%rowtype;
  v_after public.recurring_availability%rowtype;
begin
  if v_staff_id is null then raise exception 'Active staff access required'; end if;
  if not exists (select 1 from public.staff where id = v_staff_id and role = 'employee') then
    raise exception 'Employee access required';
  end if;
  if p_weekday not between 1 and 7
     or p_start_time is null or p_end_time is null or p_end_time <= p_start_time then
    raise exception 'End time must be later than start time on an ISO weekday from 1 to 7';
  end if;
  if p_effective_start_date is null
     or (p_effective_end_date is not null and p_effective_end_date < p_effective_start_date) then
    raise exception 'Effective date range is invalid';
  end if;

  if p_id is null then
    insert into public.recurring_availability(
      staff_id, weekday, start_time, end_time,
      effective_start_date, effective_end_date, note
    )
    values (
      v_staff_id, p_weekday, p_start_time, p_end_time,
      p_effective_start_date, p_effective_end_date,
      nullif(trim(coalesce(p_note, '')), '')
    )
    returning * into v_after;
    v_id := v_after.id;
  else
    select * into v_before
    from public.recurring_availability
    where id = p_id and staff_id = v_staff_id
    for update;
    if not found then raise exception 'Recurring availability not found'; end if;

    update public.recurring_availability
    set
      weekday = p_weekday,
      start_time = p_start_time,
      end_time = p_end_time,
      effective_start_date = p_effective_start_date,
      effective_end_date = p_effective_end_date,
      note = nullif(trim(coalesce(p_note, '')), '')
    where id = p_id
    returning * into v_after;
    v_id := v_after.id;
  end if;

  insert into public.roster_audit(
    actor_staff_id, action, subject_staff_id, entity_type, entity_id,
    before_data, after_data
  )
  values (
    v_staff_id,
    case when p_id is null then 'AVAILABILITY_CREATED' else 'AVAILABILITY_UPDATED' end,
    v_staff_id,
    'RECURRING_AVAILABILITY',
    v_id,
    case when p_id is null then '{}'::jsonb else jsonb_build_object(
      'weekday', v_before.weekday,
      'start_time', v_before.start_time,
      'end_time', v_before.end_time,
      'effective_start_date', v_before.effective_start_date,
      'effective_end_date', v_before.effective_end_date
    ) end,
    jsonb_build_object(
      'weekday', v_after.weekday,
      'start_time', v_after.start_time,
      'end_time', v_after.end_time,
      'effective_start_date', v_after.effective_start_date,
      'effective_end_date', v_after.effective_end_date
    )
  );
  return v_id;
end;
$$;

create or replace function public.delete_recurring_availability(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff_id uuid := public.current_staff_id();
  v_before public.recurring_availability%rowtype;
begin
  delete from public.recurring_availability
  where id = p_id
    and staff_id = v_staff_id
    and exists (
      select 1 from public.staff
      where id = v_staff_id and role = 'employee'
    )
  returning * into v_before;
  if not found then raise exception 'Recurring availability not found'; end if;

  insert into public.roster_audit(
    actor_staff_id, action, subject_staff_id, entity_type, entity_id, before_data
  )
  values (
    v_staff_id, 'AVAILABILITY_REMOVED', v_staff_id,
    'RECURRING_AVAILABILITY', p_id,
    jsonb_build_object(
      'weekday', v_before.weekday,
      'start_time', v_before.start_time,
      'end_time', v_before.end_time,
      'effective_start_date', v_before.effective_start_date,
      'effective_end_date', v_before.effective_end_date
    )
  );
end;
$$;

create or replace function public.save_availability_exception(
  p_id uuid,
  p_local_date date,
  p_kind public.availability_kind,
  p_start_time time,
  p_end_time time,
  p_is_full_day boolean,
  p_note text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff_id uuid := public.current_staff_id();
  v_id uuid;
  v_before public.availability_exceptions%rowtype;
  v_after public.availability_exceptions%rowtype;
begin
  if v_staff_id is null then raise exception 'Active staff access required'; end if;
  if not exists (select 1 from public.staff where id = v_staff_id and role = 'employee') then
    raise exception 'Employee access required';
  end if;
  if p_local_date is null
     or (p_is_full_day and p_kind <> 'unavailable')
     or (
       not p_is_full_day
       and (
         p_start_time is null
         or p_end_time is null
         or p_end_time <= p_start_time
       )
     ) then
    raise exception 'Date exception range is invalid';
  end if;

  if p_id is null then
    insert into public.availability_exceptions(
      staff_id, local_date, kind, start_time, end_time, is_full_day, note
    )
    values (
      v_staff_id, p_local_date, p_kind,
      case when p_is_full_day then null else p_start_time end,
      case when p_is_full_day then null else p_end_time end,
      p_is_full_day, nullif(trim(coalesce(p_note, '')), '')
    )
    returning * into v_after;
    v_id := v_after.id;
  else
    select * into v_before
    from public.availability_exceptions
    where id = p_id and staff_id = v_staff_id
    for update;
    if not found then raise exception 'Availability exception not found'; end if;

    update public.availability_exceptions
    set
      local_date = p_local_date,
      kind = p_kind,
      start_time = case when p_is_full_day then null else p_start_time end,
      end_time = case when p_is_full_day then null else p_end_time end,
      is_full_day = p_is_full_day,
      note = nullif(trim(coalesce(p_note, '')), '')
    where id = p_id
    returning * into v_after;
    v_id := v_after.id;
  end if;

  insert into public.roster_audit(
    actor_staff_id, action, subject_staff_id, entity_type, entity_id,
    before_data, after_data
  )
  values (
    v_staff_id,
    case when p_id is null then 'AVAILABILITY_CREATED' else 'AVAILABILITY_UPDATED' end,
    v_staff_id,
    'AVAILABILITY_EXCEPTION',
    v_id,
    case when p_id is null then '{}'::jsonb else jsonb_build_object(
      'local_date', v_before.local_date,
      'kind', v_before.kind,
      'start_time', v_before.start_time,
      'end_time', v_before.end_time,
      'is_full_day', v_before.is_full_day
    ) end,
    jsonb_build_object(
      'local_date', v_after.local_date,
      'kind', v_after.kind,
      'start_time', v_after.start_time,
      'end_time', v_after.end_time,
      'is_full_day', v_after.is_full_day
    )
  );
  return v_id;
end;
$$;

create or replace function public.delete_availability_exception(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff_id uuid := public.current_staff_id();
  v_before public.availability_exceptions%rowtype;
begin
  delete from public.availability_exceptions
  where id = p_id
    and staff_id = v_staff_id
    and exists (
      select 1 from public.staff
      where id = v_staff_id and role = 'employee'
    )
  returning * into v_before;
  if not found then raise exception 'Availability exception not found'; end if;

  insert into public.roster_audit(
    actor_staff_id, action, subject_staff_id, entity_type, entity_id, before_data
  )
  values (
    v_staff_id, 'AVAILABILITY_REMOVED', v_staff_id,
    'AVAILABILITY_EXCEPTION', p_id,
    jsonb_build_object(
      'local_date', v_before.local_date,
      'kind', v_before.kind,
      'start_time', v_before.start_time,
      'end_time', v_before.end_time,
      'is_full_day', v_before.is_full_day
    )
  );
end;
$$;

create or replace function public.supervisor_audit_history(
  p_action text default null,
  p_entity_type text default null,
  p_limit integer default 200
)
returns table (
  audit_id bigint,
  actor_staff_id uuid,
  actor_name text,
  action text,
  entity_type text,
  entity_id uuid,
  shift_id uuid,
  assignment_id uuid,
  release_request_id uuid,
  subject_staff_id uuid,
  subject_name text,
  reason text,
  before_data jsonb,
  after_data jsonb,
  details jsonb,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_supervisor();
  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'Audit history limit must be between 1 and 500';
  end if;

  return query
    select
      audit.id,
      audit.actor_staff_id,
      actor.full_name,
      audit.action,
      audit.entity_type,
      audit.entity_id,
      audit.shift_id,
      audit.assignment_id,
      audit.release_request_id,
      audit.subject_staff_id,
      subject.full_name,
      audit.reason,
      audit.before_data,
      audit.after_data,
      audit.details,
      audit.created_at
    from public.roster_audit audit
    join public.staff actor on actor.id = audit.actor_staff_id
    left join public.staff subject on subject.id = audit.subject_staff_id
    where (p_action is null or audit.action = p_action)
      and (p_entity_type is null or audit.entity_type = p_entity_type)
    order by audit.created_at desc, audit.id desc
    limit p_limit;
end;
$$;

revoke all on function public.normalise_roster_audit() from public, anon, authenticated;
revoke all on function public.protect_release_request_invariants() from public, anon, authenticated;
revoke all on function public.lock_release_workflow(uuid)
  from public, anon, authenticated;
revoke all on function public.release_request_submission_open(uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function public.cancel_pending_release_requests_for_assignment(uuid, uuid, text, uuid)
  from public, anon, authenticated;

revoke all on function public.submit_release_request(uuid, text, text) from public, anon;
revoke all on function public.employee_release_request_assignments() from public, anon;
revoke all on function public.employee_release_requests() from public, anon;
revoke all on function public.supervisor_release_requests(public.release_request_status) from public, anon;
revoke all on function public.release_request_candidates(uuid) from public, anon;
revoke all on function public.reject_release_request(uuid, text) from public, anon;
revoke all on function public.approve_release_request_remove(uuid, text) from public, anon;
revoke all on function public.approve_release_request_replace(
  uuid, uuid, boolean, text, text
) from public, anon;
revoke all on function public.supervisor_audit_history(text, text, integer) from public, anon;

grant execute on function public.submit_release_request(uuid, text, text) to authenticated;
grant execute on function public.employee_release_request_assignments() to authenticated;
grant execute on function public.employee_release_requests() to authenticated;
grant execute on function public.supervisor_release_requests(public.release_request_status) to authenticated;
grant execute on function public.release_request_candidates(uuid) to authenticated;
grant execute on function public.reject_release_request(uuid, text) to authenticated;
grant execute on function public.approve_release_request_remove(uuid, text) to authenticated;
grant execute on function public.approve_release_request_replace(
  uuid, uuid, boolean, text, text
) to authenticated;
grant execute on function public.supervisor_audit_history(text, text, integer) to authenticated;

revoke insert, update, delete on public.roster_audit from authenticated;
