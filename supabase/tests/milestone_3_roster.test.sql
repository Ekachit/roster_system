begin;
select plan(36);

insert into auth.users (id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
('12000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','roster.supervisor@example.test','',now(),now(),now()),
('12000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','roster.available@example.test','',now(),now(),now()),
('12000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','roster.partial@example.test','',now(),now(),now()),
('12000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','roster.exception@example.test','',now(),now(),now()),
('12000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','roster.inactive@example.test','',now(),now(),now()),
('12000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','roster.ineligible@example.test','',now(),now(),now());

insert into public.staff(id,email,full_name,role,is_active) values
('22000000-0000-0000-0000-000000000001','roster.supervisor@example.test','Morgan Supervisor','supervisor',true),
('22000000-0000-0000-0000-000000000002','roster.available@example.test','Avery Available','employee',true),
('22000000-0000-0000-0000-000000000003','roster.partial@example.test','Parker Partial','employee',true),
('22000000-0000-0000-0000-000000000004','roster.exception@example.test','Casey Exception','employee',true),
('22000000-0000-0000-0000-000000000005','roster.inactive@example.test','Indigo Inactive','employee',false),
('22000000-0000-0000-0000-000000000006','roster.ineligible@example.test','Riley Ineligible','employee',true);
update auth.users set email_confirmed_at=email_confirmed_at+interval '1 second' where id::text like '12000000-%';

insert into public.staff_locations(staff_id,location_id)
select s.id,l.id from public.staff s cross join public.locations l
where s.id in ('22000000-0000-0000-0000-000000000002','22000000-0000-0000-0000-000000000003','22000000-0000-0000-0000-000000000004','22000000-0000-0000-0000-000000000005') and l.name='Clayton';
insert into public.staff_activity_types(staff_id,activity_type_id)
select s.id,a.id from public.staff s cross join public.activity_types a
where s.id in ('22000000-0000-0000-0000-000000000002','22000000-0000-0000-0000-000000000003','22000000-0000-0000-0000-000000000004','22000000-0000-0000-0000-000000000005') and a.name='Training';
insert into public.recurring_availability(staff_id,weekday,start_time,end_time,effective_start_date) values
('22000000-0000-0000-0000-000000000002',1,'09:00','17:00','2026-01-01'),
('22000000-0000-0000-0000-000000000003',1,'10:00','12:00','2026-01-01'),
('22000000-0000-0000-0000-000000000004',1,'09:00','17:00','2026-01-01'),
('22000000-0000-0000-0000-000000000005',1,'09:00','17:00','2026-01-01'),
('22000000-0000-0000-0000-000000000006',1,'09:00','17:00','2026-01-01');
insert into public.availability_exceptions(staff_id,local_date,kind,is_full_day)
values('22000000-0000-0000-0000-000000000004','2026-08-03','unavailable',true);

set local role authenticated;
select set_config('request.jwt.claim.sub','12000000-0000-0000-0000-000000000001',true);
create temp table roster_ids(key text primary key,id uuid);
grant select on roster_ids to authenticated;

select lives_ok($$
  insert into roster_ids values('shift1',public.save_shift(null,'Training coverage','2026-08-03','10:00','13:00',
    (select id from public.locations where name='Clayton'),
    (select id from public.activity_types where name='Training'),2,'Synthetic test shift'))
$$,'supervisor creates a shift');
select is((select required_staff_count from public.shifts where id=(select id from roster_ids where key='shift1')),2,'required staff count is stored');
select is((select shift_title from public.shifts where id=(select id from roster_ids where key='shift1')),'Training coverage','required shift title is stored');
select is((select details->>'shift_title' from public.roster_audit where action='SHIFT_CREATED' and shift_id=(select id from roster_ids where key='shift1')),'Training coverage','shift title is audited');
select throws_ok($$select public.save_shift(null,'Bad time','2026-08-03','13:00','10:00',
  (select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,null)$$,
  'Invalid shift time','invalid shift time is rejected');
select is((select (public.assignment_conflicts((select id from roster_ids where key='shift1'),'22000000-0000-0000-0000-000000000003')->0->>'code')),'PARTIALLY_AVAILABLE','partial availability is structured');
select is((select (public.assignment_conflicts((select id from roster_ids where key='shift1'),'22000000-0000-0000-0000-000000000004')->0->>'code')),'DATE_SPECIFIC_UNAVAILABLE','date exception is structured');
select ok(public.assignment_conflicts((select id from roster_ids where key='shift1'),'22000000-0000-0000-0000-000000000005') @> '[{"code":"INACTIVE_EMPLOYEE"}]','inactive employee conflict is returned');
select ok(public.assignment_conflicts((select id from roster_ids where key='shift1'),'22000000-0000-0000-0000-000000000006') @> '[{"code":"LOCATION_NOT_ELIGIBLE"},{"code":"ACTIVITY_NOT_ELIGIBLE"}]','location and activity conflicts are returned');
select lives_ok($$
  insert into roster_ids values('assignment1',public.assign_employee((select id from roster_ids where key='shift1'),
    '22000000-0000-0000-0000-000000000002','REGULAR',false,null))
$$,'fully available employee is assigned');
select throws_like($$select public.assign_employee((select id from roster_ids where key='shift1'),'22000000-0000-0000-0000-000000000002','REGULAR',true,'duplicate')$$,
  'Assignment has a non-overridable conflict:%','duplicate assignment cannot be overridden');

select lives_ok($$
  insert into roster_ids values('shift2',public.save_shift(null,'Overlapping session','2026-08-03','12:00','14:00',
    (select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,null))
$$,'second shift is created');
select throws_like($$select public.assign_employee((select id from roster_ids where key='shift2'),'22000000-0000-0000-0000-000000000002','REGULAR',true,'overlap')$$,
  'Assignment has a non-overridable conflict:%','overlap cannot be overridden');
select throws_ok($$select public.assign_employee((select id from roster_ids where key='shift1'),'22000000-0000-0000-0000-000000000003','SHADOWING',false,null)$$,
  'Override confirmation and written reason required','warning requires explicit override');
select lives_ok($$
  insert into roster_ids values('assignment2',public.assign_employee((select id from roster_ids where key='shift1'),
    '22000000-0000-0000-0000-000000000003','SHADOWING',true,'Supervisor accepts partial coverage for training'))
$$,'availability override with reason succeeds');
select is((select count(*) from public.roster_audit where action='ASSIGNMENT_OVERRIDDEN'),1::bigint,'override is audited');
select is((select regular_assigned_count from public.shift_staffing((select id from roster_ids where key='shift1'))),1::bigint,'shadowing does not count toward required staffing');
select is((select shadowing_count from public.shift_staffing((select id from roster_ids where key='shift1'))),1::bigint,'shadowing is retained as a real assignment');
select ok((select understaffed from public.shift_staffing((select id from roster_ids where key='shift1'))),'database staffing calculation remains understaffed');
select throws_like($$select public.assign_employee((select id from roster_ids where key='shift1'),'22000000-0000-0000-0000-000000000006','REGULAR',true,'eligibility override forbidden')$$,
  'Assignment has a non-overridable conflict:%','location and activity eligibility cannot be overridden');
select throws_ok($$select public.set_staff_active('22000000-0000-0000-0000-000000000002',false)$$,
  'Staff with future active assignments cannot be deactivated','future active assignment blocks deactivation');
select lives_ok($$select public.set_shift_status((select id from roster_ids where key='shift1'),'PUBLISHED',null)$$,'draft shift is published');
select lives_ok($$select public.set_shift_status((select id from roster_ids where key='shift1'),'DRAFT','Correcting published roster')$$,'published shift is deliberately unpublished');
select lives_ok($$select public.set_shift_status((select id from roster_ids where key='shift1'),'PUBLISHED',null)$$,'shift can be republished');
select lives_ok($$select public.replace_employee((select id from roster_ids where key='assignment2'),
  '22000000-0000-0000-0000-000000000004','SHADOWING',true,'Exception reviewed with employee','Coverage changed')$$,
  'replacement succeeds transactionally with override');
select ok((select removed_at is not null and replaced_by_assignment_id is not null from public.shift_assignments where id=(select id from roster_ids where key='assignment2')),'replaced assignment history is preserved');
select is((select assignment_kind::text from public.shift_assignments where id=(select replaced_by_assignment_id from public.shift_assignments where id=(select id from roster_ids where key='assignment2'))),'SHADOWING','replacement preserves the selected shadowing kind');
select throws_ok($$select public.save_shift(null,'Spring gap','2026-10-04','02:10','03:10',
  (select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,null)$$,
  'Invalid shift time','nonexistent Melbourne spring-forward Sunday boundary is rejected');
select lives_ok($$select public.save_shift(null,'Autumn repeat','2026-04-05','02:10','03:10',
  (select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,null)$$,
  'repeated Melbourne fall-back Sunday boundary is accepted');
select lives_ok($$select public.copy_shift((select id from roster_ids where key='shift1'),'2026-08-09')$$,
  'shift copies to Sunday');
select is((select count(*) from public.shifts where local_date='2026-08-09' and shift_title='Training coverage'),1::bigint,'Sunday copy retains shift title');

select set_config('request.jwt.claim.sub','12000000-0000-0000-0000-000000000002',true);
select is((select count(*) from public.shifts),1::bigint,'employee reads only a shift containing their active published assignment');
select is((select count(*) from public.shift_assignments),1::bigint,'employee reads only own active published assignment');
select throws_like($$select public.save_shift(null,'Not allowed','2026-08-03','09:00','10:00',
  (select id from public.locations limit 1),(select id from public.activity_types limit 1),1,null)$$,
  'Supervisor access required','employee cannot create a shift');
select throws_like($$select public.remove_employee((select id from roster_ids where key='assignment1'),'Not allowed')$$,
  'Supervisor access required','employee cannot remove assignments');
select throws_like($$insert into public.shift_assignments(shift_id,staff_id,assigned_by)
  values((select id from roster_ids where key='shift1'),'22000000-0000-0000-0000-000000000002','22000000-0000-0000-0000-000000000001')$$,
  'permission denied for table shift_assignments','employee has no direct assignment write');

select * from finish();
rollback;
