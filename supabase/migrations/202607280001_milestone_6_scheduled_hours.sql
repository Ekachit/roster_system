create index shifts_reporting_idx
  on public.shifts(local_date, status, location_id, activity_type_id);

create or replace function public.scheduled_hours_report(
  p_start_date date,
  p_end_date date,
  p_staff_id uuid default null,
  p_location_id uuid default null,
  p_activity_type_id uuid default null
)
returns table (
  assignment_id uuid,
  staff_id uuid,
  employee_name text,
  employee_email text,
  shift_id uuid,
  local_date date,
  start_time time,
  end_time time,
  duration_minutes integer,
  location_id uuid,
  location_name text,
  activity_type_id uuid,
  activity_name text,
  shift_status public.shift_status,
  assignment_status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_supervisor();

  if p_start_date is null or p_end_date is null then
    raise exception 'Start date and end date are required'
      using errcode = '22004';
  end if;

  if p_start_date > p_end_date then
    raise exception 'Start date must be on or before end date'
      using errcode = '22007';
  end if;

  return query
    select
      assignment.id,
      employee.id,
      employee.full_name,
      employee.email::text,
      shift.id,
      shift.local_date,
      shift.start_time,
      shift.end_time,
      round(
        extract(epoch from (
          ((shift.local_date + shift.end_time) at time zone 'Australia/Melbourne')
          - ((shift.local_date + shift.start_time) at time zone 'Australia/Melbourne')
        )) / 60
      )::integer,
      location.id,
      location.name::text,
      activity.id,
      activity.name::text,
      shift.status,
      'ASSIGNED'::text
    from public.shift_assignments assignment
    join public.shifts shift on shift.id = assignment.shift_id
    join public.staff employee on employee.id = assignment.staff_id
    join public.locations location on location.id = shift.location_id
    join public.activity_types activity on activity.id = shift.activity_type_id
    where shift.status = 'PUBLISHED'
      and assignment.removed_at is null
      and shift.local_date between p_start_date and p_end_date
      and (p_staff_id is null or employee.id = p_staff_id)
      and (p_location_id is null or location.id = p_location_id)
      and (p_activity_type_id is null or activity.id = p_activity_type_id)
    order by
      lower(employee.full_name),
      employee.id,
      shift.local_date,
      shift.start_time,
      shift.id,
      assignment.id;
end;
$$;

revoke all on function public.scheduled_hours_report(
  date, date, uuid, uuid, uuid
) from public, anon;

grant execute on function public.scheduled_hours_report(
  date, date, uuid, uuid, uuid
) to authenticated;
