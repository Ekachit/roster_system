begin;
select plan(23);

insert into auth.users (id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
('14000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m4.supervisor@example.test','',now(),now(),now()),
('14000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m4.employee.one@example.test','',now(),now(),now()),
('14000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m4.employee.two@example.test','',now(),now(),now());

insert into public.staff(id,email,full_name,role,is_active) values
('24000000-0000-0000-0000-000000000001','m4.supervisor@example.test','Synthetic Supervisor','supervisor',true),
('24000000-0000-0000-0000-000000000002','m4.employee.one@example.test','Synthetic Employee One','employee',true),
('24000000-0000-0000-0000-000000000003','m4.employee.two@example.test','Synthetic Employee Two','employee',true);
update auth.users set email_confirmed_at=email_confirmed_at+interval '1 second' where id::text like '14000000-%';

insert into public.staff_locations(staff_id,location_id)
select staff.id, location.id
from public.staff staff cross join public.locations location
where staff.id in ('24000000-0000-0000-0000-000000000002','24000000-0000-0000-0000-000000000003')
  and location.name = 'Clayton';
insert into public.staff_activity_types(staff_id,activity_type_id)
select staff.id, activity.id
from public.staff staff cross join public.activity_types activity
where staff.id in ('24000000-0000-0000-0000-000000000002','24000000-0000-0000-0000-000000000003')
  and activity.name = 'Training';
insert into public.recurring_availability(staff_id,weekday,start_time,end_time,effective_start_date)
select staff_id, weekday, '08:00', '17:00', '2026-01-01'
from (values
  ('24000000-0000-0000-0000-000000000002'::uuid),
  ('24000000-0000-0000-0000-000000000003'::uuid)
) employee(staff_id)
cross join generate_series(1, 7) weekday;

set local role authenticated;
select set_config('request.jwt.claim.sub','14000000-0000-0000-0000-000000000001',true);
create temp table m4_ids(key text primary key,id uuid);
grant select on m4_ids to authenticated;

insert into m4_ids values
('own_shift', public.save_shift(null,'Synthetic published shift','2026-08-10','09:00','10:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),2,'Employee-visible notes')),
('draft_shift', public.save_shift(null,'Synthetic draft shift','2026-08-11','09:00','10:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,null)),
('other_shift', public.save_shift(null,'Synthetic unrelated shift','2026-08-12','09:00','10:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,null)),
('cancelled_shift', public.save_shift(null,'Synthetic cancelled shift','2026-08-13','09:00','10:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,null)),
('removed_shift', public.save_shift(null,'Synthetic removed assignment','2026-08-14','09:00','10:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,null)),
('saturday_shift', public.save_shift(null,'Synthetic Saturday shadow shift','2026-08-15','09:00','10:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,null)),
('sunday_shift', public.save_shift(null,'Synthetic Sunday regular shift','2026-08-16','09:00','10:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,null));

insert into m4_ids values
('own_assignment', public.assign_employee((select id from m4_ids where key='own_shift'),'24000000-0000-0000-0000-000000000002','REGULAR',true,'Synthetic Milestone 4 test override')),
('colleague_assignment', public.assign_employee((select id from m4_ids where key='own_shift'),'24000000-0000-0000-0000-000000000003','REGULAR',true,'Synthetic Milestone 4 test override')),
('draft_assignment', public.assign_employee((select id from m4_ids where key='draft_shift'),'24000000-0000-0000-0000-000000000002','REGULAR',true,'Synthetic Milestone 4 test override')),
('other_assignment', public.assign_employee((select id from m4_ids where key='other_shift'),'24000000-0000-0000-0000-000000000003','REGULAR',true,'Synthetic Milestone 4 test override')),
('cancelled_assignment', public.assign_employee((select id from m4_ids where key='cancelled_shift'),'24000000-0000-0000-0000-000000000002','REGULAR',true,'Synthetic Milestone 4 test override')),
('removed_assignment', public.assign_employee((select id from m4_ids where key='removed_shift'),'24000000-0000-0000-0000-000000000002','REGULAR',true,'Synthetic Milestone 4 test override')),
('saturday_assignment', public.assign_employee((select id from m4_ids where key='saturday_shift'),'24000000-0000-0000-0000-000000000002','SHADOWING',false,null)),
('sunday_assignment', public.assign_employee((select id from m4_ids where key='sunday_shift'),'24000000-0000-0000-0000-000000000002','REGULAR',false,null));

select public.set_shift_status((select id from m4_ids where key='own_shift'),'PUBLISHED',null);
select public.set_shift_status((select id from m4_ids where key='other_shift'),'PUBLISHED',null);
select public.set_shift_status((select id from m4_ids where key='cancelled_shift'),'PUBLISHED',null);
select public.set_shift_status((select id from m4_ids where key='cancelled_shift'),'CANCELLED','Synthetic cancellation');
select public.set_shift_status((select id from m4_ids where key='removed_shift'),'PUBLISHED',null);
select public.remove_employee((select id from m4_ids where key='removed_assignment'),'Synthetic removal');
select public.set_shift_status((select id from m4_ids where key='saturday_shift'),'PUBLISHED',null);
select public.set_shift_status((select id from m4_ids where key='sunday_shift'),'PUBLISHED',null);

select set_config('request.jwt.claim.sub','14000000-0000-0000-0000-000000000002',true);
select is((select count(*) from public.employee_schedule()),4::bigint,'employee schedule contains active published assignments and own cancelled history');
select is((select count(*) from public.employee_schedule() where shift_status='PUBLISHED'),3::bigint,'employee active schedule excludes cancelled history');
select ok((select shift_title='Synthetic published shift' and assignment_kind='REGULAR' from public.employee_schedule() where shift_id=(select id from m4_ids where key='own_shift')),'published title and regular kind are returned');
select ok((select shift_title='Synthetic Saturday shadow shift' and assignment_kind='SHADOWING' and extract(dow from local_date)=6 from public.employee_schedule() where shift_id=(select id from m4_ids where key='saturday_shift')),'Saturday title and shadowing kind are returned');
select ok((select shift_title='Synthetic Sunday regular shift' and assignment_kind='REGULAR' and extract(dow from local_date)=0 from public.employee_schedule() where shift_id=(select id from m4_ids where key='sunday_shift')),'Sunday title and regular kind are returned');
select is((select count(*) from public.employee_schedule() where shift_title='Synthetic cancelled shift'),1::bigint,'employee can access own cancelled shift history and detail data');
select is((select assignment_status from public.employee_schedule() where shift_title='Synthetic cancelled shift'),'CANCELLED','cancelled assignment is clearly marked');
select is((select count(*) from public.employee_schedule() where shift_title='Synthetic draft shift'),0::bigint,'employee does not see draft shift');
select is((select count(*) from public.employee_schedule() where shift_title='Synthetic unrelated shift'),0::bigint,'employee does not see unrelated employee shift');
select is((select count(*) from public.employee_schedule() where shift_title='Synthetic removed assignment'),0::bigint,'removed assignment is not active in employee schedule');
select is((select colleague_names from public.employee_schedule() where shift_id=(select id from m4_ids where key='own_shift')),array['Synthetic Employee Two']::text[],'co-worker response contains the assigned colleague name');
select throws_like($$select id,created_by,updated_by,published_at from public.shifts$$,'permission denied for table shifts','employee cannot retrieve internal shift columns from the base table');
select throws_like($$select id,assigned_by,override_reason,removed_by,removal_reason from public.shift_assignments$$,'permission denied for table shift_assignments','employee cannot retrieve internal assignment columns from the base table');
select throws_like($$select * from public.supervisor_roster_shifts(null,null)$$,'Supervisor access required','employee cannot call the supervisor shift projection');
select throws_like($$select * from public.supervisor_roster_assignments()$$,'Supervisor access required','employee cannot call the supervisor assignment projection');

select lives_ok($$select public.acknowledge_assignment((select id from m4_ids where key='own_assignment'))$$,'employee acknowledges own active published assignment');
select is((select count(*) from public.shift_acknowledgements),1::bigint,'employee reads own acknowledgement');
select lives_ok($$select public.acknowledge_assignment((select id from m4_ids where key='own_assignment'))$$,'repeated acknowledgement is safe');
select set_config('request.jwt.claim.sub','14000000-0000-0000-0000-000000000001',true);
select is((select count(*) from public.roster_audit where action='ASSIGNMENT_ACKNOWLEDGED' and assignment_id=(select id from m4_ids where key='own_assignment')),1::bigint,'idempotent acknowledgement writes one audit event');
select set_config('request.jwt.claim.sub','14000000-0000-0000-0000-000000000002',true);
select throws_like($$select public.acknowledge_assignment((select id from m4_ids where key='other_assignment'))$$,'Active published assignment not found','employee cannot acknowledge another employee assignment');
select throws_like($$select public.acknowledge_assignment((select id from m4_ids where key='cancelled_assignment'))$$,'Active published assignment not found','employee cannot acknowledge a cancelled assignment');
select throws_like($$select public.acknowledge_assignment((select id from m4_ids where key='removed_assignment'))$$,'Active published assignment not found','employee cannot acknowledge a removed assignment');
select throws_like($$update public.shifts set notes='Forbidden' where id=(select id from m4_ids where key='own_shift')$$,'permission denied for table shifts','employee cannot modify shift details');

select * from finish();
rollback;
