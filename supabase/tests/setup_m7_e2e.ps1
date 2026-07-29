$ErrorActionPreference = 'Stop'
if (-not $env:M7_E2E_PASSWORD) { throw 'M7_E2E_PASSWORD is required.' }

$container = docker ps --filter 'name=supabase_db_' --format '{{.Names}}' |
  Where-Object { $_ -like '*ai-fitness-zone-roster*' } |
  Select-Object -First 1
if (-not $container) { throw 'Local Supabase database container is not running.' }

$escapedPassword = $env:M7_E2E_PASSWORD.Replace("'", "''")
$sql = @"
insert into public.staff(id,email,full_name,role,is_active) values
('2a000000-0000-0000-0000-000000000001','m7.e2e.supervisor@example.test','M7 E2E Supervisor','supervisor',true),
('2a000000-0000-0000-0000-000000000002','m7.e2e.employee@example.test','M7 E2E Employee','employee',true),
('2a000000-0000-0000-0000-000000000003','m7.e2e.replacement@example.test','M7 E2E Replacement','employee',true);

insert into auth.users(
  id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
  confirmation_token,recovery_token,email_change_token_new,email_change,
  phone_change_token,email_change_token_current,reauthentication_token,created_at,updated_at
) values
('1a000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'm7.e2e.supervisor@example.test',crypt('$escapedPassword',gen_salt('bf')),now(),'','','','','','','',now(),now()),
('1a000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'm7.e2e.employee@example.test',crypt('$escapedPassword',gen_salt('bf')),now(),'','','','','','','',now(),now());

update auth.users
set email_confirmed_at=email_confirmed_at+interval '1 second'
where id in (
  '1a000000-0000-0000-0000-000000000001',
  '1a000000-0000-0000-0000-000000000002'
);

insert into public.staff_locations(staff_id,location_id)
select employee.id, location.id
from public.staff employee cross join public.locations location
where employee.id in (
  '2a000000-0000-0000-0000-000000000002',
  '2a000000-0000-0000-0000-000000000003'
) and location.name='Clayton';

insert into public.staff_activity_types(staff_id,activity_type_id)
select employee.id, activity.id
from public.staff employee cross join public.activity_types activity
where employee.id in (
  '2a000000-0000-0000-0000-000000000002',
  '2a000000-0000-0000-0000-000000000003'
) and activity.name='Training';

insert into public.recurring_availability(
  staff_id,weekday,start_time,end_time,effective_start_date,note
) values (
  '2a000000-0000-0000-0000-000000000003',
  7,'08:00','17:00','2026-01-01','Synthetic replacement availability'
);
"@

$sql | docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output 'Synthetic Milestone 7 end-to-end fixtures created.'
