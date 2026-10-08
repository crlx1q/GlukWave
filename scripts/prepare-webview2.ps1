param([string]$Destination)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (!$Destination) { $Destination=Join-Path $projectRoot 'work/tools/webview2/MicrosoftEdgeWebview2Setup.exe' }
$Destination=[IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
if (!(Test-Path -LiteralPath $Destination)) { Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $Destination }
$signature=Get-AuthenticodeSignature -LiteralPath $Destination
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'WebView2 bootstrapper must have a valid Microsoft Authenticode signature.' }
Get-FileHash -LiteralPath $Destination -Algorithm SHA256
