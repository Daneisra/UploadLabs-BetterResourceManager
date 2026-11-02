[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Archive,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OriginalArchive
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem
$prefix = 'mods-unpacked/Daneisra-BetterResourceManager/'
$expected = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
$rootPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd([char[]]'\/')
foreach ($item in @('manifest.json', 'mod_main.gd', 'data', 'scenes', 'scripts', 'translations', 'LICENSE', 'NOTICE.md', 'README.md')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $rootPath $item) -File -Recurse -Force) {
        $relative = $file.FullName.Substring($rootPath.Length + 1).Replace('\', '/')
        $expected.Add($prefix + $relative, $file.FullName)
    }
}
$sourceMain = Get-Content -LiteralPath (Join-Path $rootPath 'mod_main.gd') -Raw
$buildMatch = [regex]::Match($sourceMain, '(?m)^const MOD_BUILD := "(test21|test22|test23)"\r?$')
if (-not $buildMatch.Success) { throw 'Unknown package build identity.' }
$build = $buildMatch.Groups[1].Value
$fileCount = if ($build -in @('test22','test23')) { 20 } else { 19 }
if ($expected.Count -ne $fileCount) { throw "Expected $fileCount package source files, got $($expected.Count)." }
if ($OriginalArchive -and $build -ne 'test21') {
    throw 'Original-test20 exact gameplay reconciliation is specific to test21. Newer builds intentionally change compatibility behavior; run the unlock and demand regression tests.'
}

function Read-EntryText($Entry) {
    if ($null -eq $Entry) { throw 'Required ZIP entry missing.' }
    $reader = [IO.StreamReader]::new($Entry.Open())
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}
function Normalize-Text([string]$Value) {
    return [regex]::Replace($Value.Replace("`r`n", "`n"), '[\t ]+(?=\n|$)', '').TrimEnd([char[]]"`r`n")
}
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Archive).Path)
$baseline = $null
try {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $zip.Entries) {
        if ($entry.FullName.EndsWith('/')) { continue }
        if (-not $seen.Add($entry.FullName) -or -not $expected.ContainsKey($entry.FullName)) {
            throw "Duplicate or unexpected package entry: $($entry.FullName)"
        }
        $stream = $entry.Open()
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') }
        finally { $stream.Dispose(); $hasher.Dispose() }
        if ($hash -cne (Get-FileHash -LiteralPath $expected[$entry.FullName]).Hash) {
            throw "Package/source byte mismatch: $($entry.FullName)"
        }
    }
    if ($seen.Count -ne $expected.Count) { throw 'Package omits source files.' }
    $main = Read-EntryText $zip.GetEntry($prefix + 'mod_main.gd')
    if ($main -notmatch ('(?m)^const MOD_BUILD := "' + $build + '"\r?$')) { throw "Missing $build runtime identity." }
    $manifest = (Read-EntryText $zip.GetEntry($prefix + 'manifest.json')) | ConvertFrom-Json
    if ($manifest.version_number -ne '0.1.0' -or $manifest.description -notmatch [regex]::Escape("v0.1.0-$build")) {
        throw "Manifest does not identify $build."
    }
    $compiledHash = (Get-FileHash -LiteralPath $expected[$prefix + 'translations/BetterResourceManager.en.translation']).Hash
    if ($compiledHash -cne '997F9B755BDFADE7E23A8D47EE45520F2CD1AC4FE0A3E3ADAD49898A13A17B61') {
        throw 'Compiled translation differs from the 15-message verified test21 asset.'
    }
    if ($OriginalArchive) {
        if ((Get-FileHash -LiteralPath $OriginalArchive).Hash -ne 'B3B8AAD369E28CE19874DEE6BCEEC0E07D84DE9C3914AC05ED708F7FE66C7DFC') {
            throw 'Original archive is not the tested test20 package.'
        }
        $baseline = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $OriginalArchive).Path)
        foreach ($name in $expected.Keys) {
            $relative = $name.Substring($prefix.Length)
            if ($relative -in @('README.md', 'translations/BetterResourceManager.en.translation')) { continue }
            $before = Read-EntryText $baseline.GetEntry($name)
            $after = Read-EntryText $zip.GetEntry($name)
            if ($relative -eq 'manifest.json') {
                $beforeJson = $before | ConvertFrom-Json
                $afterJson = $after | ConvertFrom-Json
                foreach ($field in @('description', 'website_url')) {
                    $beforeJson.PSObject.Properties.Remove($field)
                    $afterJson.PSObject.Properties.Remove($field)
                }
                $before = $beforeJson | ConvertTo-Json -Depth 30 -Compress
                $after = $afterJson | ConvertTo-Json -Depth 30 -Compress
            }
            elseif ($relative -eq 'mod_main.gd') {
                $after = [regex]::Replace($after, '(?m)^const MOD_BUILD := "test21"\r?\n', '')
                $after = $after.Replace('"Adaptive Smart Manager initialized, version: %s (%s recovered test20 package)" % [MOD_VERSION, MOD_BUILD]', '"Adaptive Smart Manager initialized, version: %s (test20 compact unified Demand layout)" % MOD_VERSION')
            }
            if ((Normalize-Text $before) -cne (Normalize-Text $after)) {
                throw "Unexpected original-test20 content change: $relative"
            }
        }
    }
}
finally {
    if ($null -ne $baseline) { $baseline.Dispose() }
    $zip.Dispose()
}
[pscustomobject]@{
    Build = "0.1.0-$build"
    FilesVerified = $expected.Count
    SHA256 = (Get-FileHash -LiteralPath $Archive).Hash.ToLowerInvariant()
    OriginalGameplayVerified = [bool]$OriginalArchive
    InGameValidation = 'pending'
}
