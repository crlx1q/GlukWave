param([ValidateSet('all','ytdlp','spotdl','deno')][string]$Adapter='all', [string]$Python='python', [ValidatePattern('^\d+\.\d+\.\d+$')][string]$DenoVersion='2.9.7')
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$toolRoot=Join-Path $projectRoot 'work/tools/extractors'
New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
foreach ($name in @('ytdlp','spotdl')) {
  if ($Adapter -ne 'all' -and $Adapter -ne $name) { continue }
  $directory=Join-Path $toolRoot $name
  if (!(Test-Path -LiteralPath (Join-Path $directory 'Scripts/python.exe'))) { & $Python -m venv $directory; if ($LASTEXITCODE -ne 0) { throw 'Python environment creation failed.' } }
  & (Join-Path $directory 'Scripts/python.exe') -m pip install --disable-pip-version-check -r (Join-Path $projectRoot ('apps/server/extractors/requirements-'+$name+'.txt'))
  if ($LASTEXITCODE -ne 0) { throw 'Extractor installation failed.' }
}
if ($Adapter -in @('all','deno')) {
  $directory=Join-Path $toolRoot 'deno';New-Item -ItemType Directory -Path $directory -Force | Out-Null
  $release=Invoke-RestMethod ('https://api.github.com/repos/denoland/deno/releases/tags/v'+$DenoVersion)
  $asset=$release.assets | Where-Object name -eq 'deno-x86_64-pc-windows-msvc.zip' | Select-Object -First 1
  if (!$asset -or !$asset.digest -or !$asset.browser_download_url.StartsWith('https://github.com/denoland/deno/releases/')) { throw 'Verified official Deno asset missing.' }
  $archive=Join-Path $toolRoot 'deno.zip'
  Invoke-WebRequest $asset.browser_download_url -OutFile $archive
  if ($asset.digest -ne ('sha256:'+(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLower())) { throw 'Deno checksum mismatch.' }
  Expand-Archive -LiteralPath $archive -DestinationPath $directory -Force
  & (Join-Path $directory 'deno.exe') --version
}
Write-Output 'Independent extractor runtimes installed. Provider credentials remain server-only.'
