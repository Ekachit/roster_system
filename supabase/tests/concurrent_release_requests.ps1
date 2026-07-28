$ErrorActionPreference = 'Stop'
$container = docker ps --filter 'name=supabase_db_' --format '{{.Names}}' | Select-Object -First 1
if (-not $container) { throw 'Local Supabase database container is not running.' }

function Invoke-Sql([string]$sql) {
  $output = $sql | docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1
  if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
  return ($output -join "`n")
}

$setup = @'
insert into auth.users(
  id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at
) values
('18000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','release.race.supervisor.one@example.test','',now(),now(),now()),
('18000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','release.race.supervisor.two@example.test','',now(),now(),now()),
('18000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','release.race.employee@example.test','',now(),now(),now());

insert into public.staff(id,email,full_name,role,is_active) values
('28000000-0000-0000-0000-000000000001','release.race.supervisor.one@example.test','Release Race Supervisor One','supervisor',true),
('28000000-0000-0000-0000-000000000002','release.race.supervisor.two@example.test','Release Race Supervisor Two','supervisor',true),
('28000000-0000-0000-0000-000000000003','release.race.employee@example.test','Release Race Employee','employee',true),
('28000000-0000-0000-0000-000000000004','release.race.replacement.one@example.test','Release Race Replacement One','employee',true),
('28000000-0000-0000-0000-000000000005','release.race.replacement.two@example.test','Release Race Replacement Two','employee',true);

update auth.users
set email_confirmed_at=email_confirmed_at+interval '1 second'
where id::text like '18000000-%';

insert into public.staff_locations(staff_id,location_id)
select staff.id,location.id
from public.staff staff cross join public.locations location
where staff.id in (
  '28000000-0000-0000-0000-000000000003',
  '28000000-0000-0000-0000-000000000004',
  '28000000-0000-0000-0000-000000000005'
) and location.name='Clayton';

insert into public.staff_activity_types(staff_id,activity_type_id)
select staff.id,activity.id
from public.staff staff cross join public.activity_types activity
where staff.id in (
  '28000000-0000-0000-0000-000000000003',
  '28000000-0000-0000-0000-000000000004',
  '28000000-0000-0000-0000-000000000005'
) and activity.name='Training';

insert into public.recurring_availability(
  staff_id,weekday,start_time,end_time,effective_start_date
)
select staff_id,weekday,'08:00','17:00','2026-01-01'
from (values
  ('28000000-0000-0000-0000-000000000003'::uuid),
  ('28000000-0000-0000-0000-000000000004'::uuid),
  ('28000000-0000-0000-0000-000000000005'::uuid)
) employee(staff_id)
cross join generate_series(1,7) weekday;

