begin;
select plan(84);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  (
    '15000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm5.supervisor@example.test', '',
    now(), now(), now()
  ),
  (
    '15000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm5.employee.one@example.test', '',
    now(), now(), now()
  ),
  (
    '15000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm5.employee.two@example.test', '',
    now(), now(), now()
  ),
  (
    '15000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm5.employee.three@example.test', '',
    now(), now(), now()
  );

insert into public.staff(id, email, full_name, role, is_active) values
  (
    '25000000-0000-0000-0000-000000000001',
    'm5.supervisor@example.test', 'Synthetic M5 Supervisor', 'supervisor', true
  ),
  (
    '25000000-0000-0000-0000-000000000002',
    'm5.employee.one@example.test', 'Synthetic M5 Employee One', 'employee', true
  ),
  (
    '25000000-0000-0000-0000-000000000003',
    'm5.employee.two@example.test', 'Synthetic M5 Employee Two', 'employee', true
  ),
  (
    '25000000-0000-0000-0000-000000000004',
    'm5.employee.three@example.test', 'Synthetic M5 Employee Three', 'employee', true
  );

update auth.users
set email_confirmed_at = email_confirmed_at + interval '1 second'
where id::text like '15000000-%';

insert into public.staff_locations(staff_id, location_id)
select employee.id, location.id
from public.staff employee
cross join public.locations location
where employee.id in (
  '25000000-0000-0000-0000-000000000002',
  '25000000-0000-0000-0000-000000000003'
)
and location.name = 'Clayton';

insert into public.staff_activity_types(staff_id, activity_type_id)
select employee.id, activity.id
from public.staff employee
cross join public.activity_types activity
where employee.id in (
  '25000000-0000-0000-0000-000000000002',
  '25000000-0000-0000-0000-000000000003'
)
and activity.name = 'Training';

insert into public.recurring_availability(
  staff_id, weekday, start_time, end_time, effective_start_date
)
select employee.staff_id, weekday, '08:00', '17:00', '2026-01-01'
from (
  values
    ('25000000-0000-0000-0000-000000000002'::uuid),
    ('25000000-0000-0000-0000-000000000003'::uuid)
) employee(staff_id)
cross join generate_series(1, 7) weekday;

create or replace function public.m5_force_resolution_failure()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.resolution_reason like '%FORCE_ROLLBACK%' then
    raise exception 'forced release resolution failure';
  end if;
  return new;
end;
$$;

create trigger m5_force_resolution_failure
before update on public.release_requests
for each row execute function public.m5_force_resolution_failure();

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

create temp table m5_ids (
  key text primary key,
  id uuid not null
);
grant select, insert on m5_ids to authenticated;

insert into m5_ids values
  (
    'reject_shift',
    public.save_shift(
      null, 'Synthetic rejection shift', '2026-08-20', '09:00', '10:00',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, 'Release request test'
    )
  ),
  (
    'remove_shift',
    public.save_shift(
      null, 'Synthetic removal shift', '2026-08-21', '09:00', '10:00',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, null
    )
  ),
  (
    'replace_shift',
    public.save_shift(
      null, 'Synthetic replacement shift', '2026-08-22', '09:00', '10:00',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, null
    )
  ),
  (
    'rollback_shift',
    public.save_shift(
      null, 'Synthetic rollback shift', '2026-08-23', '09:00', '10:00',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, null
    )
  ),
  (
    'sync_remove_shift',
    public.save_shift(
      null, 'Synthetic direct removal shift', '2026-08-24', '09:00', '10:00',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, null
    )
  ),
  (
    'cancel_shift',
    public.save_shift(
      null, 'Synthetic cancellation shift', '2026-08-25', '09:00', '10:00',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, null
    )
  ),
  (
    'unpublish_shift',
    public.save_shift(
      null, 'Synthetic unpublication shift', '2026-08-26', '09:00', '10:00',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, null
    )
  ),
  (
    'direct_replace_shift',
    public.save_shift(
      null, 'Synthetic direct replacement shift', '2026-08-27', '09:00', '10:00',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, null
    )
  ),
  (
    'shadow_replace_shift',
    public.save_shift(
      null, 'Synthetic shadow replacement shift', '2026-08-28', '09:00', '10:00',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, null
    )
  ),
  (
    'during_shift',
    public.save_shift(
      null, 'Synthetic in-progress shift',
      (now() at time zone 'Australia/Melbourne')::date,
      '00:00', '23:59:59',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, null
    )
  ),
  (
    'ended_shift',
    public.save_shift(
      null, 'Synthetic ended shift',
      (now() at time zone 'Australia/Melbourne')::date - 1,
      '09:00', '10:00',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, null
    )
  );

