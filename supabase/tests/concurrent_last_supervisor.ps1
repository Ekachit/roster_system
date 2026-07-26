$ErrorActionPreference = 'Stop'

$container = docker ps `
  --filter 'label=com.supabase.cli.project=ai-fitness-zone-roster' `
  --filter 'name=supabase_db' `
  --format '{{.Names}}'

if (-not $container) {
  throw 'The local Supabase database is not running. Run supabase start first.'
}

$setupSql = @'
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('11000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'concurrent.one@example.test', '', now(), now(), now()),
  ('11000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'concurrent.two@example.test', '', now(), now(), now())
on conflict (id) do update set email = excluded.email, email_confirmed_at = excluded.email_confirmed_at;

insert into public.staff (id, email, full_name, role, is_active)
values
  ('21000000-0000-0000-0000-000000000001', 'concurrent.one@example.test', 'Concurrent Supervisor One', 'supervisor', true),
  ('21000000-0000-0000-0000-000000000002', 'concurrent.two@example.test', 'Concurrent Supervisor Two', 'supervisor', true)
on conflict (id) do update set role = 'supervisor', is_active = true;

update auth.users
set email_confirmed_at = email_confirmed_at + interval '1 second'
where id in (
  '11000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000002'
);

update public.staff
set role = 'employee'
where role = 'supervisor'
  and id not in (
    '21000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000002'
  );
'@

$setupSql | docker exec -i $container psql -v ON_ERROR_STOP=1 -U postgres -d postgres
if ($LASTEXITCODE -ne 0) {
  throw 'Concurrency test setup failed.'
}

$deactivateSql = @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000001', true);
select public.set_staff_active('21000000-0000-0000-0000-000000000001', false);
select pg_sleep(2);
commit;
"@

$demoteSql = @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000002', true);
select public.save_staff_configuration(
  '21000000-0000-0000-0000-000000000002',
  'concurrent.two@example.test',
  'Concurrent Supervisor Two',
  'employee',
  null,
  array[]::uuid[],
  array[]::uuid[]
);
commit;
"@

$runner = {
  param($containerName, $sql)
  $output = & docker exec $containerName psql -v ON_ERROR_STOP=1 -U postgres -d postgres -c $sql 2>&1
  [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

$first = Start-Job -ScriptBlock $runner -ArgumentList $container, $deactivateSql
Start-Sleep -Milliseconds 300
$second = Start-Job -ScriptBlock $runner -ArgumentList $container, $demoteSql

$results = @($first, $second) | Wait-Job | Receive-Job
@($first, $second) | Remove-Job

$count = docker exec $container psql -U postgres -d postgres -Atc `
  "select count(*) from public.staff where id in ('21000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000002') and role = 'supervisor' and is_active"

$successCount = @($results | Where-Object ExitCode -eq 0).Count
$blockedCount = @($results | Where-Object {
  $_.ExitCode -ne 0 -and $_.Output -match 'The last active supervisor cannot be demoted or deactivated'
}).Count

if ($successCount -ne 1 -or $blockedCount -ne 1 -or [int]$count -ne 1) {
  $results | Format-List | Out-String | Write-Host
  throw "Concurrency protection failed: successes=$successCount blocked=$blockedCount active_supervisors=$count"
}

Write-Host 'PASS: two concurrent sessions produced one successful change, one protected rejection, and one active supervisor.'
