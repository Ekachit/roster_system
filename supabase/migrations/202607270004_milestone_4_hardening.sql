drop policy if exists shifts_employee_own_published on public.shifts;
drop policy if exists assignments_employee_published_own on public.shift_assignments;

revoke select on public.shifts, public.shift_assignments from authenticated;

create or replace function public.supervisor_roster_shifts(
  p_start_date date default null,
  p_end_date date default null
)
returns setof public.shifts
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_supervisor();
  return query
    select shift.*
    from public.shifts shift
    where (p_start_date is null or shift.local_date >= p_start_date)
      and (p_end_date is null or shift.local_date <= p_end_date)
    order by shift.local_date, shift.start_time, shift.id;
end;
$$;

create or replace function public.supervisor_roster_assignments()
returns setof public.shift_assignments
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_supervisor();
  return query
    select assignment.*
    from public.shift_assignments assignment
    order by assignment.assigned_at, assignment.id;
end;
$$;

drop function public.employee_schedule();

create function public.employee_schedule()
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
  shift_status public.shift_status,
  acknowledged_at timestamptz,
  cancelled_at timestamptz,
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
    case
      when shift.status = 'CANCELLED' then 'CANCELLED'
      when own.removed_at is not null then 'REMOVED'
      else 'ASSIGNED'
    end,
    shift.status,
    acknowledgement.acknowledged_at,
    shift.cancelled_at,
    coalesce((
      select array_agg(colleague.full_name order by colleague.full_name)
      from public.shift_assignments other
      join public.staff colleague on colleague.id = other.staff_id
      where other.shift_id = shift.id
        and other.staff_id <> own.staff_id
        and (
          (shift.status = 'PUBLISHED' and other.removed_at is null)
          or (shift.status = 'CANCELLED' and other.assigned_at <= shift.cancelled_at)
        )
    ), array[]::text[])
  from public.shift_assignments own
  join public.shifts shift on shift.id = own.shift_id
  join public.locations location on location.id = shift.location_id
  join public.activity_types activity on activity.id = shift.activity_type_id
  left join public.shift_acknowledgements acknowledgement on acknowledgement.assignment_id = own.id
  where own.staff_id = public.current_staff_id()
    and (
      (shift.status = 'PUBLISHED' and own.removed_at is null)
      or shift.status = 'CANCELLED'
    )
  order by shift.local_date, shift.start_time, shift.id, own.assigned_at desc
$$;

revoke all on function public.supervisor_roster_shifts(date, date) from public, anon;
revoke all on function public.supervisor_roster_assignments() from public, anon;
revoke all on function public.employee_schedule() from public, anon;
grant execute on function public.supervisor_roster_shifts(date, date) to authenticated;
grant execute on function public.supervisor_roster_assignments() to authenticated;
grant execute on function public.employee_schedule() to authenticated;
