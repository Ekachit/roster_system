begin;
select plan(18);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  (
    '16000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm6.supervisor@example.test', '',
    now(), now(), now()
  ),
  (
    '16000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm6.employee.one@example.test', '',
    now(), now(), now()
  ),
  (
    '16000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm6.employee.two@example.test', '',
    now(), now(), now()
  );

insert into public.staff(id, email, full_name, role, is_active) values
  (
    '26000000-0000-0000-0000-000000000001',
    'm6.supervisor@example.test', 'Synthetic M6 Supervisor', 'supervisor', true
  ),
  (
    '26000000-0000-0000-0000-000000000002',
    'm6.employee.one@example.test', 'Synthetic M6 Employee One', 'employee', true
  ),
  (
    '26000000-0000-0000-0000-000000000003',
    'm6.employee.two@example.test', 'Synthetic M6 Employee Two', 'employee', true
  );

update auth.users
set email_confirmed_at = email_confirmed_at + interval '1 second'
where id::text like '16000000-%';

insert into public.shifts (
  id, shift_title, local_date, start_time, end_time,
  location_id, activity_type_id, required_staff_count, status,
  created_by, updated_by, published_at, cancelled_at
) values
  (
    '36000000-0000-0000-0000-000000000001',
    'Synthetic single shift', '2026-08-10', '09:00', '10:30',
    (select id from public.locations where name = 'Clayton'),
    (select id from public.activity_types where name = 'Training'),
    1, 'PUBLISHED',
    '26000000-0000-0000-0000-000000000001',
    '26000000-0000-0000-0000-000000000001', now(), null
  ),
  (
    '36000000-0000-0000-0000-000000000002',
    'Synthetic back-to-back shift', '2026-08-10', '10:30', '12:00',
    (select id from public.locations where name = 'Caulfield'),
    (select id from public.activity_types where name = 'Event'),
    1, 'PUBLISHED',
    '26000000-0000-0000-0000-000000000001',
    '26000000-0000-0000-0000-000000000001', now(), null
  ),
  (
    '36000000-0000-0000-0000-000000000003',
    'Synthetic second employee shift', '2026-08-11', '13:00', '14:00',
    (select id from public.locations where name = 'Clayton'),
    (select id from public.activity_types where name = 'Training'),
    1, 'PUBLISHED',
    '26000000-0000-0000-0000-000000000001',
    '26000000-0000-0000-0000-000000000001', now(), null
  ),
  (
    '36000000-0000-0000-0000-000000000004',
    'Synthetic cancelled shift', '2026-08-12', '09:00', '10:00',
    (select id from public.locations where name = 'Clayton'),
    (select id from public.activity_types where name = 'Training'),
    1, 'CANCELLED',
    '26000000-0000-0000-0000-000000000001',
    '26000000-0000-0000-0000-000000000001', now(), now()
  ),
  (
    '36000000-0000-0000-0000-000000000005',
    'Synthetic removed assignment shift', '2026-08-13', '09:00', '10:00',
    (select id from public.locations where name = 'Clayton'),
    (select id from public.activity_types where name = 'Training'),
    1, 'PUBLISHED',
    '26000000-0000-0000-0000-000000000001',
    '26000000-0000-0000-0000-000000000001', now(), null
  ),
  (
    '36000000-0000-0000-0000-000000000006',
    'Synthetic draft shift', '2026-08-14', '09:00', '10:00',
    (select id from public.locations where name = 'Clayton'),
    (select id from public.activity_types where name = 'Training'),
    1, 'DRAFT',
    '26000000-0000-0000-0000-000000000001',
    '26000000-0000-0000-0000-000000000001', null, null
  ),
  (
    '36000000-0000-0000-0000-000000000007',
    'Synthetic Melbourne DST shift', '2026-04-05', '01:30', '03:30',
    (select id from public.locations where name = 'Clayton'),
    (select id from public.activity_types where name = 'Training'),
    1, 'PUBLISHED',
    '26000000-0000-0000-0000-000000000001',
    '26000000-0000-0000-0000-000000000001', now(), null
  );

insert into public.shift_assignments (
  id, shift_id, staff_id, assignment_kind, assigned_by,
  removed_at, removed_by, removal_reason
) values
  (
    '46000000-0000-0000-0000-000000000001',
    '36000000-0000-0000-0000-000000000001',
    '26000000-0000-0000-0000-000000000002',
    'REGULAR', '26000000-0000-0000-0000-000000000001',
    null, null, null
  ),
  (
    '46000000-0000-0000-0000-000000000002',
    '36000000-0000-0000-0000-000000000002',
    '26000000-0000-0000-0000-000000000002',
    'REGULAR', '26000000-0000-0000-0000-000000000001',
    null, null, null
  ),
  (
    '46000000-0000-0000-0000-000000000003',
    '36000000-0000-0000-0000-000000000003',
    '26000000-0000-0000-0000-000000000003',
    'SHADOWING', '26000000-0000-0000-0000-000000000001',
    null, null, null
  ),
  (
    '46000000-0000-0000-0000-000000000004',
    '36000000-0000-0000-0000-000000000004',
    '26000000-0000-0000-0000-000000000002',
    'REGULAR', '26000000-0000-0000-0000-000000000001',
    null, null, null
  ),
  (
    '46000000-0000-0000-0000-000000000005',
    '36000000-0000-0000-0000-000000000005',
    '26000000-0000-0000-0000-000000000002',
    'REGULAR', '26000000-0000-0000-0000-000000000001',
    now(), '26000000-0000-0000-0000-000000000001',
    'Synthetic historical removal'
  ),
  (
    '46000000-0000-0000-0000-000000000006',
    '36000000-0000-0000-0000-000000000006',
    '26000000-0000-0000-0000-000000000002',
    'REGULAR', '26000000-0000-0000-0000-000000000001',
    null, null, null
  ),
  (
    '46000000-0000-0000-0000-000000000007',
    '36000000-0000-0000-0000-000000000007',
    '26000000-0000-0000-0000-000000000002',
    'REGULAR', '26000000-0000-0000-0000-000000000001',
    null, null, null
  );

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '16000000-0000-0000-0000-000000000001',
  true
);

