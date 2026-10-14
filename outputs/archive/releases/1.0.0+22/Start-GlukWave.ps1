$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Установите Node.js 24 или новее.' }
$nodeMajor = [int]((& node --version).TrimStart('v').Split('.')[0])
if ($nodeMajor -lt 24) { throw 'GlukWave требует Node.js 24 или новее.' }
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'node_modules'))) {
  & npm.cmd install
  if ($LASTEXITCODE -ne 0) { throw 'Не удалось установить зависимости.' }
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.env'))) {
  & npm.cmd run keys
  if ($LASTEXITCODE -ne 0) { throw 'Не удалось создать локальную конфигурацию.' }
}
function Test-GlukWaveServer {
  try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:4000/api/health' -TimeoutSec 2; return $health.status -eq 'ok' -and $null -ne $health.storage -and $health.version -eq '0.1.0' }
  catch { return $false }
}
function Test-GlukWaveWeb {
  try { $page = Invoke-WebRequest -Uri 'http://127.0.0.1:5173' -UseBasicParsing -TimeoutSec 2; return $page.StatusCode -eq 200 -and $page.Content -match '<title>GlukWave' }
  catch { return $false }
}
$serverReady = Test-GlukWaveServer
$webReady = Test-GlukWaveWeb
Write-Host 'Сайт · http://127.0.0.1:5173/' -ForegroundColor Cyan
Write-Host 'Музыка · http://127.0.0.1:5173/app/' -ForegroundColor Cyan
if ($serverReady -and $webReady) {
  Write-Host 'Приложение уже запущено. Откройте адрес выше в браузере.'
  return
}
Write-Host 'Для остановки запущенных здесь компонентов нажмите Ctrl+C.'
if ($serverReady) { & npm.cmd run dev -w '@glukwave/web' }
elseif ($webReady) { & npm.cmd run dev -w '@glukwave/server' }
else { & npm.cmd run dev }
