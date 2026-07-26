begin;
select plan(41);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.supervisor.one@example.test', '', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.employee.a@example.test', '', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.employee.b@example.test', '', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.inactive@example.test', '', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.unapproved@example.test', '', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.supervisor.two@example.test', '', now(), now(), now());

insert into public.staff (id, email, full_name, role, is_active) values
  ('20000000-0000-0000-0000-000000000001', 'rls.supervisor.one@example.test', 'Riley Supervisor', 'supervisor', true),
  ('20000000-0000-0000-0000-000000000002', 'rls.employee.a@example.test', 'Morgan Employee', 'employee', true),
  ('20000000-0000-0000-0000-000000000003', 'rls.employee.b@example.test', 'Avery Employee', 'employee', true),
  ('20000000-0000-0000-0000-000000000004', 'rls.inactive@example.test', 'Casey Inactive', 'employee', false),
  ('20000000-0000-0000-0000-000000000006', 'rls.supervisor.two@example.test', 'Jordan Supervisor', 'supervisor', true);

update auth.users
set email_confirmed_at = email_confirmed_at + interval '1 second'
where id::text like '10000000-%';

insert into public.staff_private_notes(staff_id, note)
values ('20000000-0000-0000-0000-000000000002', 'Supervisor private note');

insert into public.locations(id, name) values
  ('30000000-0000-0000-0000-000000000001', 'RLS Location One'),
  ('30000000-0000-0000-0000-000000000002', 'RLS Location Two');
insert into public.activity_types(id, name) values
  ('40000000-0000-0000-0000-000000000001', 'RLS Activity One'),
  ('40000000-0000-0000-0000-000000000002', 'RLS Activity Two');
insert into public.staff_locations(staff_id, location_id) values
  ('20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000002');
insert into public.staff_activity_types(staff_id, activity_type_id) values
  ('20000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000002');

