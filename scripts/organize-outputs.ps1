param([switch]$Apply, [switch]$IncludeRecentBuildArtifacts)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'outputs'))
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'apps/server/package.json'))) { throw 'Run from the GlukWave project.' }
if ((Get-Item -LiteralPath $outputRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'outputs must be a real project directory.' }
function Assert-OutputPath([string]$value) {
  $absolute = [IO.Path]::GetFullPath($value)
  if (-not $absolute.StartsWith($outputRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Path outside outputs: $absolute" }
  $parent = Split-Path -Parent $absolute
  while ($parent -ne $outputRoot) {
    if ((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Linked directory: $parent" }
    $parent = Split-Path -Parent $parent
  }
  return $absolute
}
$releases = (Get-Content -LiteralPath (Join-Path $outputRoot 'releases.json') -Raw | ConvertFrom-Json).releases
$versions = @($releases.version | Sort-Object -Unique)
if ($versions.Count -ne 1 -or $versions[0] -notmatch '^1\.0\.0\+(\d+)$') { throw 'Expected one current native version.' }
$latest = [int]$Matches[1]
if ($IncludeRecentBuildArtifacts) {
  $proofPath=Join-Path $projectRoot 'work/qa/windows-package-proof.json'
  if (-not (Test-Path -LiteralPath $proofPath -PathType Leaf)) { throw 'Audit the current Windows package before collecting recent build backups.' }
  $proof=Get-Content -LiteralPath $proofPath -Raw | ConvertFrom-Json
  $currentZip=Assert-OutputPath (Join-Path $outputRoot 'GlukWave-windows.zip')
  if (-not $proof.passed -or -not $proof.zipCrcAndAllFilesMatched -or (Get-FileHash -LiteralPath $currentZip).Hash.ToLowerInvariant() -ne $proof.sha256) { throw 'Current Windows audit is missing or stale.' }
}
foreach ($release in $releases) {
  $file = Assert-OutputPath (Join-Path $outputRoot $release.file)
  if ((Get-Item -LiteralPath $file).Length -ne $release.bytes -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $release.sha256) { throw "Current release integrity failed: $($release.file)" }
}
$plan = [Collections.Generic.List[object]]::new()
$previewHashes = @{}
foreach ($file in Get-ChildItem -LiteralPath $outputRoot -File | Sort-Object Name) {
  $action = $null; $destination = $null; $reason = $null
  if ($file.Name -match '^GlukWave-(android(?:-debug)?|Setup|windows)-(1\.0\.0\+(\d+))\.(apk|exe|zip)$') {
    $kind=$Matches[1]; $version=$Matches[2]; $build=[int]$Matches[3]
    if ($build -lt $latest-1) { $action='delete'; $reason='superseded generated client; current and preceding version retained' }
    elseif ($build -eq $latest-1) { $action='move'; $destination="archive/releases/$version/$($file.Name)"; $reason='preceding client retained for rollback' }
    elseif ($build -eq $latest) {
      $alias = switch -Regex ($kind) { '^android' {'GlukWave-android-debug.apk'} '^Setup$' {'GlukWave-Setup.exe'} '^windows$' {'GlukWave-windows.zip'} }
      if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $outputRoot $alias)).Hash) { throw "Dated release differs from stable alias: $($file.Name)" }
      $action='delete'; $destination=$alias; $reason='byte-identical dated copy of current stable file'
    }
  } elseif ($file.Name -match '^GlukWave-source-(.+)\.zip$') {
    $label=$Matches[1]
    if ((Get-FileHash -LiteralPath $file.FullName).Hash -eq (Get-FileHash -LiteralPath (Join-Path $outputRoot 'GlukWave-source.zip')).Hash) {
      $action='delete'; $destination='GlukWave-source.zip'; $reason='byte-identical source archive'
    } else { $action='move'; $destination="archive/sources/$($file.Name)"; $reason='unique historical source archive preserved' }
  } elseif ($file.Name -match '^GlukWave-(1\.0\.0\+(\d+))-.+\.json$') {
    if ([int]$Matches[2] -lt $latest) { $action='move'; $destination="archive/releases/$($Matches[1])/$($file.Name)"; $reason='historical release verification' }
  } elseif ($file.Name -match '^GlukWave-source-.+-audit\.json$') {
    $action='move'; $destination="archive/sources/$($file.Name)"; $reason='historical source verification'
  } elseif ($file.Extension -eq '.png' -and $file.Name -ne 'GlukWave-server-console.png') {
    $hash=(Get-FileHash -LiteralPath $file.FullName).Hash
    if ($previewHashes.ContainsKey($hash)) { $action='delete'; $destination=$previewHashes[$hash]; $reason='byte-identical preview retained under canonical name' }
    else { $action='move'; $destination="archive/previews/$($file.Name)"; $reason='historical preview'; $previewHashes[$hash]=$destination }
  } elseif ($file.Name -match '^GlukWave-source\.[a-f0-9]{32}\.partial$' -and $file.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddDays(-1)) {
    $action='delete'; $reason='abandoned packaging partial older than one day'
  }
  if ($action) {
    $source=Assert-OutputPath $file.FullName
    $target=if ($destination) { Assert-OutputPath (Join-Path $outputRoot $destination) } else { $null }
    $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($action -eq 'move' -and (Test-Path -LiteralPath $target)) {
      $existing=Get-Item -LiteralPath $target
      if ($existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Invalid archive target: $target" }
      if ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -ne $sourceHash) { throw "Different archive already exists: $target" }
      $action='delete'; $reason='byte-identical copy already retained in archive'
    }
    $plan.Add([pscustomobject]@{action=$action;from=$file.Name;to=$destination;bytes=$file.Length;sha256=$sourceHash;reason=$reason})
  }
}
$releaseArchive=Join-Path $outputRoot 'archive/releases'
if (Test-Path -LiteralPath $releaseArchive -PathType Container) {
  foreach ($versionDirectory in Get-ChildItem -LiteralPath $releaseArchive -Directory) {
    if ($versionDirectory.Name -notmatch '^1\.0\.0\+(\d+)$' -or [int]$Matches[1] -ge $latest-1) { continue }
    $checkedDirectory=Assert-OutputPath $versionDirectory.FullName
    if ($versionDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked release directory: $checkedDirectory" }
    foreach ($file in Get-ChildItem -LiteralPath $checkedDirectory -File) {
      if ($file.Name -notmatch '^GlukWave-(?:android(?:-debug)?(?:-1\.0\.0\+\d+)?\.apk|Setup(?:-1\.0\.0\+\d+)?\.exe|windows(?:-1\.0\.0\+\d+)?\.zip)$') { continue }
      if ($file.Name -match '-(1\.0\.0\+\d+)\.(?:apk|exe|zip)$' -and $Matches[1] -ne $versionDirectory.Name) { continue }
      $checkedFile=Assert-OutputPath $file.FullName
      if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked release file: $checkedFile" }
      $plan.Add([pscustomobject]@{action='delete';from=$checkedFile.Substring($outputRoot.Length+1).Replace('\','/');to=$null;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $checkedFile).Hash.ToLowerInvariant();reason='superseded archived generated client; current and preceding version retained; historical reports kept'})
    }
  }
}
function Bundle-Inventory([string]$directory) {
  $directory=Assert-OutputPath $directory
  $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($directory)
  $rows=[Collections.Generic.List[object]]::new()
  while ($pending.Count) {
    $current=$pending.Pop()
    foreach ($entry in Get-ChildItem -LiteralPath $current -Force) {
      $absolute=Assert-OutputPath $entry.FullName
      if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked bundle content: $absolute" }
      if ($entry.PSIsContainer) { $pending.Push($absolute) }
      else {
        if ($entry.Name -match '^\.env|\.(sqlite|sqlite3|jks|keystore)$') { throw "Unexpected private data in generated bundle: $absolute" }
        $rows.Add([pscustomobject]@{path=$absolute.Substring($directory.Length+1);bytes=$entry.Length;sha256=(Get-FileHash -LiteralPath $absolute).Hash})
      }
    }
  }
  $sorted=@($rows.ToArray() | Sort-Object path)
  $payload=($sorted | ForEach-Object { $_.path+':'+$_.bytes+':'+$_.sha256 }) -join "`n"
  $sha=[Security.Cryptography.SHA256]::Create()
  try { $fingerprint=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
  return [pscustomobject]@{bytes=($sorted | Measure-Object bytes -Sum).Sum;count=$sorted.Count;sha256=$fingerprint}
}
# Generated staging/backup directories left by earlier Windows packaging attempts.
# Two-hour guard prevents collecting a current build. An explicit post-audit run
# can also collect recent backups; the stable bundle always stays untouched.
foreach ($directory in Get-ChildItem -LiteralPath $outputRoot -Directory) {
  if ($directory.Name -notmatch '^GlukWave-windows(?:\.[a-f0-9]{32}\.partial|\.previous\.[a-f0-9]{32}|-1\.0\.0\+(\d+))$') { continue }
  if (-not $IncludeRecentBuildArtifacts -and $directory.LastWriteTimeUtc -ge [DateTime]::UtcNow.AddHours(-2)) { continue }
  if ($Matches[1] -and [int]$Matches[1] -ge $latest-1) { continue }
  $absolute=Assert-OutputPath $directory.FullName
  if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked bundle: $absolute" }
  foreach ($process in Get-Process -Name glukwave -ErrorAction SilentlyContinue) {
    if ($process.Path -and $process.Path.StartsWith($absolute+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw "Old bundle is running: $absolute" }
  }
  $inventory=Bundle-Inventory $absolute
  $plan.Add([pscustomobject]@{action='delete-directory';from=$directory.Name;to=$null;bytes=$inventory.bytes;fileCount=$inventory.count;sha256=$inventory.sha256;reason='abandoned generated Windows staging or superseded extracted bundle'})
}
$deletedBytes=($plan | Where-Object action -in @('delete','delete-directory') | Measure-Object bytes -Sum).Sum
$report=[pscustomobject]@{createdAt=[DateTime]::UtcNow.ToString('o');applied=[bool]$Apply;currentVersion=$versions[0];rollbackBuild=$latest-1;deletedBytes=$deletedBytes;entries=@($plan.ToArray())}
if ($Apply) {
  # Validate the complete plan before the first mutation. Never recurse or overwrite unique data.
  foreach ($entry in $plan) {
    $source=Assert-OutputPath (Join-Path $outputRoot $entry.from)
    if ($entry.action -eq 'delete' -and $entry.to) {
      $retained=Assert-OutputPath (Join-Path $outputRoot $entry.to)
      $retainedItem=Get-Item -LiteralPath $retained
      if ($retainedItem.PSIsContainer -or ($retainedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $retained).Hash.ToLowerInvariant() -ne $entry.sha256) { throw "Retained duplicate changed: $retained" }
    }
    if ($entry.action -eq 'delete-directory') { if ((Bundle-Inventory $source).sha256 -ne $entry.sha256) { throw "Bundle changed: $source" } }
    elseif ((Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -ne $entry.sha256) { throw "Source changed: $source" }
    if ($entry.action -eq 'move') {
      $target=Assert-OutputPath (Join-Path $outputRoot $entry.to)
      if (Test-Path -LiteralPath $target) { throw "Destination already exists: $target" }
    }
  }
  foreach ($entry in $plan) {
    $source=Assert-OutputPath (Join-Path $outputRoot $entry.from)
    if ($entry.action -eq 'move') {
      $target=Assert-OutputPath (Join-Path $outputRoot $entry.to)
      [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
      Move-Item -LiteralPath $source -Destination $target
      if ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -ne $entry.sha256) { throw "Moved file integrity failed: $target" }
    } elseif ($entry.action -eq 'delete-directory') {
      $checked=Assert-OutputPath $source
      if ((Get-Item -LiteralPath $checked).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked bundle: $checked" }
      Remove-Item -LiteralPath $checked -Recurse
    } else { Remove-Item -LiteralPath $source }
  }
  $priorPath=Join-Path $outputRoot 'organization.json'
  if ($plan.Count -gt 0 -and (Test-Path -LiteralPath $priorPath)) {
    $prior=Get-Content -LiteralPath $priorPath -Raw | ConvertFrom-Json
    $history=@();if ($prior.PSObject.Properties.Name -contains 'history') { $history=@($prior.history) }
    $history+=@([pscustomobject]@{createdAt=$prior.createdAt;currentVersion=$prior.currentVersion;deletedBytes=$prior.deletedBytes;entries=$prior.entries})
    $report | Add-Member -NotePropertyName history -NotePropertyValue $history
  }
  if ($plan.Count -gt 0) { $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputRoot 'organization.json') -Encoding utf8 }
}
$report | ConvertTo-Json -Depth 6
