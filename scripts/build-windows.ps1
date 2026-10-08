param([string]$Server = 'http://127.0.0.1:4000')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$nativeRoot = Join-Path $projectRoot 'apps/native'
$serverUri = $null
if (-not [Uri]::TryCreate($Server, [UriKind]::Absolute, [ref]$serverUri) -or $serverUri.Scheme -notin @('http','https') -or $serverUri.UserInfo) { throw 'Pass an HTTP(S) server origin without credentials.' }
# Copy sources into a short independent directory. Never build through a junction.
$buildWorkspace = Join-Path (Split-Path $projectRoot -Parent | Split-Path -Parent) ('gw-build-' + [guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $buildWorkspace | Out-Null
function Copy-SourceDirectory([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
    if ($item.PSIsContainer) {
      if ($item.Name -in @('build','.dart_tool','ephemeral','.plugin_symlinks','.symlinks','.git','__pycache__')) { continue }
      Copy-SourceDirectory $item.FullName (Join-Path $Destination $item.Name)
    } else { Copy-Item -LiteralPath $item.FullName -Destination $Destination }
  }
}
foreach ($name in @('lib','assets','windows')) { Copy-SourceDirectory (Join-Path $nativeRoot $name) (Join-Path $buildWorkspace $name) }
foreach ($name in @('pubspec.yaml','pubspec.lock','.metadata','analysis_options.yaml')) { Copy-Item -LiteralPath (Join-Path $nativeRoot $name) -Destination $buildWorkspace }
$oldPubCache = $env:PUB_CACHE
$env:PUB_CACHE = Join-Path (Split-Path $buildWorkspace -Parent) ('gw-pub-' + [guid]::NewGuid().ToString('N').Substring(0,6))
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutterCommand) { $flutterPath = $flutterCommand.Source }
elseif (Test-Path -LiteralPath 'C:\flutter\bin\flutter.bat') { $flutterPath = 'C:\flutter\bin\flutter.bat' }
else { throw 'Install Flutter and add its bin directory to PATH.' }
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'work/qa') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $projectRoot 'work/qa/windows-build-workspace.txt'), $buildWorkspace, [Text.UTF8Encoding]::new($false))
$cacheTarget = Join-Path $buildWorkspace 'build/windows/x64'
New-Item -ItemType Directory -Path $cacheTarget -Force | Out-Null
$oldBuild = Join-Path $nativeRoot 'build/windows/x64'
if (Test-Path -LiteralPath $oldBuild) {
  Get-ChildItem -LiteralPath $oldBuild -File | Where-Object { $_.Name -match '^(firebase_cpp_sdk_windows_.*\.zip|mpv.*\.7z)$' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $cacheTarget }
}
Push-Location -LiteralPath $buildWorkspace
try {
  & $flutterPath pub get --enforce-lockfile
  if ($LASTEXITCODE -ne 0) { throw 'Dependency restoration failed.' }
  & $flutterPath build windows --release --no-pub "--dart-define=GLUKWAVE_SERVER=$Server"
  if ($LASTEXITCODE -ne 0) { throw 'Windows compilation failed.' }
} finally { Pop-Location; $env:PUB_CACHE = $oldPubCache }
& (Join-Path $PSScriptRoot 'package-windows.ps1') -ReleaseRoot (Join-Path $buildWorkspace 'build/windows/x64/runner/Release')
