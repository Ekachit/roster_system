begin;
select plan(18);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  (
    '19000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm7.supervisor@example.test', '',
    now(), now(), now()
  ),
  (
    '19000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm7.employee@example.test', '',
    now(), now(), now()
  ),
  (
    '19000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm7.unapproved@example.test', '',
    now(), now(), now()
  );

insert into public.staff(id, email, full_name, role, is_active) values
  (
    '29000000-0000-0000-0000-000000000001',
    'm7.supervisor@example.test', 'Synthetic M7 Supervisor', 'supervisor', true
  ),
  (
    '29000000-0000-0000-0000-000000000002',
    'm7.employee@example.test', 'Synthetic M7 Employee', 'employee', true
  );

update auth.users
set email_confirmed_at = email_confirmed_at + interval '1 second'
where id::text like '19000000-%';

insert into public.staff_private_notes(staff_id, note)
values (
  '29000000-0000-0000-0000-000000000002',
  'M7 supervisor-only note'
);

insert into public.recurring_availability(
  id, staff_id, weekday, start_time, end_time, effective_start_date, note
) values (
  '79000000-0000-0000-0000-000000000001',
  '29000000-0000-0000-0000-000000000002',
  1, '09:00', '17:00', '2026-01-01', 'M7 private availability'
);

insert into public.shifts(
  id, shift_title, local_date, start_time, end_time,
  location_id, activity_type_id, required_staff_count,
  notes, status, published_at, created_by, updated_by
) values (
  '39000000-0000-0000-0000-000000000001',
  'M7 release constraint fixture', '2026-09-07', '09:00', '10:00',
  (select id from public.locations where name = 'Clayton'),
  (select id from public.activity_types where name = 'Training'),
  1, null, 'PUBLISHED', now(),
  '29000000-0000-0000-0000-000000000001',
  '29000000-0000-0000-0000-000000000001'
);

insert into public.shift_assignments(
  id, shift_id, staff_id, assignment_kind, assigned_by
) values (
  '49000000-0000-0000-0000-000000000001',
  '39000000-0000-0000-0000-000000000001',
  '29000000-0000-0000-0000-000000000002',
  'REGULAR',
  '29000000-0000-0000-0000-000000000001'
);

insert into public.roster_audit(
  actor_staff_id, action, entity_type, reason
) values (
  '29000000-0000-0000-0000-000000000001',
  'M7_HARDENING_FIXTURE', 'AUDIT_EVENT', 'Original immutable reason'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.is_shift_published(uuid)',
    'EXECUTE'
  ),
  'obsolete shift-status helper is not browser executable'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.prevent_roster_audit_mutation()',
    'EXECUTE'
  ),
  'audit trigger function is not browser executable'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.protect_assigned_shift_material_fields()',
    'EXECUTE'
  ),
  'assigned-shift integrity trigger is not browser executable'
);

select throws_like(
  $$update public.shifts
    set start_time = '08:30'
    where id = '39000000-0000-0000-0000-000000000001'$$,
  'Remove or replace active assignments before changing shift date, time, location, or activity',
  'material shift edits cannot invalidate an active assignment'
);

select throws_like(
  $$update public.roster_audit
    set reason = 'Tampered'
    where action = 'M7_HARDENING_FIXTURE'$$,
  'Roster audit history is append-only',
  'database owner cannot update audit history'
);

select throws_like(
  $$delete from public.roster_audit
    where action = 'M7_HARDENING_FIXTURE'$$,
  'Roster audit history is append-only',
  'database owner cannot delete audit history'
);

select throws_like(
  $$insert into public.staff(email, full_name, role)
    values (
      'm7.long-name@example.test',
      repeat('x', 121),
      'employee'
    )$$,
  '%staff_full_name_length%',
  'oversized staff names are rejected by the database'
);

select throws_like(
  $$insert into public.shifts(
      shift_title, local_date, start_time, end_time,
      location_id, activity_type_id, required_staff_count,
      notes, created_by, updated_by
    ) values (
      repeat('x', 161), '2026-09-07', '09:00', '10:00',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, null,
      '29000000-0000-0000-0000-000000000001',
      '29000000-0000-0000-0000-000000000001'
    )$$,
  '%shifts_title_length%',
  'oversized shift titles are rejected by the database'
);

select throws_like(
  $$insert into public.release_requests(
      assignment_id, staff_id, reason, status
    ) values (
      '49000000-0000-0000-0000-000000000001',
      '29000000-0000-0000-0000-000000000002',
      repeat('x', 201),
      'PENDING'
    )$$,
  '%release_requests_reason_length%',
  'oversized release reasons are rejected by the database'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '19000000-0000-0000-0000-000000000002',
  true
);

select is(
  (select count(*) from public.staff_private_notes),
  0::bigint,
  'employee cannot read supervisor-only notes'
);

select is(
  (
    select count(*)
    from public.recurring_availability
    where staff_id <> '29000000-0000-0000-0000-000000000002'
  ),
  0::bigint,
  'employee cannot read another employee availability'
);

select throws_like(
  $$select * from public.supervisor_roster_shifts(
    '2026-09-01', '2026-09-30'
  )$$,
  'Supervisor access required',
  'employee cannot call supervisor roster projection'
);

select throws_like(
  $$select * from public.scheduled_hours_report(
    '2026-09-01', '2026-09-30'
  )$$,
  'Supervisor access required',
  'employee cannot call supervisor reporting projection'
);

select throws_like(
  $$update public.staff
    set role = 'supervisor'
    where id = '29000000-0000-0000-0000-000000000002'$$,
  'permission denied for table staff',
  'employee cannot directly escalate their role'
);

select throws_like(
  $$insert into public.shifts(
      shift_title, local_date, start_time, end_time,
      location_id, activity_type_id, required_staff_count,
      notes, created_by, updated_by
    ) values (
      'Unauthorized shift', '2026-09-07', '09:00', '10:00',
      (select id from public.locations where name = 'Clayton'),
      (select id from public.activity_types where name = 'Training'),
      1, null,
      '29000000-0000-0000-0000-000000000002',
      '29000000-0000-0000-0000-000000000002'
    )$$,
  'permission denied for table shifts',
  'employee cannot directly create a shift'
);

select throws_like(
  $$update public.roster_audit
    set reason = 'Browser tamper'
    where action = 'M7_HARDENING_FIXTURE'$$,
  'permission denied for table roster_audit',
  'employee cannot directly mutate audit history'
);

select set_config(
  'request.jwt.claim.sub',
  '19000000-0000-0000-0000-000000000003',
  true
);

select is(
  (select count(*) from public.recurring_availability),
  0::bigint,
  'unapproved authenticated user cannot read availability'
);

select is(
  (select count(*) from public.current_access_profile()),
  0::bigint,
  'unapproved authenticated user has no access profile'
);

select * from finish();
rollback;
