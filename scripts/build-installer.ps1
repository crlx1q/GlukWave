param([string]$Compiler, [string]$Version='1.0.0+4', [string]$BundleRoot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$bundleRoot = if ($BundleRoot) { [IO.Path]::GetFullPath($BundleRoot) } else { Join-Path $projectRoot 'outputs\GlukWave-windows' }
$outputRoot = Join-Path $projectRoot 'outputs'
if (!(Test-Path -LiteralPath (Join-Path $bundleRoot 'glukwave.exe'))) { throw 'Build and verify the Windows bundle first.' }
if (!$Compiler) {
  $compilerCandidates = @(
    (Join-Path $projectRoot 'work\tools\inno-portable\tools\ISCC.exe'),
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 7\ISCC.exe')
  $Compiler = $compilerCandidates | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
}
if (!$Compiler) { throw 'Install Inno Setup or pass -Compiler with its ISCC.exe path.' }
$webviewBootstrapper=Join-Path $projectRoot 'work/tools/webview2/MicrosoftEdgeWebview2Setup.exe'
& (Join-Path $PSScriptRoot 'prepare-webview2.ps1') -Destination $webviewBootstrapper
& $Compiler ('/DBundleDir='+$bundleRoot) ('/DOutputDir='+$outputRoot) ('/DBuildVersion='+$Version) ('/DWebViewBootstrapper='+$webviewBootstrapper) (Join-Path $projectRoot 'deploy\windows\GlukWave.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
$installerFile = Join-Path $outputRoot 'GlukWave-Setup.exe'
if (!(Test-Path -LiteralPath $installerFile)) { throw 'Installer output missing.' }
Get-Item -LiteralPath $installerFile | Select-Object FullName,Length
Get-FileHash -LiteralPath $installerFile -Algorithm SHA256
