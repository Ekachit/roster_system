create table public.shift_acknowledgements (
  assignment_id uuid primary key references public.shift_assignments(id) on delete restrict,
  staff_id uuid not null references public.staff(id) on delete restrict,
  acknowledged_at timestamptz not null default now()
);

create index shift_acknowledgements_staff_idx
  on public.shift_acknowledgements(staff_id, acknowledged_at);

alter table public.shift_acknowledgements enable row level security;

create policy shifts_employee_own_published on public.shifts for select to authenticated
using (
  status = 'PUBLISHED'
  and exists (
    select 1
    from public.shift_assignments assignment
    where assignment.shift_id = shifts.id
      and assignment.staff_id = public.current_staff_id()
      and assignment.removed_at is null
  )
);

create policy acknowledgements_supervisor_select on public.shift_acknowledgements
for select to authenticated using (public.is_supervisor());

create policy acknowledgements_employee_own_select on public.shift_acknowledgements
for select to authenticated using (staff_id = public.current_staff_id());

create or replace function public.employee_schedule()
returns table (
  assignment_id uuid,
  shift_id uuid,
  shift_title text,
  local_date date,
  start_time time,
  end_time time,
  location_name text,
  activity_name text,
  notes text,
  assignment_kind public.assignment_kind,
  assignment_status text,
  acknowledged_at timestamptz,
  colleague_names text[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    own.id,
    shift.id,
    shift.shift_title,
    shift.local_date,
    shift.start_time,
    shift.end_time,
    location.name,
    activity.name,
    shift.notes,
    own.assignment_kind,
    'ASSIGNED'::text,
    acknowledgement.acknowledged_at,
    coalesce((
      select array_agg(colleague.full_name order by colleague.full_name)
      from public.shift_assignments other
      join public.staff colleague on colleague.id = other.staff_id
      where other.shift_id = shift.id
        and other.removed_at is null
        and other.staff_id <> own.staff_id
    ), array[]::text[])
  from public.shift_assignments own
  join public.shifts shift on shift.id = own.shift_id
  join public.locations location on location.id = shift.location_id
  join public.activity_types activity on activity.id = shift.activity_type_id
  left join public.shift_acknowledgements acknowledgement on acknowledgement.assignment_id = own.id
  where own.staff_id = public.current_staff_id()
    and own.removed_at is null
    and shift.status = 'PUBLISHED'
  order by shift.local_date, shift.start_time, shift.id
$$;

create or replace function public.acknowledge_assignment(p_assignment_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff_id uuid := public.current_staff_id();
  v_shift_id uuid;
  v_acknowledged_at timestamptz;
begin
  if v_staff_id is null then
    raise exception 'Active employee access required' using errcode = '42501';
  end if;

  select assignment.shift_id
  into v_shift_id
  from public.shift_assignments assignment
  join public.shifts shift on shift.id = assignment.shift_id
  where assignment.id = p_assignment_id
    and assignment.staff_id = v_staff_id
    and assignment.removed_at is null
    and shift.status = 'PUBLISHED'
  for update of assignment;

  if v_shift_id is null then
    raise exception 'Active published assignment not found' using errcode = '42501';
  end if;

  insert into public.shift_acknowledgements(assignment_id, staff_id)
  values (p_assignment_id, v_staff_id)
  on conflict (assignment_id) do nothing
  returning acknowledged_at into v_acknowledged_at;

  if v_acknowledged_at is not null then
    insert into public.roster_audit(
      actor_staff_id, action, shift_id, assignment_id, subject_staff_id
    )
    values (
      v_staff_id, 'ASSIGNMENT_ACKNOWLEDGED', v_shift_id, p_assignment_id, v_staff_id
    );
  else
    select acknowledged_at into v_acknowledged_at
    from public.shift_acknowledgements
    where assignment_id = p_assignment_id;
  end if;

  return v_acknowledged_at;
end;
$$;

create or replace function public.reset_acknowledgements_on_unpublish()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reset_count integer;
begin
  if old.status = 'PUBLISHED' and new.status = 'DRAFT' then
    delete from public.shift_acknowledgements acknowledgement
    using public.shift_assignments assignment
    where acknowledgement.assignment_id = assignment.id
      and assignment.shift_id = new.id;
    get diagnostics v_reset_count = row_count;

    if v_reset_count > 0 then
      insert into public.roster_audit(actor_staff_id, action, shift_id, details)
      values (
        new.updated_by,
        'ASSIGNMENT_ACKNOWLEDGEMENTS_RESET',
        new.id,
        jsonb_build_object('count', v_reset_count, 'reason', 'shift_unpublished')
      );
    end if;
  end if;
  return new;
end;
$$;

create trigger shifts_reset_acknowledgements_after_unpublish
after update of status on public.shifts
for each row execute function public.reset_acknowledgements_on_unpublish();

revoke all on public.shift_acknowledgements from anon, authenticated;
grant select on public.shift_acknowledgements to authenticated;

revoke all on function public.employee_schedule() from public, anon;
revoke all on function public.acknowledge_assignment(uuid) from public, anon;
revoke all on function public.reset_acknowledgements_on_unpublish() from public, anon, authenticated;
grant execute on function public.employee_schedule() to authenticated;
grant execute on function public.acknowledge_assignment(uuid) to authenticated;