insert into m5_ids values
  (
    'reject_assignment',
    public.assign_employee(
      (select id from m5_ids where key = 'reject_shift'),
      '25000000-0000-0000-0000-000000000002',
      'REGULAR', false, null
    )
  ),
  (
    'remove_assignment',
    public.assign_employee(
      (select id from m5_ids where key = 'remove_shift'),
      '25000000-0000-0000-0000-000000000002',
      'REGULAR', false, null
    )
  ),
  (
    'replace_assignment',
    public.assign_employee(
      (select id from m5_ids where key = 'replace_shift'),
      '25000000-0000-0000-0000-000000000002',
      'REGULAR', false, null
    )
  ),
  (
    'rollback_assignment',
    public.assign_employee(
      (select id from m5_ids where key = 'rollback_shift'),
      '25000000-0000-0000-0000-000000000002',
      'REGULAR', false, null
    )
  ),
  (
    'sync_remove_assignment',
    public.assign_employee(
      (select id from m5_ids where key = 'sync_remove_shift'),
      '25000000-0000-0000-0000-000000000002',
      'REGULAR', false, null
    )
  ),
  (
    'cancel_assignment',
    public.assign_employee(
      (select id from m5_ids where key = 'cancel_shift'),
      '25000000-0000-0000-0000-000000000002',
      'REGULAR', false, null
    )
  ),
  (
    'unpublish_assignment',
    public.assign_employee(
      (select id from m5_ids where key = 'unpublish_shift'),
      '25000000-0000-0000-0000-000000000002',
      'REGULAR', false, null
    )
  ),
  (
    'direct_replace_assignment',
    public.assign_employee(
      (select id from m5_ids where key = 'direct_replace_shift'),
      '25000000-0000-0000-0000-000000000002',
      'REGULAR', false, null
    )
  ),
  (
    'shadow_replace_assignment',
    public.assign_employee(
      (select id from m5_ids where key = 'shadow_replace_shift'),
      '25000000-0000-0000-0000-000000000002',
      'SHADOWING', false, null
    )
  ),
  (
    'during_assignment',
    public.assign_employee(
      (select id from m5_ids where key = 'during_shift'),
      '25000000-0000-0000-0000-000000000002',
      'REGULAR', true, 'Synthetic in-progress coverage override'
    )
  ),
  (
    'ended_assignment',
    public.assign_employee(
      (select id from m5_ids where key = 'ended_shift'),
      '25000000-0000-0000-0000-000000000002',
      'REGULAR', false, null
    )
  );

