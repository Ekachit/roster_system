-- Milestone 7 final hardening.
-- Keep audit history append-only even for privileged SQL paths, constrain
-- browser-controlled text at the database boundary, and remove an obsolete
-- metadata helper from the browser contract.

alter table public.staff
  add constraint staff_full_name_length
  check (char_length(full_name) <= 120),
  add constraint staff_email_length
  check (char_length(email::text) <= 320);

alter table public.staff_private_notes
  add constraint staff_private_notes_length
  check (note is null or char_length(note) <= 2000);

alter table public.locations
  add constraint locations_name_length
  check (char_length(name::text) <= 100);

alter table public.activity_types
  add constraint activity_types_name_length
  check (char_length(name::text) <= 100);

alter table public.recurring_availability
  add constraint recurring_availability_note_length
  check (note is null or char_length(note) <= 500);

alter table public.availability_exceptions
  add constraint availability_exceptions_note_length
  check (note is null or char_length(note) <= 500);

alter table public.shifts
  add constraint shifts_title_length
  check (char_length(shift_title) <= 160),
  add constraint shifts_notes_length
  check (notes is null or char_length(notes) <= 2000);

alter table public.shift_assignments
  add constraint shift_assignments_override_reason_length
  check (override_reason is null or char_length(override_reason) <= 1000),
  add constraint shift_assignments_removal_reason_length
  check (removal_reason is null or char_length(removal_reason) <= 1000);

alter table public.release_requests
  add constraint release_requests_reason_length
  check (char_length(reason) <= 200),
  add constraint release_requests_note_length
  check (note is null or char_length(note) <= 1000),
  add constraint release_requests_resolution_reason_length
  check (resolution_reason is null or char_length(resolution_reason) <= 1000);

alter table public.roster_audit
  add constraint roster_audit_reason_length
  check (reason is null or char_length(reason) <= 2000);

create or replace function public.protect_assigned_shift_material_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (
    old.local_date is distinct from new.local_date
    or old.start_time is distinct from new.start_time
    or old.end_time is distinct from new.end_time
    or old.location_id is distinct from new.location_id
    or old.activity_type_id is distinct from new.activity_type_id
  ) and exists (
    select 1
    from public.shift_assignments assignment
    where assignment.shift_id = old.id
      and assignment.removed_at is null
  ) then
    raise exception
      'Remove or replace active assignments before changing shift date, time, location, or activity';
  end if;
  return new;
end;
$$;

create trigger shifts_protect_assigned_material_fields
before update of local_date, start_time, end_time, location_id, activity_type_id
on public.shifts
for each row execute function public.protect_assigned_shift_material_fields();

revoke all on function public.protect_assigned_shift_material_fields()
from public, anon, authenticated;

create or replace function public.prevent_roster_audit_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Roster audit history is append-only'
    using errcode = '42501';
end;
$$;

create trigger roster_audit_prevent_mutation
before update or delete on public.roster_audit
for each row execute function public.prevent_roster_audit_mutation();

revoke all on function public.prevent_roster_audit_mutation()
from public, anon, authenticated;

-- The employee base-table policies that used this helper were removed in the
-- Milestone 4 hardening migration. No browser query needs this one-bit shift
-- status probe now.
revoke execute on function public.is_shift_published(uuid) from authenticated;
