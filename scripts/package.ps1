$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputDir = Join-Path $projectRoot 'outputs'
[System.IO.Directory]::CreateDirectory($outputDir) | Out-Null
$archivePath = Join-Path $outputDir 'GlukWave-source.zip'
$temporaryPath = Join-Path $outputDir ('GlukWave-source.' + [System.Guid]::NewGuid().ToString('N') + '.partial')
$allowedRootFiles = @('.env.example', '.gitignore', '.dockerignore', 'Dockerfile', 'compose.yaml', 'package.json', 'package-lock.json', 'README.md')
$allowedRoots = @('apps', 'docs', 'scripts', 'deploy', '.github')
$files = [System.Collections.Generic.List[string]]::new()
foreach ($name in $allowedRootFiles) { $candidate = Join-Path $projectRoot $name; if (Test-Path -LiteralPath $candidate -PathType Leaf) { $files.Add($candidate) } }
function Add-SourceFiles([string]$directory) {
  foreach ($entry in Get-ChildItem -LiteralPath $directory -Force) {
    if ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
    if ($entry.PSIsContainer) {
      if ($entry.Name -in @('node_modules', '.git', '.dart_tool', 'build', '.gradle', 'ephemeral', '.idea', '.vscode', '.symlinks', '.originkit', '__pycache__', '.pytest_cache', 'xcuserdata')) { continue }
      Add-SourceFiles $entry.FullName
    } elseif ($entry.Name -notmatch '^\.env($|\.)|^\.flutter-plugins|^local\.properties$|^key\.properties$|^Generated\.xcconfig$|^flutter_export_environment\.sh$|\.(jks|keystore|p12|pyc|iml|apk|ipa|exe|sqlite|sqlite3|sqlite-wal|sqlite-shm)$|\.tsbuildinfo$') {
      $files.Add($entry.FullName)
    }
  }
}
foreach ($name in $allowedRoots) { $directory = Join-Path $projectRoot $name; if (Test-Path -LiteralPath $directory -PathType Container) { Add-SourceFiles $directory } }
foreach ($name in @('START.md', 'VERIFICATION.md', 'Start-GlukWave.ps1')) { $candidate = Join-Path $outputDir $name; if (Test-Path -LiteralPath $candidate -PathType Leaf) { $files.Add($candidate) } }
Add-Type -AssemblyName System.IO.Compression
$stream = [System.IO.File]::Open($temporaryPath, [System.IO.FileMode]::CreateNew)
$archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($file in $files) {
    # Windows PowerShell 5.1 also supports this bounded relative-path calculation.
    $absoluteFile = [System.IO.Path]::GetFullPath($file)
    $rootPrefix = $projectRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $absoluteFile.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Source escaped project root.' }
    $relative = $absoluteFile.Substring($rootPrefix.Length).Replace('\', '/')
    if ($relative.StartsWith('../') -or [System.IO.Path]::IsPathRooted($relative)) { throw 'Source escaped project root.' }
    $entry = $archive.CreateEntry('GlukWave/' + $relative, [System.IO.Compression.CompressionLevel]::Optimal)
    $source = [System.IO.File]::OpenRead($file)
    $destination = $entry.Open()
    try { $source.CopyTo($destination) } finally { $destination.Dispose(); $source.Dispose() }
  }
} finally { $archive.Dispose(); $stream.Dispose() }
Move-Item -LiteralPath $temporaryPath -Destination $archivePath -Force
Write-Host ('Source archive: {0} files, {1:N1} MB' -f $files.Count, ((Get-Item -LiteralPath $archivePath).Length / 1MB))
