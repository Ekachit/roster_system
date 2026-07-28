$ErrorActionPreference = 'Stop'
if (-not $env:M6_BROWSER_PASSWORD) { throw 'M6_BROWSER_PASSWORD is required.' }

$status = supabase status -o env
$api = ($status | Where-Object { $_.StartsWith('API_URL=') }).Split('=', 2)[1].Trim('"')
$anonymousKey = ($status | Where-Object { $_.StartsWith('ANON_KEY=') }).Split('=', 2)[1].Trim('"')
$env:VITE_SUPABASE_URL = $api
$env:VITE_SUPABASE_ANON_KEY = $anonymousKey

$root = Resolve-Path "$PSScriptRoot\..\.."
$vite = Start-Process -FilePath 'node.exe' `
  -ArgumentList @('node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','5173','--strictPort') `
  -WorkingDirectory $root -WindowStyle Hidden -PassThru
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
  npm run test:browser:m6
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Stop-Process -Id $vite.Id -Force -ErrorAction SilentlyContinue
}