select is(
  (
    select duration_minutes
    from public.scheduled_hours_report('2026-08-10', '2026-08-10')
    where shift_id = '36000000-0000-0000-0000-000000000001'
  ),
  90,
  'single shift duration is calculated from its start and end'
);

select is(
  (
    select count(*)
    from public.scheduled_hours_report(
      '2026-08-10', '2026-08-11',
      '26000000-0000-0000-0000-000000000002'
    )
  ),
  2::bigint,
  'multiple shifts for one employee are returned'
);

select is(
  (
    select sum(duration_minutes)
    from public.scheduled_hours_report(
      '2026-08-10', '2026-08-11',
      '26000000-0000-0000-0000-000000000002'
    )
  ),
  180::bigint,
  'multiple shift minutes total exactly'
);

select is(
  (
    select count(*)
    from public.scheduled_hours_report(
      '2026-08-10', '2026-08-10',
      '26000000-0000-0000-0000-000000000002'
    )
    where end_time = '10:30' or start_time = '10:30'
  ),
  2::bigint,
  'back-to-back shifts are both reported'
);

select is(
  (
    select count(*)
    from public.scheduled_hours_report('2026-08-12', '2026-08-12')
  ),
  0::bigint,
  'cancelled shifts are excluded'
);

select is(
  (
    select count(*)
    from public.scheduled_hours_report('2026-08-13', '2026-08-13')
  ),
  0::bigint,
  'removed assignments are preserved but excluded'
);

select is(
  (
    select count(*)
    from public.scheduled_hours_report('2026-08-14', '2026-08-14')
  ),
  0::bigint,
  'draft shifts are excluded'
);

select is(
  (
    select count(*)
    from public.scheduled_hours_report('2026-08-10', '2026-08-10')
  ),
  2::bigint,
  'date filters include both boundaries and exclude later dates'
);

select is(
  (
    select count(*)
    from public.scheduled_hours_report(
      '2026-08-10', '2026-08-11',
      '26000000-0000-0000-0000-000000000003'
    )
  ),
  1::bigint,
  'employee filter matches only the selected employee'
);

select is(
  (
    select count(*)
    from public.scheduled_hours_report(
      '2026-08-10', '2026-08-11', null,
      (select id from public.locations where name = 'Caulfield')
    )
  ),
  1::bigint,
  'location filter matches only the selected location'
);

select is(
  (
    select count(*)
    from public.scheduled_hours_report(
      '2026-08-10', '2026-08-11', null, null,
      (select id from public.activity_types where name = 'Training')
    )
  ),
  2::bigint,
  'activity filter matches only the selected activity type'
);

select is(
  (
    select count(*)
    from public.scheduled_hours_report(
      '2026-08-10', '2026-08-11',
      '26000000-0000-0000-0000-000000000002',
      (select id from public.locations where name = 'Caulfield'),
      (select id from public.activity_types where name = 'Event')
    )
  ),
  1::bigint,
  'combined employee, location, and activity filters match together'
);

select ok(
  (
    select employee_name = 'Synthetic M6 Employee One'
      and employee_email = 'm6.employee.one@example.test'
      and local_date = '2026-08-10'
      and start_time = '09:00'
      and end_time = '10:30'
      and duration_minutes = 90
      and location_name = 'Clayton'
      and activity_name = 'Training'
      and shift_status = 'PUBLISHED'
      and assignment_status = 'ASSIGNED'
    from public.scheduled_hours_report('2026-08-10', '2026-08-10')
    where assignment_id = '46000000-0000-0000-0000-000000000001'
  ),
  'report returns the exact CSV-safe data contract'
);

select is(
  (
    select duration_minutes
    from public.scheduled_hours_report('2026-04-05', '2026-04-05')
  ),
  180,
  'duration uses Melbourne instants across the daylight-saving fallback'
);

select throws_like(
  $$select * from public.scheduled_hours_report('2026-08-11', '2026-08-10')$$,
  'Start date must be on or before end date',
  'reversed date range is rejected'
);

select throws_like(
  $$select * from public.scheduled_hours_report(null, '2026-08-10')$$,
  'Start date and end date are required',
  'missing date range is rejected'
);

select is(
  (
    select count(*)
    from public.scheduled_hours_report('2026-09-01', '2026-09-30')
  ),
  0::bigint,
  'an empty filtered range returns no rows'
);

select set_config(
  'request.jwt.claim.sub',
  '16000000-0000-0000-0000-000000000002',
  true
);

select throws_like(
  $$select * from public.scheduled_hours_report('2026-08-10', '2026-08-11')$$,
  'Supervisor access required',
  'employee report access is denied before private data is returned'
);

select * from finish();
rollback;
