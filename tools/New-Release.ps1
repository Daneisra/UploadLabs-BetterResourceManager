[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory,
    # Local test builds only: the archive notes record the uncommitted state.
    [switch]$AllowDirty
)

# Builds the installable ZIP. It never publishes anything (no GitHub release,
# no Steam Workshop upload): publication stays a separate, explicit decision.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$modFolderName = 'Daneisra-BetterResourceManager'
$runtimeItems = @('manifest.json', 'mod_main.gd', 'data', 'scenes', 'scripts', 'translations', 'README.md', 'CHANGELOG.md', 'LICENSE', 'NOTICE.md')
$rootPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd([char[]]'\/')
$releaseDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { Join-Path $rootPath 'release' } else { [IO.Path]::GetFullPath($OutputDirectory) }

function Invoke-Git([string[]]$Arguments) {
    $output = & git -C $rootPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed:`n$output" }
    return $output
}

$manifest = Get-Content -LiteralPath (Join-Path $rootPath 'manifest.json') -Raw | ConvertFrom-Json
$version = [string]$manifest.version_number
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Manifest version is not semantic: $version" }
$entryPoint = Get-Content -LiteralPath (Join-Path $rootPath 'mod_main.gd') -Raw
$buildMatch = [regex]::Match($entryPoint, '(?m)^const MOD_BUILD := "((?:[A-Za-z0-9][A-Za-z0-9.-]*)?)"\r?$')
if (-not $buildMatch.Success) { throw 'mod_main.gd does not define MOD_BUILD.' }
# An empty MOD_BUILD is a final release (0.1.0); otherwise 0.1.0-rc.1 etc.
$label = if ($buildMatch.Groups[1].Value) { "$version-$($buildMatch.Groups[1].Value)" } else { $version }

if ((Get-Content -LiteralPath (Join-Path $rootPath 'README.md') -Raw) -notmatch [regex]::Escape("v$label")) {
    throw "README.md does not mention v$label."
}
if ((Get-Content -LiteralPath (Join-Path $rootPath 'CHANGELOG.md') -Raw) -notmatch "(?m)^## v$([regex]::Escape($label))\s*$") {
    throw "CHANGELOG.md has no '## v$label' section."
}
foreach ($locale in @('en', 'fr')) {
    if (-not (Test-Path -LiteralPath (Join-Path $rootPath "translations/BetterResourceManager.$locale.translation"))) {
        throw "Compiled $locale translation missing. Run tools/Test-Translations.ps1 -Rebuild."
    }
}

$commit = (Invoke-Git @('rev-parse', 'HEAD')).Trim()
$status = @(Invoke-Git @('status', '--porcelain', '--untracked-files=no'))
$dirty = $status.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace(($status -join ''))
if ($dirty -and -not $AllowDirty) { throw 'Release builds require a clean working tree (or -AllowDirty for a local test build).' }

New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
$archiveName = "$modFolderName-v$label.zip"
$archivePath = Join-Path $releaseDirectory $archiveName
$checksumPath = "$archivePath.sha256"
$notesPath = Join-Path $releaseDirectory "$modFolderName-v$label-notes.md"
foreach ($path in @($archivePath, $checksumPath, $notesPath)) {
    if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite: $path" }
}

# Fixed timestamp (commit time) for stable archives; forward-slash entry names
# because Godot's ZIP reader does not understand backslashes.
$stamp = [DateTimeOffset]::FromUnixTimeSeconds([int64](Invoke-Git @('log', '-1', '--format=%ct')).Trim()).LocalDateTime
$files = [Collections.Generic.List[object]]::new()
foreach ($item in $runtimeItems) {
    $source = Join-Path $rootPath $item
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing runtime item: $item" }
    foreach ($file in @(Get-Item -LiteralPath $source) + @(Get-ChildItem -LiteralPath $source -File -Recurse -ErrorAction SilentlyContinue)) {
        if ($file.PSIsContainer) { continue }
        $relative = $file.FullName.Substring($rootPath.Length + 1).Replace('\', '/')
        $files.Add([pscustomobject]@{ Entry = "mods-unpacked/$modFolderName/$relative"; Path = $file.FullName })
    }
}
$sorted = $files | Sort-Object Entry -Unique

$stream = [IO.File]::Open($archivePath, [IO.FileMode]::CreateNew)
$zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $sorted) {
        $entry = $zip.CreateEntry($file.Entry, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $stamp
        $writer = $entry.Open()
        try {
            $bytes = [IO.File]::ReadAllBytes($file.Path)
            $writer.Write($bytes, 0, $bytes.Length)
        }
        finally { $writer.Dispose() }
    }
}
finally {
    $zip.Dispose()
    $stream.Dispose()
}

$sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
# LF and no BOM, so `sha256sum -c` works on Linux too (Set-Content writes CRLF).
[IO.File]::WriteAllText($checksumPath, "$sha256  $archiveName`n", [Text.Encoding]::ASCII)

$verification = & (Join-Path $PSScriptRoot 'Test-Package.ps1') -Archive $archivePath -ProjectRoot $rootPath

$notes = @(
    "# Better Resource Manager v$label",
    '',
    "- Commit: ``$commit``$(if ($dirty) { ' (uncommitted changes included: local test build)' })",
    "- SHA-256: ``$sha256``",
    "- Files: $($sorted.Count)",
    '',
    'Install: see README.md, section "Installation". Not published anywhere by this script.'
)
Set-Content -LiteralPath $notesPath -Value $notes -Encoding utf8

[pscustomobject]@{
    Label        = $label
    Commit       = $commit
    Dirty        = $dirty
    ArchivePath  = $archivePath
    SHA256       = $sha256
    Files        = $sorted.Count
    Verification = $verification
} | Format-List
