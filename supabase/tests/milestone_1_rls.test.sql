begin;
select plan(10);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.supervisor@example.test', '', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.employee@example.test', '', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.inactive@example.test', '', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.unapproved@example.test', '', now(), now(), now());

insert into public.staff (id, email, full_name, role, is_active) values
  ('20000000-0000-0000-0000-000000000001', 'rls.supervisor@example.test', 'Riley Supervisor', 'supervisor', true),
  ('20000000-0000-0000-0000-000000000002', 'rls.employee@example.test', 'Morgan Employee', 'employee', true),
  ('20000000-0000-0000-0000-000000000003', 'rls.inactive@example.test', 'Casey Inactive', 'employee', false);

update auth.users set email_confirmed_at = email_confirmed_at + interval '1 second'
where id::text like '10000000-%';

insert into public.staff_private_notes(staff_id, note)
values ('20000000-0000-0000-0000-000000000002', 'Supervisor private note');

set local role anon;
select throws_ok(
  $$select count(*) from public.staff$$,
  'permission denied for table staff',
  'anonymous users cannot read staff'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select is(public.current_staff_id(), '20000000-0000-0000-0000-000000000002'::uuid, 'approved active employee is linked');
select is((select count(*) from public.staff), 1::bigint, 'employee reads only own staff row');
select is((select count(*) from public.staff_private_notes), 0::bigint, 'employee cannot read supervisor notes');
select throws_ok(
  $$select public.save_staff_profile(null, 'attacker@example.test', 'Attacker', 'supervisor', null)$$,
  'Supervisor access required',
  'employee cannot create or elevate a role'
);
select is((select count(*) from public.supervisor_staff_directory), 0::bigint, 'employee cannot read supervisor directory');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
select is(public.current_staff_id(), null::uuid, 'inactive user has no active staff identity');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
select is(public.current_staff_id(), null::uuid, 'unapproved user has no staff identity');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select ok(public.is_supervisor(), 'approved supervisor is recognised');
select is((select count(*) from public.staff_private_notes), 1::bigint, 'supervisor can read private notes');

select * from finish();
rollback;