select public.set_shift_status((select id from m5_ids where key = 'reject_shift'), 'PUBLISHED', null);
select public.set_shift_status((select id from m5_ids where key = 'remove_shift'), 'PUBLISHED', null);
select public.set_shift_status((select id from m5_ids where key = 'replace_shift'), 'PUBLISHED', null);
select public.set_shift_status((select id from m5_ids where key = 'rollback_shift'), 'PUBLISHED', null);
select public.set_shift_status((select id from m5_ids where key = 'sync_remove_shift'), 'PUBLISHED', null);
select public.set_shift_status((select id from m5_ids where key = 'cancel_shift'), 'PUBLISHED', null);
select public.set_shift_status((select id from m5_ids where key = 'unpublish_shift'), 'PUBLISHED', null);
select public.set_shift_status((select id from m5_ids where key = 'direct_replace_shift'), 'PUBLISHED', null);
select public.set_shift_status((select id from m5_ids where key = 'shadow_replace_shift'), 'PUBLISHED', null);
select public.set_shift_status((select id from m5_ids where key = 'during_shift'), 'PUBLISHED', null);
select public.set_shift_status((select id from m5_ids where key = 'ended_shift'), 'PUBLISHED', null);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select lives_ok(
  $$insert into m5_ids values (
    'reject_request',
    public.submit_release_request(
      (select id from m5_ids where key = 'reject_assignment'),
      'Personal commitment',
      'Synthetic explanatory note'
    )
  )$$,
  'assigned employee can submit a release request before shift start'
);

select is(
  (
    select count(*)
    from public.employee_release_request_assignments()
    where assignment_id = (select id from m5_ids where key = 'during_assignment')
  ),
  1::bigint,
  'database requestable-assignment projection includes an in-progress shift'
);

select is(
  (
    select count(*)
    from public.employee_release_request_assignments()
    where assignment_id = (select id from m5_ids where key = 'ended_assignment')
  ),
  0::bigint,
  'database requestable-assignment projection excludes a shift after its end time'
);

select lives_ok(
  $$insert into m5_ids values (
    'during_request',
    public.submit_release_request(
      (select id from m5_ids where key = 'during_assignment'),
      'Became sick during shift',
      'Needs to leave early'
    )
  )$$,
  'employee can submit while the shift is in progress'
);

select throws_like(
  $$select public.submit_release_request(
    (select id from m5_ids where key = 'ended_assignment'),
    'Too late',
    null
  )$$,
  'Active published assignment not found',
  'submission after the Melbourne-local shift end is denied'
);

reset role;
select is(
  public.release_request_submission_open(
    (select id from m5_ids where key = 'during_shift'),
    (
      select (shift.local_date + shift.end_time) at time zone 'Australia/Melbourne'
      from public.shifts shift
      where shift.id = (select id from m5_ids where key = 'during_shift')
    )
  ),
  false,
  'submission is closed exactly at the Melbourne-local shift end instant'
);
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select ok(
  (
    select status = 'PENDING'
      and reason = 'Personal commitment'
      and note = 'Synthetic explanatory note'
      and submitted_at is not null
    from public.employee_release_requests()
    where request_id = (select id from m5_ids where key = 'reject_request')
  ),
  'employee request projection includes reason, optional note, timestamp, and pending status'
);

select is(
  (
    select count(*)
    from public.employee_schedule()
    where assignment_id = (select id from m5_ids where key = 'reject_assignment')
  ),
  1::bigint,
  'submitting a release request does not remove the assignment'
);

select throws_like(
  $$select public.submit_release_request(
    (select id from m5_ids where key = 'reject_assignment'),
    'Duplicate',
    null
  )$$,
  'A pending release request already exists%',
  'duplicate pending request is denied'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000003',
  true
);

select is(
  (select count(*) from public.employee_release_requests()),
  0::bigint,
  'employee can read only their own release requests'
);

select throws_like(
  $$select public.submit_release_request(
    (select id from m5_ids where key = 'reject_assignment'),
    'Not my assignment',
    null
  )$$,
  'Active published assignment not found',
  'request by an unassigned employee is denied'
);

select throws_like(
  $$select public.reject_release_request(
    (select id from m5_ids where key = 'reject_request'),
    'Forbidden'
  )$$,
  'Supervisor access required',
  'employee cannot reject a release request'
);

select throws_like(
  $$select public.approve_release_request_remove(
    (select id from m5_ids where key = 'reject_request'),
    'Forbidden'
  )$$,
  'Supervisor access required',
  'employee cannot approve a release request'
);

select throws_like(
  $$select * from public.supervisor_audit_history(null, null, 100)$$,
  'Supervisor access required',
  'employee cannot read supervisor audit history'
);