insert into public.shifts(
  id,shift_title,local_date,start_time,end_time,location_id,activity_type_id,
  required_staff_count,status,published_at,created_by,updated_by
) values
('38000000-0000-0000-0000-000000000001','Concurrent resolution','2026-09-14','09:00','10:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,'PUBLISHED',now(),'28000000-0000-0000-0000-000000000001','28000000-0000-0000-0000-000000000001'),
('38000000-0000-0000-0000-000000000002','Concurrent submission removal','2026-09-15','09:00','10:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,'PUBLISHED',now(),'28000000-0000-0000-0000-000000000001','28000000-0000-0000-0000-000000000001'),
('38000000-0000-0000-0000-000000000003','Concurrent approval cancellation','2026-09-16','09:00','10:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,'PUBLISHED',now(),'28000000-0000-0000-0000-000000000001','28000000-0000-0000-0000-000000000001'),
('38000000-0000-0000-0000-000000000004','Concurrent replacement approval','2026-09-17','09:00','10:00',(select id from public.locations where name='Clayton'),(select id from public.activity_types where name='Training'),1,'PUBLISHED',now(),'28000000-0000-0000-0000-000000000001','28000000-0000-0000-0000-000000000001');

insert into public.shift_assignments(
  id,shift_id,staff_id,assignment_kind,assigned_by
) values
('48000000-0000-0000-0000-000000000001','38000000-0000-0000-0000-000000000001','28000000-0000-0000-0000-000000000003','REGULAR','28000000-0000-0000-0000-000000000001'),
('48000000-0000-0000-0000-000000000002','38000000-0000-0000-0000-000000000002','28000000-0000-0000-0000-000000000003','REGULAR','28000000-0000-0000-0000-000000000001'),
('48000000-0000-0000-0000-000000000003','38000000-0000-0000-0000-000000000003','28000000-0000-0000-0000-000000000003','REGULAR','28000000-0000-0000-0000-000000000001'),
('48000000-0000-0000-0000-000000000004','38000000-0000-0000-0000-000000000004','28000000-0000-0000-0000-000000000003','REGULAR','28000000-0000-0000-0000-000000000001');

insert into public.release_requests(id,assignment_id,staff_id,reason) values
('58000000-0000-0000-0000-000000000001','48000000-0000-0000-0000-000000000001','28000000-0000-0000-0000-000000000003','Concurrent resolution'),
('58000000-0000-0000-0000-000000000003','48000000-0000-0000-0000-000000000003','28000000-0000-0000-0000-000000000003','Concurrent cancellation'),
('58000000-0000-0000-0000-000000000004','48000000-0000-0000-0000-000000000004','28000000-0000-0000-0000-000000000003','Concurrent replacement');
'@
Invoke-Sql $setup | Out-Null

$runner = {
  param($containerName, $sql)
  $output = $sql | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1
  [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

function Invoke-Race(
  [string]$sqlOne,
  [string]$sqlTwo,
  [int]$expectedSuccesses,
  [string]$label
) {
  $first = Start-Job -ScriptBlock $runner -ArgumentList $container, $sqlOne
  $second = Start-Job -ScriptBlock $runner -ArgumentList $container, $sqlTwo
  $results = @(Wait-Job -Job @($first, $second) | Receive-Job)
  Remove-Job $first, $second -Force
  $successes = @($results | Where-Object ExitCode -eq 0).Count
  if ($successes -ne $expectedSuccesses) {
    throw "$label produced $successes successes; expected $expectedSuccesses.`n$($results.Output -join "`n")"
  }
  return $results
}

function Assert-Match([string]$value, [string]$pattern, [string]$message) {
  if ($value -notmatch $pattern) { throw "$message`n$value" }
}

$supervisorOne = "set local role authenticated; select set_config('request.jwt.claim.sub','18000000-0000-0000-0000-000000000001',true); set local lock_timeout='8s'; set local statement_timeout='20s';"
$supervisorTwo = "set local role authenticated; select set_config('request.jwt.claim.sub','18000000-0000-0000-0000-000000000002',true); set local lock_timeout='8s'; set local statement_timeout='20s';"
$employee = "set local role authenticated; select set_config('request.jwt.claim.sub','18000000-0000-0000-0000-000000000003',true); set local lock_timeout='8s'; set local statement_timeout='20s';"

$shiftOneLock = "select pg_advisory_xact_lock(hashtextextended('release-shift:38000000-0000-0000-0000-000000000001',0));"
$raceOne = Invoke-Race `
  "begin; $supervisorOne $shiftOneLock select pg_sleep(2); select public.reject_release_request('58000000-0000-0000-0000-000000000001','Concurrent rejection wins'); commit;" `
  "begin; $supervisorTwo select public.approve_release_request_remove('58000000-0000-0000-0000-000000000001','Competing approval'); commit;" `
  1 `
  'two-supervisor resolution race'
$raceOneState = Invoke-Sql @'
select
  (select status from public.release_requests where id='58000000-0000-0000-0000-000000000001'),
  (select removed_at is null from public.shift_assignments where id='48000000-0000-0000-0000-000000000001'),
  (select count(*) from public.roster_audit where release_request_id='58000000-0000-0000-0000-000000000001' and action in ('RELEASE_REQUEST_APPROVED','RELEASE_REQUEST_REJECTED','RELEASE_REQUEST_CANCELLED'));
'@
Assert-Match $raceOneState '(?m)REJECTED\s*\|\s*t\s*\|\s*1' 'Two-supervisor race left conflicting state or audit.'
Assert-Match ($raceOne.Output -join "`n") 'Pending release request not found' 'Losing supervisor did not receive a stale-terminal rejection.'
Write-Output 'PASS: two supervisors resolving one request produced one rejected terminal outcome and one terminal audit.'

$shiftTwoLock = "select pg_advisory_xact_lock(hashtextextended('release-shift:38000000-0000-0000-0000-000000000002',0));"
$raceTwo = Invoke-Race `
  "begin; $employee $shiftTwoLock select pg_sleep(2); select public.submit_release_request('48000000-0000-0000-0000-000000000002','Concurrent submission',null); commit;" `
  "begin; $supervisorOne select public.remove_employee('48000000-0000-0000-0000-000000000002','Concurrent direct removal'); commit;" `
  2 `
  'submission-removal race'
$raceTwoState = Invoke-Sql @'
select
  (select count(*) from public.release_requests where assignment_id='48000000-0000-0000-0000-000000000002'),
  (select status from public.release_requests where assignment_id='48000000-0000-0000-0000-000000000002'),
  (select removed_at is not null from public.shift_assignments where id='48000000-0000-0000-0000-000000000002'),
  (select count(*) from public.roster_audit where assignment_id='48000000-0000-0000-0000-000000000002' and action='RELEASE_REQUEST_CANCELLED'),
  (select count(*) from public.roster_audit where assignment_id='48000000-0000-0000-0000-000000000002' and action='RELEASE_REQUEST_APPROVED');
'@
Assert-Match $raceTwoState '(?m)1\s*\|\s*CANCELLED\s*\|\s*t\s*\|\s*1\s*\|\s*0' 'Submission-removal race did not end in one clean cancellation.'
Write-Output 'PASS: submission racing direct removal committed one request, cancelled it once, and removed the assignment.'

$shiftThreeLock = "select pg_advisory_xact_lock(hashtextextended('release-shift:38000000-0000-0000-0000-000000000003',0));"
$raceThree = Invoke-Race `
  "begin; $supervisorOne $shiftThreeLock select pg_sleep(2); select public.set_shift_status('38000000-0000-0000-0000-000000000003','CANCELLED','Concurrent shift cancellation'); commit;" `
  "begin; $supervisorTwo select public.approve_release_request_remove('58000000-0000-0000-0000-000000000003','Competing release approval'); commit;" `
  1 `
  'approval-cancellation race'
$raceThreeState = Invoke-Sql @'
select
  (select status from public.release_requests where id='58000000-0000-0000-0000-000000000003'),
  (select status from public.shifts where id='38000000-0000-0000-0000-000000000003'),
  (select removed_at is null from public.shift_assignments where id='48000000-0000-0000-0000-000000000003'),
  (select count(*) from public.roster_audit where release_request_id='58000000-0000-0000-0000-000000000003' and action='RELEASE_REQUEST_CANCELLED'),
  (select count(*) from public.roster_audit where release_request_id='58000000-0000-0000-0000-000000000003' and action='RELEASE_REQUEST_APPROVED');
'@
Assert-Match $raceThreeState '(?m)CANCELLED\s*\|\s*CANCELLED\s*\|\s*t\s*\|\s*1\s*\|\s*0' 'Approval-cancellation race left contradictory lifecycle or audit state.'
Assert-Match ($raceThree.Output -join "`n") 'Pending release request not found' 'Losing approval did not reject the cancelled request.'
Write-Output 'PASS: shift cancellation racing approval produced one cancelled request outcome and no removal.'

$shiftFourLock = "select pg_advisory_xact_lock(hashtextextended('release-shift:38000000-0000-0000-0000-000000000004',0));"
$raceFour = Invoke-Race `
  "begin; $supervisorOne $shiftFourLock select pg_sleep(2); select public.approve_release_request_replace('58000000-0000-0000-0000-000000000004','28000000-0000-0000-0000-000000000004',false,null,'Concurrent replacement one'); commit;" `
  "begin; $supervisorTwo select public.approve_release_request_replace('58000000-0000-0000-0000-000000000004','28000000-0000-0000-0000-000000000005',false,null,'Concurrent replacement two'); commit;" `
  1 `
  'double replacement-approval race'
$raceFourState = Invoke-Sql @'
select
  (select status from public.release_requests where id='58000000-0000-0000-0000-000000000004'),
  (select removed_at is not null and replaced_by_assignment_id is not null from public.shift_assignments where id='48000000-0000-0000-0000-000000000004'),
  (select count(*) from public.shift_assignments where shift_id='38000000-0000-0000-0000-000000000004' and removed_at is null),
  (select count(*) from public.roster_audit where release_request_id='58000000-0000-0000-0000-000000000004' and action='RELEASE_REQUEST_APPROVED'),
  (select count(*) from public.roster_audit where assignment_id='48000000-0000-0000-0000-000000000004' and action='EMPLOYEE_REPLACED'),
  (select count(*) from public.roster_audit where release_request_id='58000000-0000-0000-0000-000000000004' and action='RELEASE_REQUEST_CANCELLED');
'@
Assert-Match $raceFourState '(?m)APPROVED\s*\|\s*t\s*\|\s*1\s*\|\s*1\s*\|\s*1\s*\|\s*0' 'Double replacement approval created duplicate assignments or contradictory audits.'
Assert-Match ($raceFour.Output -join "`n") '(Active assignment|Pending release request) not found' 'Losing replacement approval did not reject the terminal workflow.'
Write-Output 'PASS: two replacement approvals produced one replacement assignment, one approval, and one replacement audit.'
