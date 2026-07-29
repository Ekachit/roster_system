$ErrorActionPreference = 'Stop'

if (-not $env:M7_E2E_PASSWORD) {
  $env:M7_E2E_PASSWORD = "M7-$([guid]::NewGuid().ToString('N'))-Aa1!"
}

$root = Resolve-Path "$PSScriptRoot\..\.."

supabase db reset
$resetExitCode = $LASTEXITCODE
if ($resetExitCode -ne 0) {
  # On affected Windows Docker Desktop installations the CLI can receive a
  # transient gateway 502 after migrations and seed have already committed.
  # Verify the exact database state instead of replaying the reset repeatedly.
  Write-Warning 'Supabase reset returned non-zero; verifying the committed migration and clean fixture state.'
  $container = docker ps --filter 'name=supabase_db_' --format '{{.Names}}' |
    Where-Object { $_ -like '*ai-fitness-zone-roster*' } |
    Select-Object -First 1
  if (-not $container) { throw 'Local Supabase database container is not running after reset.' }
  $verification = docker exec $container psql -U postgres -d postgres -Atqc @"
select
  exists(
    select 1 from supabase_migrations.schema_migrations
    where version = '202607280002'
  )::int || '|' ||
  exists(select 1 from public.locations where name = 'Clayton')::int || '|' ||
  exists(
    select 1 from public.staff
    where email = 'm7.e2e.supervisor@example.test'
  )::int;
"@
  if ($LASTEXITCODE -ne 0 -or $verification.Trim() -ne '1|1|0') {
    throw "Local Supabase reset did not produce the required clean database state: $verification"
  }
}

& "$PSScriptRoot\setup_m7_e2e.ps1"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$status = supabase status -o env
$apiLine = $status | Where-Object { $_.StartsWith('API_URL=') }
$keyLine = $status | Where-Object { $_.StartsWith('ANON_KEY=') }
if (-not $apiLine -or -not $keyLine) { throw 'Could not read local Supabase browser configuration.' }
$env:VITE_SUPABASE_URL = $apiLine.Split('=', 2)[1].Trim('"')
$env:VITE_SUPABASE_ANON_KEY = $keyLine.Split('=', 2)[1].Trim('"')

$healthyChecks = 0
foreach ($attempt in 1..60) {
  try {
    $health = Invoke-WebRequest -UseBasicParsing "$env:VITE_SUPABASE_URL/auth/v1/health"
    if ($health.StatusCode -eq 200) {
      $healthyChecks += 1
      if ($healthyChecks -ge 3) { break }
    } else {
      $healthyChecks = 0
    }
  } catch {
    $healthyChecks = 0
  }
  Start-Sleep -Milliseconds 500
}
if ($healthyChecks -lt 3) { throw 'Local Supabase Auth did not become stably healthy.' }

$vite = Start-Process -FilePath 'node.exe' `
  -ArgumentList @('node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','5173','--strictPort') `
  -WorkingDirectory $root -WindowStyle Hidden -PassThru

try {
  $ready = $false
  foreach ($attempt in 1..30) {
    try {
      $response = Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:5173'
      if ($response.StatusCode -eq 200) { $ready = $true; break }
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  if (-not $ready) { throw 'Vite did not become ready.' }

  npx playwright test tests/milestone_7_e2e.spec.ts
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Stop-Process -Id $vite.Id -Force -ErrorAction SilentlyContinue
}