select throws_like(
  $$select public.release_request_submission_open(
    (select id from m5_ids where key = 'reject_shift'),
    now()
  )$$,
  'permission denied for function release_request_submission_open',
  'employee cannot execute the protected release-window helper'
);

select throws_like(
  $$insert into public.roster_audit(
    actor_staff_id, action
  ) values (
    '25000000-0000-0000-0000-000000000003',
    'FORGED'
  )$$,
  'permission denied for table roster_audit',
  'employee cannot insert audit records'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

select is(
  (
    select count(*)
    from public.supervisor_release_requests('PENDING')
    where request_id = (select id from m5_ids where key = 'reject_request')
  ),
  1::bigint,
  'supervisor pending queue includes the request'
);

select ok(
  (
    select shift_title = 'Synthetic rejection shift'
      and employee_name = 'Synthetic M5 Employee One'
      and assignment_active
      and shift_status = 'PUBLISHED'
    from public.supervisor_release_requests('PENDING')
    where request_id = (select id from m5_ids where key = 'reject_request')
  ),
  'supervisor request projection includes employee and related shift details'
);

select ok(
  (
    select conflicts @> '[{"code":"LOCATION_NOT_ELIGIBLE"}]'::jsonb
      and conflicts @> '[{"code":"ACTIVITY_NOT_ELIGIBLE"}]'::jsonb
    from public.release_request_candidates(
      (select id from m5_ids where key = 'reject_request')
    )
    where staff_id = '25000000-0000-0000-0000-000000000004'
  ),
  'replacement candidates include database conflict reasons'
);

select lives_ok(
  $$select public.reject_release_request(
    (select id from m5_ids where key = 'reject_request'),
    'Coverage cannot be changed'
  )$$,
  'supervisor can reject with a reason'
);

select is(
  (
    select status
    from public.supervisor_release_requests(null)
    where request_id = (select id from m5_ids where key = 'reject_request')
  ),
  'REJECTED'::public.release_request_status,
  'rejection resolves the request as rejected'
);

select is(
  (
    select count(*)
    from public.supervisor_roster_assignments()
    where id = (select id from m5_ids where key = 'reject_assignment')
      and removed_at is null
  ),
  1::bigint,
  'rejection retains the active assignment'
);

select is(
  (
    select count(*)
    from public.roster_audit
    where action = 'RELEASE_REQUEST_REJECTED'
      and release_request_id = (select id from m5_ids where key = 'reject_request')
      and reason = 'Coverage cannot be changed'
  ),
  1::bigint,
  'rejection audit records actor, request, and reason'
);

reset role;
select throws_like(
  $$update public.release_requests
    set resolution_reason = 'Attempted terminal mutation'
    where id = (select id from m5_ids where key = 'reject_request')$$,
  'Only pending release requests can be resolved',
  'terminal release-request statuses are immutable'
);
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select lives_ok(
  $$select public.acknowledge_assignment(
    (select id from m5_ids where key = 'remove_assignment')
  )$$,
  'employee can acknowledge before requesting release'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

select is(
  (
    select count(*) from public.roster_audit
    where action = 'ASSIGNMENT_ACKNOWLEDGED'
      and assignment_id = (select id from m5_ids where key = 'remove_assignment')
  ),
  1::bigint,
  'acknowledgement remains covered by audit history'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select lives_ok(
  $$insert into m5_ids values (
    'remove_request',
    public.submit_release_request(
      (select id from m5_ids where key = 'remove_assignment'),
      'Appointment',
      null
    )
  )$$,
  'employee can submit request for removal approval'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

select lives_ok(
  $$select public.approve_release_request_remove(
    (select id from m5_ids where key = 'remove_request'),
    'Approved without replacement'
  )$$,
  'supervisor can approve by removing the employee'
);

select is(
  (
    select status
    from public.supervisor_release_requests(null)
    where request_id = (select id from m5_ids where key = 'remove_request')
  ),
  'APPROVED'::public.release_request_status,
  'removal approval resolves the request'
);

select is(
  (
    select count(*)
    from public.supervisor_roster_assignments()
    where id = (select id from m5_ids where key = 'remove_assignment')
      and removed_at is not null
      and removal_reason = 'Approved without replacement'
  ),
  1::bigint,
  'removal approval historically closes the original assignment'
);

select is(
  (
    select count(*) from public.roster_audit
    where action = 'RELEASE_REQUEST_APPROVED'
      and release_request_id = (select id from m5_ids where key = 'remove_request')
  ),
  1::bigint,
  'removal approval creates request audit'
);

select is(
  (
    select count(*) from public.roster_audit
    where action = 'EMPLOYEE_REMOVED'
      and assignment_id = (select id from m5_ids where key = 'remove_assignment')
  ),
  1::bigint,
  'removal approval creates assignment removal audit'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select is(
  (
    select count(*) from public.employee_schedule()
    where assignment_id = (select id from m5_ids where key = 'remove_assignment')
  ),
  0::bigint,
  'removed assignment leaves the active employee schedule'
);

select lives_ok(
  $$insert into m5_ids values (
    'replace_request',
    public.submit_release_request(
      (select id from m5_ids where key = 'replace_assignment'),
      'Unable to attend',
      'Replacement requested'
    )
  )$$,
  'employee can submit request for replacement approval'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

select lives_ok(
  $$insert into m5_ids values (
    'replacement_assignment',
    public.approve_release_request_replace(
      (select id from m5_ids where key = 'replace_request'),
      '25000000-0000-0000-0000-000000000003',
      false,
      null,
      'Approved with replacement'
    )
  )$$,
  'supervisor can approve and replace in one workflow'
);

select ok(
  (
    select status = 'APPROVED'
      and replacement_assignment_id = (
        select id from m5_ids where key = 'replacement_assignment'
      )
    from public.supervisor_release_requests(null)
    where request_id = (select id from m5_ids where key = 'replace_request')
  ),
  'replacement approval resolves and links the request'
);

select ok(
  (
    select removed_at is not null
      and replaced_by_assignment_id = (
        select id from m5_ids where key = 'replacement_assignment'
      )
    from public.supervisor_roster_assignments()
    where id = (select id from m5_ids where key = 'replace_assignment')
  ),
  'replacement historically closes and links the original assignment'
);

select ok(
  (
    select staff_id = '25000000-0000-0000-0000-000000000003'
      and removed_at is null
    from public.supervisor_roster_assignments()
    where id = (select id from m5_ids where key = 'replacement_assignment')
  ),
  'replacement creates the new active assignment'
);

select is(
  (
    select count(*) from public.roster_audit
    where action = 'EMPLOYEE_ASSIGNED'
      and assignment_id = (select id from m5_ids where key = 'replacement_assignment')
  ),
  1::bigint,
  'replacement audits assignment creation'
);

select is(
  (
    select count(*) from public.roster_audit
    where action = 'EMPLOYEE_REMOVED'
      and assignment_id = (select id from m5_ids where key = 'replace_assignment')
  ),
  1::bigint,
  'replacement audits original assignment removal'
);

select is(
  (
    select count(*) from public.roster_audit
    where action = 'EMPLOYEE_REPLACED'
      and assignment_id = (select id from m5_ids where key = 'replace_assignment')
  ),
  1::bigint,
  'replacement audits the replacement relationship'
);

select is(
  (
    select count(*) from public.roster_audit
    where action = 'RELEASE_REQUEST_APPROVED'
      and release_request_id = (select id from m5_ids where key = 'replace_request')
  ),
  1::bigint,
  'replacement audits release approval'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select lives_ok(
  $$insert into m5_ids values (
    'rollback_request',
    public.submit_release_request(
      (select id from m5_ids where key = 'rollback_assignment'),
      'Rollback scenario',
      null
    )
  )$$,
  'rollback scenario starts with a valid pending request'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

select throws_like(
  $$select public.approve_release_request_replace(
    (select id from m5_ids where key = 'rollback_request'),
    '25000000-0000-0000-0000-000000000003',
    false,
    null,
    'FORCE_ROLLBACK'
  )$$,
  'forced release resolution failure',
  'failure after replacement insertion aborts the controlled workflow'
);

select is(
  (
    select status from public.supervisor_release_requests(null)
    where request_id = (select id from m5_ids where key = 'rollback_request')
  ),
  'PENDING'::public.release_request_status,
  'failed replacement rolls request status back to pending'
);

select is(
  (
    select count(*) from public.supervisor_roster_assignments()
    where id = (select id from m5_ids where key = 'rollback_assignment')
      and removed_at is null
  ),
  1::bigint,
  'failed replacement rolls original assignment removal back'
);

select is(
  (
    select count(*) from public.supervisor_roster_assignments()
    where shift_id = (select id from m5_ids where key = 'rollback_shift')
      and staff_id = '25000000-0000-0000-0000-000000000003'
  ),
  0::bigint,
  'failed replacement rolls new assignment insertion back'
);

select is(
  (
    select count(*) from public.roster_audit
    where reason = 'FORCE_ROLLBACK'
  ),
  0::bigint,
  'failed replacement rolls audit writes back'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select lives_ok(
  $$insert into m5_ids values (
    'sync_remove_request',
    public.submit_release_request(
      (select id from m5_ids where key = 'sync_remove_assignment'),
      'Direct removal sync',
      null
    )
  )$$,
  'pending request exists before direct supervisor removal'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

select lives_ok(
  $$select public.remove_employee(
    (select id from m5_ids where key = 'sync_remove_assignment'),
    'Roster changed directly'
  )$$,
  'existing supervisor removal command remains usable'
);

select is(
  (
    select status from public.supervisor_release_requests(null)
    where request_id = (select id from m5_ids where key = 'sync_remove_request')
  ),
  'CANCELLED'::public.release_request_status,
  'direct removal cancels its pending request'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select lives_ok(
  $$insert into m5_ids values (
    'cancel_request',
    public.submit_release_request(
      (select id from m5_ids where key = 'cancel_assignment'),
      'Cancellation sync',
      null
    )
  )$$,
  'pending request exists before shift cancellation'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

select lives_ok(
  $$select public.set_shift_status(
    (select id from m5_ids where key = 'cancel_shift'),
    'CANCELLED',
    'Session cancelled'
  )$$,
  'supervisor can cancel a shift with a pending request'
);

select is(
  (
    select status from public.supervisor_release_requests(null)
    where request_id = (select id from m5_ids where key = 'cancel_request')
  ),
  'CANCELLED'::public.release_request_status,
  'shift cancellation cancels its pending request'
);

select is(
  (
    select count(*) from public.roster_audit
    where action = 'RELEASE_REQUEST_CANCELLED'
      and release_request_id = (select id from m5_ids where key = 'sync_remove_request')
  ),
  1::bigint,
  'direct removal writes exactly one release-request cancellation audit event'
);

select is(
  (
    select count(*) from public.roster_audit
    where action = 'RELEASE_REQUEST_CANCELLED'
      and release_request_id = (select id from m5_ids where key = 'cancel_request')
  ),
  1::bigint,
  'shift cancellation writes exactly one release-request cancellation audit event'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select lives_ok(
  $$insert into m5_ids values (
    'unpublish_request',
    public.submit_release_request(
      (select id from m5_ids where key = 'unpublish_assignment'),
      'Pending through unpublication',
      null
    )
  )$$,
  'request exists before shift unpublication'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

select lives_ok(
  $$select public.set_shift_status(
    (select id from m5_ids where key = 'unpublish_shift'),
    'DRAFT',
    'Draft correction'
  )$$,
  'supervisor can unpublish a shift with a pending request'
);

select is(
  (
    select status from public.supervisor_release_requests(null)
    where request_id = (select id from m5_ids where key = 'unpublish_request')
  ),
  'PENDING'::public.release_request_status,
  'unpublication retains the pending request'
);

select is(
  (
    select count(*) from public.roster_audit
    where action = 'RELEASE_REQUEST_CANCELLED'
      and release_request_id = (select id from m5_ids where key = 'unpublish_request')
  ),
  0::bigint,
  'unpublication does not write a release-request cancellation event'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select lives_ok(
  $$insert into m5_ids values (
    'direct_replace_request',
    public.submit_release_request(
      (select id from m5_ids where key = 'direct_replace_assignment'),
      'Direct replacement sync',
      null
    )
  )$$,
  'pending request exists before ordinary direct replacement'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

select throws_like(
  $$select public.replace_employee(
    (select id from m5_ids where key = 'direct_replace_assignment'),
    '25000000-0000-0000-0000-000000000003',
    'SHADOWING',
    false,
    null,
    'Attempted kind change'
  )$$,
  'Replacement assignment kind must match the original assignment',
  'ordinary replacement cannot change the original assignment kind'
);

select is(
  (
    select status from public.supervisor_release_requests(null)
    where request_id = (select id from m5_ids where key = 'direct_replace_request')
  ),
  'PENDING'::public.release_request_status,
  'failed kind-changing replacement leaves the request pending'
);

select lives_ok(
  $$insert into m5_ids values (
    'direct_replacement_assignment',
    public.replace_employee(
      (select id from m5_ids where key = 'direct_replace_assignment'),
      '25000000-0000-0000-0000-000000000003',
      'REGULAR',
      false,
      null,
      'Roster changed independently'
    )
  )$$,
  'ordinary direct replacement succeeds when the original kind is preserved'
);

select is(
  (
    select status from public.supervisor_release_requests(null)
    where request_id = (select id from m5_ids where key = 'direct_replace_request')
  ),
  'CANCELLED'::public.release_request_status,
  'ordinary direct replacement cancels its pending request'
);

select ok(
  (
    select assignment_kind = 'REGULAR' and removed_at is null
    from public.supervisor_roster_assignments()
    where id = (select id from m5_ids where key = 'direct_replacement_assignment')
  ),
  'ordinary direct replacement preserves the regular assignment kind'
);

select is(
  (
    select count(*) from public.roster_audit
    where action = 'RELEASE_REQUEST_CANCELLED'
      and release_request_id = (select id from m5_ids where key = 'direct_replace_request')
  ),
  1::bigint,
  'ordinary direct replacement writes exactly one cancellation audit event'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select lives_ok(
  $$insert into m5_ids values (
    'shadow_replace_request',
    public.submit_release_request(
      (select id from m5_ids where key = 'shadow_replace_assignment'),
      'Shadowing replacement requested',
      null
    )
  )$$,
  'shadowing employee can submit a replacement request'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

select lives_ok(
  $$insert into m5_ids values (
    'shadow_replacement_assignment',
    public.approve_release_request_replace(
      (select id from m5_ids where key = 'shadow_replace_request'),
      '25000000-0000-0000-0000-000000000003',
      false,
      null,
      'Approved shadowing replacement'
    )
  )$$,
  'release approval replaces a shadowing assignment'
);

select is(
  (
    select status from public.supervisor_release_requests(null)
    where request_id = (select id from m5_ids where key = 'shadow_replace_request')
  ),
  'APPROVED'::public.release_request_status,
  'explicit shadowing replacement approval produces approved status'
);

select ok(
  (
    select assignment_kind = 'SHADOWING' and removed_at is null
    from public.supervisor_roster_assignments()
    where id = (select id from m5_ids where key = 'shadow_replacement_assignment')
  ),
  'approval-and-replace preserves shadowing assignment kind'
);

select ok(
  (
    select regular_assigned_count = 0
      and shadowing_count = 1
      and understaffed
    from public.shift_staffing(
      (select id from m5_ids where key = 'shadow_replace_shift')
    )
  ),
  'shadowing replacement does not increase regular staffing coverage'
);

select ok(
  (
    select assignment_kind = 'REGULAR'
    from public.supervisor_roster_assignments()
    where id = (select id from m5_ids where key = 'replacement_assignment')
  ),
  'approval-and-replace preserves regular assignment kind'
);

select ok(
  (
    select regular_assigned_count = 1
      and shadowing_count = 0
      and not understaffed
    from public.shift_staffing(
      (select id from m5_ids where key = 'replace_shift')
    )
  ),
  'regular replacement preserves regular staffing coverage'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select ok(
  (
    select status = 'CANCELLED'
      and resolution_reason like 'Cancelled because%'
    from public.employee_release_requests()
    where request_id = (select id from m5_ids where key = 'direct_replace_request')
  ),
  'cancelled request remains readable in employee history'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

select ok(
  (
    select status = 'CANCELLED'
      and resolved_by_name = 'Synthetic M5 Supervisor'
      and not assignment_active
    from public.supervisor_release_requests(null)
    where request_id = (select id from m5_ids where key = 'direct_replace_request')
  ),
  'cancelled request remains readable in supervisor history with responsible actor'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select lives_ok(
  $$insert into m5_ids values (
    'availability_exception',
    public.save_availability_exception(
      null, '2026-09-30', 'unavailable', '12:00', '13:00', false,
      'Synthetic audit test'
    )
  )$$,
  'availability creation remains usable'
);

select lives_ok(
  $$select public.save_availability_exception(
    (select id from m5_ids where key = 'availability_exception'),
    '2026-09-30', 'unavailable', '12:30', '13:30', false,
    'Synthetic updated audit test'
  )$$,
  'availability update remains usable'
);

select lives_ok(
  $$select public.delete_availability_exception(
    (select id from m5_ids where key = 'availability_exception')
  )$$,
  'availability removal remains usable'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000001',
  true
);

select is(
  (
    select count(*) from public.roster_audit
    where entity_id = (select id from m5_ids where key = 'availability_exception')
      and action in (
        'AVAILABILITY_CREATED',
        'AVAILABILITY_UPDATED',
        'AVAILABILITY_REMOVED'
      )
  ),
  3::bigint,
  'availability create, update, and removal are all audited'
);

select ok(
  (
    select before_data->>'start_time' = '12:00:00'
      and after_data->>'start_time' = '12:30:00'
    from public.roster_audit
    where entity_id = (select id from m5_ids where key = 'availability_exception')
      and action = 'AVAILABILITY_UPDATED'
  ),
  'availability update audit contains minimal before and after data'
);

select ok(
  (
    select actor_name = 'Synthetic M5 Employee One'
      and action = 'RELEASE_REQUEST_CREATED'
      and entity_type = 'RELEASE_REQUEST'
      and entity_id = (select id from m5_ids where key = 'reject_request')
      and created_at is not null
    from public.supervisor_audit_history(
      'RELEASE_REQUEST_CREATED',
      'RELEASE_REQUEST',
      200
    )
    where entity_id = (select id from m5_ids where key = 'reject_request')
  ),
  'supervisor audit history exposes actor, action, entity, and timestamp'
);

select set_config(
  'request.jwt.claim.sub',
  '15000000-0000-0000-0000-000000000002',
  true
);

select throws_like(
  $$update public.roster_audit
    set action = 'FORGED'
    where action = 'RELEASE_REQUEST_CREATED'$$,
  'permission denied for table roster_audit',
  'employees cannot modify audit logs'
);

select throws_like(
  $$insert into public.release_requests(
    assignment_id, staff_id, reason
  ) values (
    (select id from m5_ids where key = 'rollback_assignment'),
    '25000000-0000-0000-0000-000000000002',
    'Direct write'
  )$$,
  'permission denied for table release_requests',
  'employees cannot bypass the release request command'
);

select * from finish();
rollback;
