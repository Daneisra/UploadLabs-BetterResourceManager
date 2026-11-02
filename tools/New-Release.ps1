[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ReleaseLabel,
    [string]$OutputDirectory,
    [switch]$Publish,
    [switch]$Draft,
    [switch]$Prerelease,
    [string]$Repository = $env:GITHUB_REPOSITORY
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$modFolderName = 'Daneisra-BetterResourceManager'
$manifestPath = Join-Path $ProjectRoot 'manifest.json'
$readmePath = Join-Path $ProjectRoot 'README.md'
$changelogPath = Join-Path $ProjectRoot 'CHANGELOG.md'
$releaseDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path $ProjectRoot 'release'
} else {
    [IO.Path]::GetFullPath($OutputDirectory)
}

$runtimeItems = @(
    'manifest.json',
    'mod_main.gd',
    'data',
    'scenes',
    'scripts',
    'translations',
    'README.md',
    'LICENSE',
    'NOTICE.md'
)

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command was not found: $Name"
    }
}

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$output"
    }

    return $output
}

function Get-ChangelogSection {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Label
    )

    $escaped = [regex]::Escape($Label)
    $pattern = "(?ms)^##\s+v?$escaped\s*\r?\n(.*?)(?=^##\s+|\z)"
    $match = [regex]::Match($Content, $pattern)

    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value.Trim()
}

Assert-Command -Name 'git'

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest was not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$version = [string]$manifest.version_number

if ([string]::IsNullOrWhiteSpace($version)) {
    throw 'manifest.json does not contain version_number.'
}

if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Manifest version is not valid semantic versioning: $version"
}

$entryPoint = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mod_main.gd') -Raw
$buildMatch = [regex]::Match($entryPoint, '(?m)^const MOD_BUILD := "([A-Za-z0-9][A-Za-z0-9.-]*)"\r?$')
if (-not $buildMatch.Success) { throw 'mod_main.gd does not identify a valid MOD_BUILD.' }
$expectedLabel = "$version-$($buildMatch.Groups[1].Value)"
if ([string]::IsNullOrWhiteSpace($ReleaseLabel)) { $ReleaseLabel = $expectedLabel }
if ($ReleaseLabel -cne $expectedLabel) {
    throw "Release label must match the runtime build identity: $expectedLabel"
}
$translationPath = Join-Path $ProjectRoot 'translations/BetterResourceManager.en.translation'
if (-not (Test-Path -LiteralPath $translationPath -PathType Leaf)) {
    throw 'Compiled English translation is missing. Run tools/Test-Translations.ps1 -Rebuild first.'
}

$tag = "v$ReleaseLabel"
$repoRoot = (Invoke-Git -Arguments @('-C', $ProjectRoot, 'rev-parse', '--show-toplevel')).Trim()
$commit = (Invoke-Git -Arguments @('-C', $ProjectRoot, 'rev-parse', 'HEAD')).Trim()
$status = @(Invoke-Git -Arguments @('-C', $ProjectRoot, 'status', '--porcelain'))
$dirty = $status.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace(($status -join ''))

if ($dirty) {
    throw 'Release builds require a clean working tree.'
}

foreach ($item in $runtimeItems) {
    $itemPath = Join-Path $ProjectRoot $item
    if (-not (Test-Path -LiteralPath $itemPath)) {
        throw "Required runtime/package item was not found: $item"
    }
}

if (Test-Path -LiteralPath $readmePath) {
    $readme = Get-Content -LiteralPath $readmePath -Raw
    if ($readme -notmatch [regex]::Escape("v$ReleaseLabel")) {
        throw "README.md does not reference v$ReleaseLabel."
    }
}

$changelogSection = $null
if (Test-Path -LiteralPath $changelogPath) {
    $changelog = Get-Content -LiteralPath $changelogPath -Raw
    $changelogSection = Get-ChangelogSection -Content $changelog -Label $ReleaseLabel
    if (-not $changelogSection) {
        throw "CHANGELOG.md does not contain a v$ReleaseLabel section."
    }
}

New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null

$archiveName = "$modFolderName-v$ReleaseLabel.zip"
$archivePath = Join-Path $releaseDirectory $archiveName
$checksumPath = "$archivePath.sha256"
$notesPath = Join-Path $releaseDirectory "$modFolderName-v$ReleaseLabel-release-notes.md"
$stagingPath = Join-Path $releaseDirectory ("staging-$ReleaseLabel-" + [guid]::NewGuid().ToString('N'))
$stagedModPath = Join-Path $stagingPath "mods-unpacked/$modFolderName"

foreach ($outputPath in @($archivePath, $checksumPath, $notesPath)) {
    if (Test-Path -LiteralPath $outputPath) { throw "Refusing to overwrite existing release artifact: $outputPath" }
}

New-Item -ItemType Directory -Path $stagedModPath -Force | Out-Null

