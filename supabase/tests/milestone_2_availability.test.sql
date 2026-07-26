begin;
select plan(27);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('11000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'availability.supervisor@example.test', '', now(), now(), now()),
  ('11000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'availability.employee.a@example.test', '', now(), now(), now()),
  ('11000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'availability.employee.b@example.test', '', now(), now(), now()),
  ('11000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'availability.inactive@example.test', '', now(), now(), now());

insert into public.staff (id, email, full_name, role, is_active) values
  ('21000000-0000-0000-0000-000000000001', 'availability.supervisor@example.test', 'Sydney Supervisor', 'supervisor', true),
  ('21000000-0000-0000-0000-000000000002', 'availability.employee.a@example.test', 'Robin Employee', 'employee', true),
  ('21000000-0000-0000-0000-000000000003', 'availability.employee.b@example.test', 'Drew Employee', 'employee', true),
  ('21000000-0000-0000-0000-000000000004', 'availability.inactive@example.test', 'Jamie Inactive', 'employee', false);

update auth.users set email_confirmed_at = email_confirmed_at + interval '1 second'
where id::text like '11000000-%';

set local role anon;
select throws_ok($$select count(*) from public.recurring_availability$$, 'permission denied for table recurring_availability', 'anonymous cannot read recurring availability');
select throws_ok($$select count(*) from public.availability_exceptions$$, 'permission denied for table availability_exceptions', 'anonymous cannot read exceptions');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000002', true);
select lives_ok(
  $$select public.save_recurring_availability(null, 2::smallint, '09:00', '17:00', '2026-07-01', null, 'Usual Tuesday')$$,
  'employee can create own recurring availability'
);
select lives_ok(
  $$select public.save_recurring_availability(null, 6::smallint, '09:00', '17:00', '2026-07-01', null, 'Usual Saturday')$$,
  'employee can create Saturday recurring availability'
);
select lives_ok(
  $$select public.save_recurring_availability(null, 7::smallint, '10:00', '16:00', '2026-07-01', null, 'Usual Sunday')$$,
  'employee can create Sunday recurring availability'
);
select lives_ok(
  $$select public.save_availability_exception(null, '2026-07-28', 'unavailable', '12:00', '14:00', false, 'Appointment')$$,
  'employee can create own unavailable exception'
);
select lives_ok(
  $$select public.save_availability_exception(null, '2026-07-29', 'available', '10:00', '12:00', false, 'Extra availability')$$,
  'employee can create own available exception'
);
select lives_ok(
  $$select public.save_availability_exception(null, '2026-07-30', 'unavailable', null, null, true, 'Away')$$,
  'employee can create full-day unavailability'
);
select lives_ok(
  $$select public.save_availability_exception(null, '2026-08-01', 'available', '10:00', '12:00', false, 'Saturday extra')$$,
  'employee can create a weekend timed available override'
);
select lives_ok(
  $$select public.save_availability_exception(null, '2026-08-02', 'unavailable', '12:00', '14:00', false, 'Sunday unavailable')$$,
  'employee can create weekend timed unavailability'
);
select lives_ok(
  $$select public.save_availability_exception(null, '2026-08-08', 'unavailable', null, null, true, 'Saturday away')$$,
  'employee can create weekend full-day unavailability'
);
select is((select count(*) from public.recurring_availability), 3::bigint, 'employee reads own weekday and weekend recurring rules');
select is((select count(*) from public.availability_exceptions), 6::bigint, 'employee reads own weekday and weekend exceptions');
select throws_ok(
  $$select public.save_recurring_availability(null, 2::smallint, '12:00', '12:00', '2026-07-01', null, null)$$,
  'End time must be later than start time on an ISO weekday from 1 to 7',
  'zero-length recurring range is rejected'
);
select throws_ok(
  $$select public.save_recurring_availability(null, 0::smallint, '09:00', '17:00', '2026-07-01', null, null)$$,
  'End time must be later than start time on an ISO weekday from 1 to 7',
  'weekday zero is rejected'
);
select throws_ok(
  $$select public.save_recurring_availability(null, 8::smallint, '09:00', '17:00', '2026-07-01', null, null)$$,
  'End time must be later than start time on an ISO weekday from 1 to 7',
  'weekday eight is rejected'
);
select throws_ok(
  $$select public.save_recurring_availability(null, 6::smallint, '22:00', '06:00', '2026-07-01', null, null)$$,
  'End time must be later than start time on an ISO weekday from 1 to 7',
  'overnight weekend recurring availability is rejected'
);
select throws_ok(
  $$select public.save_availability_exception(null, '2026-08-01', 'unavailable', '14:00', '09:00', false, null)$$,
  'Date exception range is invalid',
  'reversed exception range is rejected'
);
select throws_ok(
  $$select public.save_recurring_availability(null, 2::smallint, '16:00', '18:00', '2026-07-01', null, null)$$,
  'Recurring availability overlaps an existing rule',
  'overlapping effective recurring rules are rejected'
);
select throws_ok(
  $$select public.save_availability_exception(null, '2026-07-28', 'available', '13:00', '15:00', false, null)$$,
  'Availability exception overlaps an existing exception',
  'overlapping date exceptions are rejected'
);
select throws_ok(
  $$insert into public.recurring_availability(staff_id, weekday,start_time,end_time,effective_start_date)
    values ('21000000-0000-0000-0000-000000000003', 6, '09:00', '17:00', '2026-01-01')$$,
  'permission denied for table recurring_availability',
  'browser cannot spoof staff id with direct weekend insert'
);

reset role;
create temp table employee_a_rule as
select id from public.recurring_availability
where staff_id = '21000000-0000-0000-0000-000000000002';
grant select on employee_a_rule to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000003', true);
select is((select count(*) from public.recurring_availability), 0::bigint, 'employee B cannot read employee A recurring availability');
select is((select count(*) from public.availability_exceptions), 0::bigint, 'employee B cannot read employee A exceptions');
select throws_ok(
  $$select public.delete_recurring_availability((select id from employee_a_rule limit 1))$$,
  'Recurring availability not found',
  'employee B cannot delete employee A recurring availability'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000001', true);
select is((select count(*) from public.recurring_availability), 3::bigint, 'supervisor reads all weekday and weekend recurring availability');
select is((select count(*) from public.availability_exceptions), 6::bigint, 'supervisor reads all weekday and weekend exceptions');

select set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000004', true);
select is(
  (select count(*) from public.recurring_availability) + (select count(*) from public.availability_exceptions),
  0::bigint,
  'inactive employee reads no availability'
);

select * from finish();
rollback;
