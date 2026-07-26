$ErrorActionPreference = 'Stop'
$container = docker ps --filter "name=supabase_db_" --format "{{.Names}}" | Select-Object -First 1
if (-not $container) { throw 'Local Supabase database container is not running.' }

function Invoke-Sql([string]$sql) {
  $output = $sql | docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1
  if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
  return ($output -join "`n")
}

$setup = @'
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values('13000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','concurrency.supervisor@example.test','',now(),now(),now());
insert into public.staff(id,email,full_name,role,is_active)
values('23000000-0000-0000-0000-000000000001','concurrency.supervisor@example.test','Concurrent Supervisor','supervisor',true);
update auth.users set email_confirmed_at=email_confirmed_at+interval '1 second' where id='13000000-0000-0000-0000-000000000001';
insert into public.staff(id,email,full_name,role,is_active) values
('23000000-0000-0000-0000-000000000002','concurrency.a@example.test','Concurrent A','employee',true),
('23000000-0000-0000-0000-000000000003','concurrency.b@example.test','Concurrent B','employee',true),
('23000000-0000-0000-0000-000000000004','concurrency.c@example.test','Concurrent C','employee',true);
insert into public.staff_locations(staff_id,location_id)
select s.id,l.id from public.staff s cross join public.locations l where s.id::text like '23000000-%' and s.role='employee' and l.name='Clayton';
insert into public.staff_activity_types(staff_id,activity_type_id)
select s.id,a.id from public.staff s cross join public.activity_types a where s.id::text like '23000000-%' and s.role='employee' and a.name='Training';
insert into public.recurring_availability(staff_id,weekday,start_time,end_time,effective_start_date)
select id,1,'08:00','18:00','2026-01-01' from public.staff where id::text like '23000000-%' and role='employee';
insert into public.shifts(id,shift_title,local_date,start_time,end_time,location_id,activity_type_id,required_staff_count,created_by,updated_by) values
('33000000-0000-0000-0000-000000000001','Duplicate race','2026-08-10','09:00','10:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,'23000000-0000-0000-0000-000000000001','23000000-0000-0000-0000-000000000001'),
('33000000-0000-0000-0000-000000000002','Overlap one','2026-08-10','11:00','13:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,'23000000-0000-0000-0000-000000000001','23000000-0000-0000-0000-000000000001'),
('33000000-0000-0000-0000-000000000003','Overlap two','2026-08-10','12:00','14:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,'23000000-0000-0000-0000-000000000001','23000000-0000-0000-0000-000000000001'),
('33000000-0000-0000-0000-000000000004','Replace one','2026-08-10','14:00','16:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,'23000000-0000-0000-0000-000000000001','23000000-0000-0000-0000-000000000001'),
('33000000-0000-0000-0000-000000000005','Replace two','2026-08-10','15:00','17:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,'23000000-0000-0000-0000-000000000001','23000000-0000-0000-0000-000000000001');
insert into public.shift_assignments(id,shift_id,staff_id,assigned_by) values
('43000000-0000-0000-0000-000000000001','33000000-0000-0000-0000-000000000004','23000000-0000-0000-0000-000000000002','23000000-0000-0000-0000-000000000001'),
('43000000-0000-0000-0000-000000000002','33000000-0000-0000-0000-000000000005','23000000-0000-0000-0000-000000000003','23000000-0000-0000-0000-000000000001');
'@
Invoke-Sql $setup | Out-Null

$runner = {
  param($containerName, $sql)
  $output = $sql | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1
  [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

function Invoke-Race([string]$sqlOne, [string]$sqlTwo, [string]$label) {
  $first = Start-Job -ScriptBlock $runner -ArgumentList $container, $sqlOne
  $second = Start-Job -ScriptBlock $runner -ArgumentList $container, $sqlTwo
  $results = @(Wait-Job -Job @($first, $second) | Receive-Job)
  Remove-Job $first, $second -Force
  $successes = @($results | Where-Object ExitCode -eq 0).Count
  $failures = @($results | Where-Object ExitCode -ne 0)
  if ($successes -ne 1 -or $failures.Count -ne 1 -or $failures[0].Output -notmatch 'non-overridable conflict') {
    throw "$label did not serialize safely.`n$($results.Output -join "`n")"
  }
  Write-Output "PASS: $label (one commit, one conflict rejection)"
}

$prefix = "begin; set local role authenticated; select set_config('request.jwt.claim.sub','13000000-0000-0000-0000-000000000001',true);"
Invoke-Race "$prefix select public.assign_employee('33000000-0000-0000-0000-000000000001','23000000-0000-0000-0000-000000000002','REGULAR',false,null); select pg_sleep(1); commit;" `
  "$prefix select public.assign_employee('33000000-0000-0000-0000-000000000001','23000000-0000-0000-0000-000000000002','REGULAR',false,null); commit;" `
  'duplicate assignment race'
Invoke-Race "$prefix select public.assign_employee('33000000-0000-0000-0000-000000000002','23000000-0000-0000-0000-000000000003','REGULAR',false,null); select pg_sleep(1); commit;" `
  "$prefix select public.assign_employee('33000000-0000-0000-0000-000000000003','23000000-0000-0000-0000-000000000003','REGULAR',false,null); commit;" `
  'overlapping assignment race'
Invoke-Race "$prefix select public.replace_employee('43000000-0000-0000-0000-000000000001','23000000-0000-0000-0000-000000000004','REGULAR',false,null,'Concurrent replacement'); select pg_sleep(1); commit;" `
  "$prefix select public.replace_employee('43000000-0000-0000-0000-000000000002','23000000-0000-0000-0000-000000000004','REGULAR',false,null,'Concurrent replacement'); commit;" `
  'conflicting replacement race'
