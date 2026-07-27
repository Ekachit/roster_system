$ErrorActionPreference = 'Stop'
if (-not $env:M4_BROWSER_PASSWORD) { throw 'M4_BROWSER_PASSWORD is required.' }
$container = docker ps --filter 'name=supabase_db_' --format '{{.Names}}' | Select-Object -First 1
if (-not $container) { throw 'Local Supabase database container is not running.' }

$escapedPassword = $env:M4_BROWSER_PASSWORD.Replace("'", "''")
$sql = @"
insert into public.staff(id,email,full_name,role,is_active) values
('26000000-0000-0000-0000-000000000001','m4.browser.supervisor@example.test','M4 Browser Supervisor','supervisor',true),
('26000000-0000-0000-0000-000000000002','m4.browser.employee@example.test','M4 Browser Employee','employee',true),
('26000000-0000-0000-0000-000000000003','m4.browser.colleague@example.test','M4 Browser Colleague','employee',true);
insert into auth.users(
  id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
  confirmation_token,recovery_token,email_change_token_new,email_change,
  phone_change_token,email_change_token_current,reauthentication_token,created_at,updated_at
) values
('16000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'm4.browser.employee@example.test',crypt('$escapedPassword',gen_salt('bf')),now(),'','','','','','','',now(),now());
update auth.users
set email_confirmed_at=email_confirmed_at+interval '1 second'
where id='16000000-0000-0000-0000-000000000001';

insert into public.shifts(
  id,shift_title,local_date,start_time,end_time,location_id,activity_type_id,
  required_staff_count,notes,status,published_at,cancelled_at,created_by,updated_by
) values
('36000000-0000-0000-0000-000000000001','Synthetic Saturday regular coverage','2026-08-01','09:00','11:00',
 (select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),
 1,'Desktop and mobile regular details','PUBLISHED',now(),null,
 '26000000-0000-0000-0000-000000000001','26000000-0000-0000-0000-000000000001'),
('36000000-0000-0000-0000-000000000002','Synthetic Sunday shadow coverage','2026-08-02','12:00','14:00',
 (select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),
 1,'Desktop and mobile shadow details','PUBLISHED',now(),null,
 '26000000-0000-0000-0000-000000000001','26000000-0000-0000-0000-000000000001'),
('36000000-0000-0000-0000-000000000003','Synthetic cancelled shadow history','2026-07-31','15:00','16:00',
 (select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),
 1,'Cancelled employee-visible details','CANCELLED',now()-interval '1 hour',now(),
 '26000000-0000-0000-0000-000000000001','26000000-0000-0000-0000-000000000001');

insert into public.shift_assignments(id,shift_id,staff_id,assignment_kind,assigned_by) values
('46000000-0000-0000-0000-000000000001','36000000-0000-0000-0000-000000000001','26000000-0000-0000-0000-000000000002','REGULAR','26000000-0000-0000-0000-000000000001'),
('46000000-0000-0000-0000-000000000002','36000000-0000-0000-0000-000000000002','26000000-0000-0000-0000-000000000002','SHADOWING','26000000-0000-0000-0000-000000000001'),
('46000000-0000-0000-0000-000000000003','36000000-0000-0000-0000-000000000003','26000000-0000-0000-0000-000000000002','SHADOWING','26000000-0000-0000-0000-000000000001'),
('46000000-0000-0000-0000-000000000004','36000000-0000-0000-0000-000000000001','26000000-0000-0000-0000-000000000003','REGULAR','26000000-0000-0000-0000-000000000001'),
('46000000-0000-0000-0000-000000000005','36000000-0000-0000-0000-000000000003','26000000-0000-0000-0000-000000000003','REGULAR','26000000-0000-0000-0000-000000000001');
"@

$sql | docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output 'Synthetic Milestone 4 browser fixtures created.'