foreach ($item in $runtimeItems) {
    $source = Join-Path $ProjectRoot $item
    $destination = Join-Path $stagedModPath $item

    if ((Get-Item -LiteralPath $source).PSIsContainer) {
        Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
}

Compress-Archive -Path (Join-Path $stagingPath 'mods-unpacked') -DestinationPath $archivePath -CompressionLevel Optimal
# Retain the unique staging directory for source/package audit; no recursive deletion.

$hash = Get-FileHash -LiteralPath $archivePath -Algorithm SHA256
$sha256 = $hash.Hash.ToLowerInvariant()
Set-Content -LiteralPath $checksumPath -Value "$sha256  $archiveName" -Encoding ascii

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $expectedManifest = "mods-unpacked/$modFolderName/manifest.json"
    $manifestEntry = $zip.GetEntry($expectedManifest)

    if ($null -eq $manifestEntry) {
        throw "Release archive does not contain expected manifest: $expectedManifest"
    }

    $reader = [System.IO.StreamReader]::new($manifestEntry.Open())
    try {
        $archiveManifest = $reader.ReadToEnd() | ConvertFrom-Json
    }
    finally {
        $reader.Dispose()
    }

    if ([string]$archiveManifest.version_number -ne $version) {
        throw "Archive manifest version '$($archiveManifest.version_number)' does not match '$version'."
    }

    if ($null -eq $zip.GetEntry("mods-unpacked/$modFolderName/translations/BetterResourceManager.en.translation")) {
        throw 'Release archive is missing its compiled English translation.'
    }
    foreach ($requiredEntry in @('mod_main.gd', 'scripts', 'scenes', 'translations')) {
        $prefix = "mods-unpacked/$modFolderName/$requiredEntry"
        $found = @($zip.Entries | Where-Object { $_.FullName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if (-not $found) {
            throw "Release archive is missing required content: $requiredEntry"
        }
    }
}
finally {
    $zip.Dispose()
}

& (Join-Path $PSScriptRoot 'Test-Package.ps1') -Archive $archivePath -ProjectRoot $ProjectRoot

$releaseNotes = "# Adaptive Smart Manager v$ReleaseLabel`n`n"
$releaseNotes += "**Manifest version:** ``$version```n`n"
$releaseNotes += "**Commit:** ``$commit```n`n"

if ($changelogSection) {
    $releaseNotes += "## Changes`n`n$changelogSection`n`n"
}

$releaseNotes += "## Installation`n`n"
$releaseNotes += "1. Remove or disable the original ``kuuk-SmartThreadManager`` and ``kuuk-SmartGPUManager`` mods.`n"
$releaseNotes += "2. Put ``$archiveName`` in the Upload Labs ``mods`` folder without extracting it.`n"
$releaseNotes += "3. Launch Upload Labs and verify both Smart Thread Manager and Smart GPU Manager are available.`n`n"
$releaseNotes += "## Integrity`n`nSHA-256: ``$sha256```n"

Set-Content -LiteralPath $notesPath -Value $releaseNotes -Encoding utf8

$published = $false
$releaseUrl = $null

if ($Publish) {
    Assert-Command -Name 'gh'

    if ([string]::IsNullOrWhiteSpace($Repository)) {
        throw 'Repository was not supplied and GITHUB_REPOSITORY is not set.'
    }

    $existingRelease = & gh release view $tag --repo $Repository --json url 2>$null
    if ($LASTEXITCODE -eq 0) {
        throw "GitHub release $tag already exists."
    }

    $arguments = @(
        'release', 'create', $tag,
        $archivePath,
        $checksumPath,
        '--repo', $Repository,
        '--target', $commit,
        '--title', "Adaptive Smart Manager v$ReleaseLabel",
        '--notes-file', $notesPath
    )

    if ($Draft) {
        $arguments += '--draft'
    }

    if ($Prerelease) {
        $arguments += '--prerelease'
    }

    & gh @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub release publication failed for $tag."
    }

    $releaseJson = & gh release view $tag --repo $Repository --json tagName,name,url,isDraft,isPrerelease,assets
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to verify GitHub release $tag."
    }

    $release = $releaseJson | ConvertFrom-Json
    if ($release.tagName -ne $tag) {
        throw 'Published release tag verification failed.'
    }

    $assetNames = @($release.assets | ForEach-Object { $_.name })
    if ($archiveName -notin $assetNames) {
        throw "Published release is missing $archiveName."
    }

    if ((Split-Path -Leaf $checksumPath) -notin $assetNames) {
        throw "Published release is missing $(Split-Path -Leaf $checksumPath)."
    }

    $published = $true
    $releaseUrl = [string]$release.url
}

[pscustomobject]@{
    Success          = $true
    ManifestVersion  = $version
    ReleaseLabel     = $ReleaseLabel
    Tag              = $tag
    ProjectRoot      = $repoRoot
    Commit           = $commit
    ArchivePath      = $archivePath
    ChecksumPath     = $checksumPath
    ReleaseNotesPath = $notesPath
    SHA256           = $sha256
    Published        = $published
    ReleaseUrl       = $releaseUrl
} | Format-List
