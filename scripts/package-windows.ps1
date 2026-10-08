param([string]$ReleaseRoot)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$releaseRoot = if ($ReleaseRoot) { [IO.Path]::GetFullPath($ReleaseRoot) } else { Join-Path $projectRoot 'apps/native/build/windows/x64/runner/Release' }
$outputRoot = Join-Path $projectRoot 'outputs'
$executable = Join-Path $releaseRoot 'glukwave.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Build the Windows Release application first.' }
if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot 'data/app.so') -PathType Leaf)) { throw 'Flutter application runtime is missing.' }
$bundle = Join-Path $outputRoot ('GlukWave-windows.' + [guid]::NewGuid().ToString('N') + '.partial')
New-Item -ItemType Directory -Path $bundle | Out-Null
Copy-Item -LiteralPath $releaseRoot -Destination (Join-Path $bundle 'GlukWave') -Recurse
$appDir = Join-Path $bundle 'GlukWave'
$redistRoot = 'C:\BuildTools\GlukWave\VC\Redist\MSVC'
$crtDirectory = Get-ChildItem -LiteralPath $redistRoot -Directory | Where-Object Name -match '^\d+\.' | Sort-Object Name -Descending | ForEach-Object {
  $candidate = Join-Path $_.FullName 'x64/Microsoft.VC143.CRT'
  if (Test-Path -LiteralPath $candidate -PathType Container) { $candidate }
} | Select-Object -First 1
if (-not $crtDirectory) { throw 'The matching Microsoft C++ redistributable files are missing.' }
foreach ($name in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','concrt140.dll')) {
  $source = Join-Path $crtDirectory $name
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Runtime file missing: $name" }
  Copy-Item -LiteralPath $source -Destination $appDir
}
# Include the unmodified CRT family together, including subsidiary MSVCP DLLs.
Get-ChildItem -LiteralPath $crtDirectory -Filter '*.dll' -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $appDir -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/THIRD-PARTY.md') -Destination (Join-Path $appDir 'THIRD-PARTY.md')
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/licenses') -Destination (Join-Path $appDir 'licenses') -Recurse
@'
GlukWave for Windows

Extract the entire GlukWave folder and run glukwave.exe.
Keep the data directory and DLL files beside the application.
This local test build connects to the GlukWave server on the computer at 127.0.0.1:4000.
Start the Node server in the project first. Close hides the application in the tray;
choose Quit in the tray menu to exit completely.

This package is not Authenticode-signed. It is intended for local testing.
Third-party notices: THIRD-PARTY.md and the licenses screen inside the application.
'@ | Set-Content -LiteralPath (Join-Path $appDir 'START.txt') -Encoding utf8
$temporaryZip = Join-Path $outputRoot ('GlukWave-windows.' + [guid]::NewGuid().ToString('N') + '.zip')
Compress-Archive -LiteralPath $appDir -DestinationPath $temporaryZip -CompressionLevel Optimal
$target = Join-Path $outputRoot 'GlukWave-windows.zip'
Move-Item -LiteralPath $temporaryZip -Destination $target -Force
$directoryTarget = Join-Path $outputRoot 'GlukWave-windows'
# Existing deliveries are preserved until a complete replacement is prepared.
if (Test-Path -LiteralPath $directoryTarget) {
  Move-Item -LiteralPath $directoryTarget -Destination (Join-Path $outputRoot ('GlukWave-windows.previous.' + [guid]::NewGuid().ToString('N')))
}
Move-Item -LiteralPath $appDir -Destination $directoryTarget
Write-Output "Windows application: $directoryTarget\glukwave.exe"
Write-Output "Windows download: $target"