set local role anon;
select throws_ok($$select count(*) from public.staff$$, 'permission denied for table staff', 'anonymous cannot read staff');
select throws_ok($$select count(*) from public.staff_private_notes$$, 'permission denied for table staff_private_notes', 'anonymous cannot read notes');
select throws_ok($$select count(*) from public.locations$$, 'permission denied for table locations', 'anonymous cannot read locations');
select throws_ok($$select count(*) from public.activity_types$$, 'permission denied for table activity_types', 'anonymous cannot read activities');
select throws_ok($$select count(*) from public.staff_locations$$, 'permission denied for table staff_locations', 'anonymous cannot read location eligibility');
select throws_ok($$select count(*) from public.staff_activity_types$$, 'permission denied for table staff_activity_types', 'anonymous cannot read activity eligibility');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
select is(
  array[
    (select count(*) from public.staff),
    (select count(*) from public.staff_private_notes),
    (select count(*) from public.locations),
    (select count(*) from public.activity_types),
    (select count(*) from public.staff_locations),
    (select count(*) from public.staff_activity_types)
  ],
  array[0::bigint,0::bigint,0::bigint,0::bigint,0::bigint,0::bigint],
  'unapproved user is denied from every base table'
);
select is((select count(*) from public.current_access_profile()), 0::bigint, 'unapproved user has no access-status profile');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
select is(
  array[
    (select count(*) from public.staff),
    (select count(*) from public.staff_private_notes),
    (select count(*) from public.locations),
    (select count(*) from public.activity_types),
    (select count(*) from public.staff_locations),
    (select count(*) from public.staff_activity_types)
  ],
  array[0::bigint,0::bigint,0::bigint,0::bigint,0::bigint,0::bigint],
  'inactive user is denied from every base table'
);
select is((select count(*) from public.current_access_profile()), 1::bigint, 'inactive user can read one limited access-status row');
select ok(
  (select not is_active and email_matches from public.current_access_profile()),
  'inactive access status reports inactive with a matching approved email'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select is((select count(*) from public.staff), 1::bigint, 'employee reads only own staff row');
select is((select count(*) from public.staff_locations where staff_id = '20000000-0000-0000-0000-000000000003'), 0::bigint, 'employee A cannot read employee B location eligibility');
select is((select count(*) from public.staff_locations), 1::bigint, 'employee A reads own location eligibility');
select is((select count(*) from public.staff_activity_types where staff_id = '20000000-0000-0000-0000-000000000003'), 0::bigint, 'employee A cannot read employee B activity eligibility');
select is((select count(*) from public.staff_activity_types), 1::bigint, 'employee A reads own activity eligibility');
select is((select count(*) from public.staff_private_notes), 0::bigint, 'employee cannot read supervisor notes');
select throws_ok($$update public.staff set role = 'supervisor' where id = '20000000-0000-0000-0000-000000000002'$$, 'permission denied for table staff', 'employee cannot change role');
select throws_ok($$update public.staff set is_active = false where id = '20000000-0000-0000-0000-000000000002'$$, 'permission denied for table staff', 'employee cannot change active status');
select throws_ok($$update public.staff set email = 'attacker@example.test' where id = '20000000-0000-0000-0000-000000000002'$$, 'permission denied for table staff', 'employee cannot change approved email');
select throws_ok($$update public.staff set auth_user_id = null where id = '20000000-0000-0000-0000-000000000002'$$, 'permission denied for table staff', 'employee cannot change Auth linkage');
select throws_ok($$insert into public.locations(name) values ('Employee Location')$$, 'new row violates row-level security policy for table "locations"', 'employee cannot insert a location');
update public.locations set name = 'Employee Rename' where id = '30000000-0000-0000-0000-000000000001';
select is((select name::text from public.locations where id = '30000000-0000-0000-0000-000000000001'), 'RLS Location One', 'employee cannot update a location');
select throws_ok($$insert into public.activity_types(name) values ('Employee Activity')$$, 'new row violates row-level security policy for table "activity_types"', 'employee cannot insert an activity');
update public.activity_types set name = 'Employee Rename' where id = '40000000-0000-0000-0000-000000000001';
select is((select name::text from public.activity_types where id = '40000000-0000-0000-0000-000000000001'), 'RLS Activity One', 'employee cannot update an activity');
select throws_ok(
  $$select public.save_staff_configuration(null, 'attacker@example.test', 'Attacker', 'supervisor', null, array[]::uuid[], array[]::uuid[])$$,
  'Supervisor access required',
  'employee cannot invoke the supervisor staff command'
);

reset role;
update auth.users set email = 'changed.employee@example.test'
where id = '10000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select is(public.current_staff_id(), null::uuid, 'post-link Auth email change immediately removes active access');
select ok(
  (select is_active and not email_matches from public.current_access_profile()),
  'limited access status safely reports the Auth email mismatch'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select ok(public.is_supervisor(), 'approved supervisor is recognised');
select cmp_ok((select count(*) from public.supervisor_staff_directory), '>=', 5::bigint, 'supervisor reads the staff directory and notes');
select lives_ok(
  $$select public.save_staff_configuration(
    null,
    'rls.created@example.test',
    'Created Employee',
    'employee',
    'Private configuration note',
    array['30000000-0000-0000-0000-000000000001']::uuid[],
    array['40000000-0000-0000-0000-000000000001']::uuid[]
  )$$,
  'supervisor can atomically create staff, notes and eligibility'
);
select ok(
  exists (
    select 1
    from public.staff s
    join public.staff_private_notes n on n.staff_id = s.id
    join public.staff_locations sl on sl.staff_id = s.id
    join public.staff_activity_types sa on sa.staff_id = s.id
    where s.email = 'rls.created@example.test'
      and n.note = 'Private configuration note'
      and sl.location_id = '30000000-0000-0000-0000-000000000001'
      and sa.activity_type_id = '40000000-0000-0000-0000-000000000001'
  ),
  'atomic staff command persisted every configuration part'
);
select lives_ok(
  $$insert into public.locations(name) values ('Supervisor Location');
    update public.locations set name = 'Supervisor Location Updated' where name = 'Supervisor Location';
    insert into public.activity_types(name) values ('Supervisor Activity');
    update public.activity_types set name = 'Supervisor Activity Updated' where name = 'Supervisor Activity'$$,
  'supervisor can insert and update locations and activities'
);
select throws_ok(
  $$select public.save_staff_configuration(
    '20000000-0000-0000-0000-000000000003',
    'different.approved@example.test',
    'Avery Employee',
    'employee',
    null,
    array[]::uuid[],
    array[]::uuid[]
  )$$,
  'A linked staff email cannot be changed; use the administrator unlink-and-relink procedure',
  'normal staff save cannot change a linked approved email'
);
select throws_ok(
  $$select public.save_staff_configuration(
    null,
    'rollback@example.test',
    'Rollback Example',
    'employee',
    'Must roll back',
    array['ffffffff-ffff-ffff-ffff-ffffffffffff']::uuid[],
    array[]::uuid[]
  )$$,
  '23503',
  null,
  'invalid eligibility rolls back the atomic staff command'
);
select is((select count(*) from public.staff where email = 'rollback@example.test'), 0::bigint, 'failed atomic command leaves no partial staff profile');

select lives_ok(
  $$select public.save_staff_configuration(
    '20000000-0000-0000-0000-000000000006',
    'rls.supervisor.two@example.test',
    'Jordan Supervisor',
    'employee',
    null,
    array[]::uuid[],
    array[]::uuid[]
  )$$,
  'demoting one of two supervisors succeeds'
);
select throws_ok(
  $$select public.save_staff_configuration(
    '20000000-0000-0000-0000-000000000001',
    'rls.supervisor.one@example.test',
    'Riley Supervisor',
    'employee',
    null,
    array[]::uuid[],
    array[]::uuid[]
  )$$,
  'The last active supervisor cannot be demoted or deactivated',
  'sequential final-supervisor demotion fails'
);
select throws_ok(
  $$select public.set_staff_active('20000000-0000-0000-0000-000000000001', false)$$,
  'The last active supervisor cannot be demoted or deactivated',
  'sequential final-supervisor deactivation fails'
);
select ok(public.is_supervisor(), 'the protected caller remains an authorised active supervisor');
select ok(
  not has_function_privilege('anon', 'public.set_updated_at()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.set_updated_at()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.link_approved_auth_user()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.link_approved_auth_user()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.protect_staff_invariants()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.protect_staff_invariants()', 'EXECUTE'),
  'trigger-only functions have no client execution grants'
);

select * from finish();
rollback;
