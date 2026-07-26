$ErrorActionPreference = 'Stop'
if (-not $env:M3_BROWSER_PASSWORD) { throw 'M3_BROWSER_PASSWORD is required.' }

$status = supabase status -o env
$api = ($status | Where-Object { $_.StartsWith('API_URL=') }).Split('=', 2)[1].Trim('"')
$anonymousKey = ($status | Where-Object { $_.StartsWith('ANON_KEY=') }).Split('=', 2)[1].Trim('"')
$env:VITE_SUPABASE_URL = $api
$env:VITE_SUPABASE_ANON_KEY = $anonymousKey

$container = docker ps --filter 'name=supabase_db_' --format '{{.Names}}' | Select-Object -First 1
$cleanup = @"
delete from public.roster_audit where shift_id in (
  select id from public.shifts where shift_title='Synthetic Sunday training'
);
delete from public.shift_assignments where shift_id in (
  select id from public.shifts where shift_title='Synthetic Sunday training'
);
delete from public.shifts where shift_title='Synthetic Sunday training';
"@
$cleanup | docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 | Out-Null

$vite = Start-Process -FilePath 'npm.cmd' -ArgumentList @('run','dev','--','--host','127.0.0.1') `
  -WorkingDirectory (Resolve-Path "$PSScriptRoot\..\..") -WindowStyle Hidden -PassThru
try {
  $ready = $false
  foreach ($attempt in 1..20) {
    try {
      $response = Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:5173'
      if ($response.StatusCode -eq 200) { $ready = $true; break }
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  if (-not $ready) { throw 'Vite did not become ready.' }
  npm run test:browser:m3
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Stop-Process -Id $vite.Id -Force -ErrorAction SilentlyContinue
}
