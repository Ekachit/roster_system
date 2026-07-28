$ErrorActionPreference = 'Stop'
if (-not $env:M5_BROWSER_PASSWORD) { throw 'M5_BROWSER_PASSWORD is required.' }
$container = docker ps --filter 'name=supabase_db_' --format '{{.Names}}' | Select-Object -First 1
if (-not $container) { throw 'Local Supabase database container is not running.' }

$escapedPassword = $env:M5_BROWSER_PASSWORD.Replace("'", "''")
$sql = @"
insert into public.staff(id,email,full_name,role,is_active) values
('27000000-0000-0000-0000-000000000001','m5.browser.supervisor@example.test','M5 Browser Supervisor','supervisor',true),
('27000000-0000-0000-0000-000000000002','m5.browser.employee@example.test','M5 Browser Employee','employee',true),
('27000000-0000-0000-0000-000000000003','m5.browser.replacement@example.test','M5 Browser Replacement','employee',true);

insert into auth.users(
  id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
  confirmation_token,recovery_token,email_change_token_new,email_change,
  phone_change_token,email_change_token_current,reauthentication_token,created_at,updated_at
) values
('17000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'm5.browser.supervisor@example.test',crypt('$escapedPassword',gen_salt('bf')),now(),'','','','','','','',now(),now()),
('17000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'm5.browser.employee@example.test',crypt('$escapedPassword',gen_salt('bf')),now(),'','','','','','','',now(),now());
update auth.users
set email_confirmed_at=email_confirmed_at+interval '1 second'
where id in (
  '17000000-0000-0000-0000-000000000001',
  '17000000-0000-0000-0000-000000000002'
);

insert into public.staff_locations(staff_id,location_id)
select employee.id, location.id
from public.staff employee cross join public.locations location
where employee.id in (
  '27000000-0000-0000-0000-000000000002',
  '27000000-0000-0000-0000-000000000003'
) and location.name='Clayton';

insert into public.staff_activity_types(staff_id,activity_type_id)
select employee.id, activity.id
from public.staff employee cross join public.activity_types activity
where employee.id in (
  '27000000-0000-0000-0000-000000000002',
  '27000000-0000-0000-0000-000000000003'
) and activity.name='Training';

insert into public.recurring_availability(
  staff_id,weekday,start_time,end_time,effective_start_date
)
select employee.staff_id, weekday, '08:00', '17:00', '2026-01-01'
from (values
  ('27000000-0000-0000-0000-000000000002'::uuid),
  ('27000000-0000-0000-0000-000000000003'::uuid)
) employee(staff_id)
cross join generate_series(1,7) weekday;

insert into public.shifts(
  id,shift_title,local_date,start_time,end_time,location_id,activity_type_id,
  required_staff_count,notes,status,published_at,created_by,updated_by
) values (
  '37000000-0000-0000-0000-000000000001',
  'Synthetic release workflow shift',
  '2026-08-30','09:00','11:00',
  (select id from public.locations where name='Clayton'),
  (select id from public.activity_types where name='Training'),
  1,'Synthetic Milestone 5 browser details','PUBLISHED',now(),
  '27000000-0000-0000-0000-000000000001',
  '27000000-0000-0000-0000-000000000001'
), (
  '37000000-0000-0000-0000-000000000002',
  'Synthetic cancelled release shift',
  '2026-08-29','13:00','15:00',
  (select id from public.locations where name='Clayton'),
  (select id from public.activity_types where name='Training'),
  1,'Synthetic externally removed request history','PUBLISHED',now(),
  '27000000-0000-0000-0000-000000000001',
  '27000000-0000-0000-0000-000000000001'
);

insert into public.shift_assignments(
  id,shift_id,staff_id,assignment_kind,assigned_by,
  removed_at,removed_by,removal_reason
) values (
  '47000000-0000-0000-0000-000000000001',
  '37000000-0000-0000-0000-000000000001',
  '27000000-0000-0000-0000-000000000002',
  'REGULAR',
  '27000000-0000-0000-0000-000000000001',
  null,null,null
), (
  '47000000-0000-0000-0000-000000000002',
  '37000000-0000-0000-0000-000000000002',
  '27000000-0000-0000-0000-000000000002',
  'REGULAR',
  '27000000-0000-0000-0000-000000000001',
  now(),'27000000-0000-0000-0000-000000000001',
  'Synthetic independent assignment removal'
);

insert into public.release_requests(
  id,assignment_id,staff_id,reason,note,status,submitted_at,
  resolved_at,resolved_by,resolution_reason
) values (
  '57000000-0000-0000-0000-000000000002',
  '47000000-0000-0000-0000-000000000002',
  '27000000-0000-0000-0000-000000000002',
  'Synthetic historical request',
  'Synthetic cancelled status fixture',
  'CANCELLED',
  now() - interval '2 hours',
  now() - interval '1 hour',
  '27000000-0000-0000-0000-000000000001',
  'Cancelled because the assignment was independently removed.'
);
"@

$sql | docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output 'Synthetic Milestone 5 browser fixtures created.'
