$ErrorActionPreference = 'Stop'
$container = docker ps --filter 'name=supabase_db_' --format '{{.Names}}' | Select-Object -First 1
if (-not $container) { throw 'Local Supabase database container is not running.' }

function Invoke-Sql([string]$sql) {
  $output = $sql | docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1
  if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
  return ($output -join "`n")
}

$setup = @'
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values('15000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ack.race.employee@example.test','',now(),now(),now());
insert into public.staff(id,email,full_name,role,is_active) values
('25000000-0000-0000-0000-000000000001','ack.race.supervisor@example.test','Acknowledgement Race Supervisor','supervisor',true),
('25000000-0000-0000-0000-000000000002','ack.race.employee@example.test','Acknowledgement Race Employee','employee',true);
update auth.users
set email_confirmed_at=email_confirmed_at+interval '1 second'
where id='15000000-0000-0000-0000-000000000001';
insert into public.shifts(
  id,shift_title,local_date,start_time,end_time,location_id,activity_type_id,
  required_staff_count,status,published_at,created_by,updated_by
) values (
  '35000000-0000-0000-0000-000000000001','Acknowledgement race shift','2026-08-17','09:00','10:00',
  (select id from public.locations where name='Clayton'),
  (select id from public.activity_types where name='Training'),
  1,'PUBLISHED',now(),
  '25000000-0000-0000-0000-000000000001','25000000-0000-0000-0000-000000000001'
);
insert into public.shift_assignments(id,shift_id,staff_id,assigned_by)
values(
  '45000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '25000000-0000-0000-0000-000000000002',
  '25000000-0000-0000-0000-000000000001'
);
'@
Invoke-Sql $setup | Out-Null

$runner = {
  param($containerName, $sql)
  $output = $sql | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1
  [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

$command = @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','15000000-0000-0000-0000-000000000001',true);
select public.acknowledge_assignment('45000000-0000-0000-0000-000000000001');
commit;
"@

$first = Start-Job -ScriptBlock $runner -ArgumentList $container, $command
$second = Start-Job -ScriptBlock $runner -ArgumentList $container, $command
$results = @(Wait-Job -Job @($first, $second) | Receive-Job)
Remove-Job $first, $second -Force

$counts = Invoke-Sql @'
select
  (select count(*) from public.shift_acknowledgements where assignment_id='45000000-0000-0000-0000-000000000001') as acknowledgement_count,
  (select count(*) from public.roster_audit where action='ASSIGNMENT_ACKNOWLEDGED' and assignment_id='45000000-0000-0000-0000-000000000001') as audit_count;
'@

$successes = @($results | Where-Object ExitCode -eq 0).Count
if ($successes -ne 2 -or $counts -notmatch '(?m)^\s*1\s*\|\s*1\s*$') {
  throw "Acknowledgement race was not idempotent.`n$($results.Output -join "`n")`n$counts"
}

Write-Output 'PASS: two concurrent acknowledgement sessions succeeded with one acknowledgement row and one audit event.'
