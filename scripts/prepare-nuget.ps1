param([string]$Destination)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (!$Destination) { $Destination=Join-Path $projectRoot 'work/tools/nuget/nuget.exe' }
$Destination=[IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
if (!(Test-Path -LiteralPath $Destination)) {
  $temporary=$Destination+'.download'
  Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $temporary
  $signature=Get-AuthenticodeSignature -LiteralPath $temporary
  if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'NuGet Microsoft signature verification failed.' }
  Move-Item -LiteralPath $temporary -Destination $Destination
}
$signature=Get-AuthenticodeSignature -LiteralPath $Destination
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'NuGet Microsoft signature verification failed.' }
[pscustomobject]@{path=$Destination;signature='Microsoft, valid';sha256=(Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLower()}
