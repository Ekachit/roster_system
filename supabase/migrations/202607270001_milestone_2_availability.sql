create type public.availability_kind as enum ('available', 'unavailable');

create table public.recurring_availability (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  start_time time not null,
  end_time time not null,
  effective_start_date date not null,
  effective_end_date date,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint recurring_time_order check (end_time > start_time),
  constraint recurring_effective_order check (
    effective_end_date is null or effective_end_date >= effective_start_date
  )
);

create table public.availability_exceptions (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff(id) on delete cascade,
  local_date date not null,
  kind public.availability_kind not null,
  start_time time,
  end_time time,
  is_full_day boolean not null default false,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint exception_interval_shape check (
    (is_full_day and kind = 'unavailable' and start_time is null and end_time is null)
    or
    (not is_full_day and start_time is not null and end_time is not null and end_time > start_time)
  )
);

create index recurring_availability_staff_weekday_idx
  on public.recurring_availability(staff_id, weekday);
create index availability_exceptions_staff_date_idx
  on public.availability_exceptions(staff_id, local_date);

create trigger recurring_availability_updated_at
before update on public.recurring_availability
for each row execute function public.set_updated_at();

create trigger availability_exceptions_updated_at
before update on public.availability_exceptions
for each row execute function public.set_updated_at();

create or replace function public.protect_availability_overlap()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_table_name = 'recurring_availability' then
    perform pg_advisory_xact_lock(hashtextextended(
      'recurring:' || new.staff_id::text || ':' || new.weekday::text, 0
    ));
    if exists (
      select 1
      from public.recurring_availability r
      where r.staff_id = new.staff_id
        and r.weekday = new.weekday
        and r.id <> new.id
        and r.start_time < new.end_time
        and new.start_time < r.end_time
        and r.effective_start_date <= coalesce(new.effective_end_date, 'infinity'::date)
        and new.effective_start_date <= coalesce(r.effective_end_date, 'infinity'::date)
    ) then
      raise exception 'Recurring availability overlaps an existing rule';
    end if;
  else
    perform pg_advisory_xact_lock(hashtextextended(
      'exception:' || new.staff_id::text || ':' || new.local_date::text, 0
    ));
    if exists (
      select 1
      from public.availability_exceptions e
      where e.staff_id = new.staff_id
        and e.local_date = new.local_date
        and e.id <> new.id
        and (
          e.is_full_day or new.is_full_day
          or (e.start_time < new.end_time and new.start_time < e.end_time)
        )
    ) then
      raise exception 'Availability exception overlaps an existing exception';
    end if;
  end if;
  return new;
end;
$$;

create trigger recurring_availability_no_overlap
before insert or update on public.recurring_availability
for each row execute function public.protect_availability_overlap();

create trigger availability_exceptions_no_overlap
before insert or update on public.availability_exceptions
for each row execute function public.protect_availability_overlap();

alter table public.recurring_availability enable row level security;
alter table public.availability_exceptions enable row level security;

create policy recurring_own_select on public.recurring_availability
for select to authenticated using (staff_id = public.current_staff_id());
create policy recurring_supervisor_select on public.recurring_availability
for select to authenticated using (public.is_supervisor());
create policy exceptions_own_select on public.availability_exceptions
for select to authenticated using (staff_id = public.current_staff_id());
create policy exceptions_supervisor_select on public.availability_exceptions
for select to authenticated using (public.is_supervisor());

create or replace function public.save_recurring_availability(
  p_id uuid,
  p_weekday smallint,
  p_start_time time,
  p_end_time time,
  p_effective_start_date date,
  p_effective_end_date date,
  p_note text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_staff_id uuid := public.current_staff_id();
  v_id uuid;
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
      staff_id, weekday, start_time, end_time, effective_start_date, effective_end_date, note
    ) values (
      v_staff_id, p_weekday, p_start_time, p_end_time, p_effective_start_date,
      p_effective_end_date, nullif(trim(p_note), '')
    ) returning id into v_id;
  else
    update public.recurring_availability
    set weekday = p_weekday, start_time = p_start_time, end_time = p_end_time,
        effective_start_date = p_effective_start_date,
        effective_end_date = p_effective_end_date, note = nullif(trim(p_note), '')
    where id = p_id and staff_id = v_staff_id
    returning id into v_id;
    if v_id is null then raise exception 'Recurring availability not found'; end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.delete_recurring_availability(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.recurring_availability
  where id = p_id and staff_id = public.current_staff_id()
    and exists (
      select 1 from public.staff s
      where s.id = public.current_staff_id() and s.role = 'employee'
    );
  if not found then raise exception 'Recurring availability not found'; end if;
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
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_staff_id uuid := public.current_staff_id();
  v_id uuid;
begin
  if v_staff_id is null then raise exception 'Active staff access required'; end if;
  if not exists (select 1 from public.staff where id = v_staff_id and role = 'employee') then
    raise exception 'Employee access required';
  end if;
  if p_local_date is null
     or (p_is_full_day and p_kind <> 'unavailable')
     or (not p_is_full_day and (
       p_start_time is null or p_end_time is null or p_end_time <= p_start_time
     )) then
    raise exception 'Date exception range is invalid';
  end if;
  if p_id is null then
    insert into public.availability_exceptions(
      staff_id, local_date, kind, start_time, end_time, is_full_day, note
    ) values (
      v_staff_id, p_local_date, p_kind,
      case when p_is_full_day then null else p_start_time end,
      case when p_is_full_day then null else p_end_time end,
      p_is_full_day, nullif(trim(p_note), '')
    ) returning id into v_id;
  else
    update public.availability_exceptions
    set local_date = p_local_date, kind = p_kind,
        start_time = case when p_is_full_day then null else p_start_time end,
        end_time = case when p_is_full_day then null else p_end_time end,
        is_full_day = p_is_full_day, note = nullif(trim(p_note), '')
    where id = p_id and staff_id = v_staff_id
    returning id into v_id;
    if v_id is null then raise exception 'Availability exception not found'; end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.delete_availability_exception(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.availability_exceptions
  where id = p_id and staff_id = public.current_staff_id()
    and exists (
      select 1 from public.staff s
      where s.id = public.current_staff_id() and s.role = 'employee'
    );
  if not found then raise exception 'Availability exception not found'; end if;
end;
$$;

revoke all on public.recurring_availability, public.availability_exceptions from anon;
revoke all on public.recurring_availability, public.availability_exceptions from authenticated;
grant select on public.recurring_availability, public.availability_exceptions to authenticated;

revoke all on function public.save_recurring_availability(uuid, smallint, time, time, date, date, text) from public, anon;
revoke all on function public.delete_recurring_availability(uuid) from public, anon;
revoke all on function public.save_availability_exception(uuid, date, public.availability_kind, time, time, boolean, text) from public, anon;
revoke all on function public.delete_availability_exception(uuid) from public, anon;
revoke all on function public.protect_availability_overlap() from public, anon, authenticated;
grant execute on function public.save_recurring_availability(uuid, smallint, time, time, date, date, text) to authenticated;
grant execute on function public.delete_recurring_availability(uuid) to authenticated;
grant execute on function public.save_availability_exception(uuid, date, public.availability_kind, time, time, boolean, text) to authenticated;
grant execute on function public.delete_availability_exception(uuid) to authenticated;
