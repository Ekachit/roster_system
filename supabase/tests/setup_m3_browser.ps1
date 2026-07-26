$ErrorActionPreference = 'Stop'
if (-not $env:M3_BROWSER_PASSWORD) { throw 'M3_BROWSER_PASSWORD is required.' }
$container = docker ps --filter 'name=supabase_db_' --format '{{.Names}}' | Select-Object -First 1
if (-not $container) { throw 'Local Supabase database container is not running.' }

$escapedPassword = $env:M3_BROWSER_PASSWORD.Replace("'", "''")
$sql = @"
insert into public.staff(id,email,full_name,role,is_active) values
('24000000-0000-0000-0000-000000000001','browser.supervisor@example.test','Browser Supervisor','supervisor',true),
('24000000-0000-0000-0000-000000000002','browser.employee@example.test','Bailey Browser Employee','employee',true);
insert into auth.users(
  id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
  confirmation_token,recovery_token,email_change_token_new,email_change,
  phone_change_token,email_change_token_current,reauthentication_token,created_at,updated_at
) values
('14000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'browser.supervisor@example.test',crypt('$escapedPassword',gen_salt('bf')),now(),'','','','','','','',now(),now()),
('14000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'browser.employee@example.test',crypt('$escapedPassword',gen_salt('bf')),now(),'','','','','','','',now(),now());
insert into public.staff_locations
select '24000000-0000-0000-0000-000000000002',id,now() from public.locations where name='Clayton';
insert into public.staff_activity_types
select '24000000-0000-0000-0000-000000000002',id,now() from public.activity_types where name='Training';
insert into public.recurring_availability(staff_id,weekday,start_time,end_time,effective_start_date)
values('24000000-0000-0000-0000-000000000002',7,'09:00','17:00','2026-01-01');
"@
$sql | docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output 'Synthetic browser fixtures created.'
