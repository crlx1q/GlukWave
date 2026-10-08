param([Parameter(Mandatory=$true)][string]$Apk, [string]$ApkSigner)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (!$ApkSigner) { $ApkSigner='C:/Users/alish/AppData/Local/Android/Sdk/build-tools/36.1.0/apksigner.bat' }
$baseline=Get-Content -LiteralPath (Join-Path $projectRoot 'deploy/android-signing.json') -Raw | ConvertFrom-Json
$verification=& $ApkSigner verify --print-certs $Apk 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Android package signature verification failed.' }
$certificate=($verification | Select-String '^Signer #1 certificate SHA-256 digest: ([a-f0-9]{64})$').Matches.Groups[1].Value
if ($certificate -ne $baseline.certificateSha256) { throw 'Signing certificate changed. Stop: this APK cannot update the existing local test installation.' }
[pscustomobject]@{apk=[IO.Path]::GetFullPath($Apk);certificateSha256=$certificate;matchesBaseline=$baseline.baseline;sha256=(Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash.ToLower()}
