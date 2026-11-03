[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Archive,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

# Static verification of the installable ZIP: structure, manifest identity,
# declared incompatibilities, byte-for-byte match with the source, and every
# resource path the scripts and scenes reference.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$modId = 'Daneisra-BetterResourceManager'
$prefix = "mods-unpacked/$modId/"
$rootPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd([char[]]'\/')
$runtimeItems = @('manifest.json', 'mod_main.gd', 'data', 'scenes', 'scripts', 'translations', 'README.md', 'CHANGELOG.md', 'LICENSE', 'NOTICE.md')
$expectedIncompatibilities = @('kuuk-SmartThreadManager', 'kuuk-SmartGPUManager', 'guardipee14-AdaptiveSmartManager')
# Game resources the mod's scenes rely on; they must exist in Upload Labs, not in the ZIP.
$gameResources = @('res://scenes/windows/window_base.tscn', 'res://scenes/input_container.tscn', 'res://scenes/output_container.tscn', 'res://textures/icons/brain.png', 'res://themes/fonts/main.tres')

$expected = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
foreach ($item in $runtimeItems) {
    $source = Join-Path $rootPath $item
    foreach ($file in @(Get-Item -LiteralPath $source) + @(Get-ChildItem -LiteralPath $source -File -Recurse -ErrorAction SilentlyContinue)) {
        if ($file.PSIsContainer) { continue }
        $expected[$prefix + $file.FullName.Substring($rootPath.Length + 1).Replace('\', '/')] = $file.FullName
    }
}

function Read-Entry($Zip, [string]$Name) {
    $entry = $Zip.GetEntry($Name)
    if ($null -eq $entry) { throw "Missing ZIP entry: $Name" }
    $reader = [IO.StreamReader]::new($entry.Open())
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Archive).Path)
try {
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName
        if ($name.Contains('\')) { throw "Backslash in ZIP entry (Godot cannot read it): $name" }
        if ($name.EndsWith('/')) { continue }
        if (-not $name.StartsWith($prefix)) { throw "Entry outside $prefix : $name" }
        if (-not $names.Add($name)) { throw "Duplicate entry: $name" }
        if (-not $expected.ContainsKey($name)) { throw "Unexpected entry: $name" }
        $hasher = [Security.Cryptography.SHA256]::Create()
        $stream = $entry.Open()
        try { $hash = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') }
        finally { $stream.Dispose(); $hasher.Dispose() }
        if ($hash -cne (Get-FileHash -LiteralPath $expected[$name]).Hash) { throw "Entry differs from source: $name" }
    }
    foreach ($name in $expected.Keys) {
        if (-not $names.Contains($name)) { throw "Source file missing from ZIP: $name" }
    }

    $manifest = (Read-Entry $zip ($prefix + 'manifest.json')) | ConvertFrom-Json
    if ("$($manifest.namespace)-$($manifest.name)" -cne $modId) { throw "Manifest id is $($manifest.namespace)-$($manifest.name), expected $modId" }
    if ($manifest.version_number -notmatch '^\d+\.\d+\.\d+$') { throw 'Manifest version is not semantic.' }
    $godot = $manifest.extra.godot
    $incompatibilities = @($godot.incompatibilities)
    foreach ($id in $expectedIncompatibilities) {
        if ($incompatibilities -notcontains $id) { throw "Manifest does not declare incompatibility with $id" }
    }
    if (@($manifest.dependencies).Count -ne 0) { throw 'BRM must not require other mods.' }
    if (@($godot.compatible_mod_loader_version) -notcontains '7.0.1') { throw 'Mod Loader 7.0.1 not declared.' }

    $main = Read-Entry $zip ($prefix + 'mod_main.gd')
    $buildMatch = [regex]::Match($main, '(?m)^const MOD_BUILD := "([^"]*)"')
    if (-not $buildMatch.Success) { throw 'MOD_BUILD missing.' }
    $build = $buildMatch.Groups[1].Value
    if ($main -notmatch [regex]::Escape("const MOD_DIR := `"$modId`"")) { throw 'MOD_DIR does not match the folder.' }

    foreach ($locale in @('en', 'fr')) {
        if ($null -eq $zip.GetEntry($prefix + "translations/BetterResourceManager.$locale.translation")) { throw "Missing $locale translation." }
    }

    # Every window registered must point at a scene shipped in the ZIP.
    $data = (Read-Entry $zip ($prefix + 'data/brm_data.json')) | ConvertFrom-Json
    $windowIds = @($data.windows.PSObject.Properties.Name)
    foreach ($id in @('smart_thread_manager', 'smart_gpu_manager', 'better_resource_hub')) {
        if ($windowIds -notcontains $id) { throw "Window $id not registered." }
        $scene = ([string]$data.windows.$id.scene).Replace('../../', '') + '.tscn'
        if ($null -eq $zip.GetEntry($scene)) { throw "Window $id scene not in ZIP: $scene" }
    }

    # Every res:// path referenced by a shipped script or scene must be shipped
    # too, or be one of the known game resources.
    $missing = [Collections.Generic.List[string]]::new()
    $external = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $zip.Entries | Where-Object { $_.FullName -match '\.(gd|tscn)$' }) {
        $text = Read-Entry $zip $entry.FullName
        foreach ($match in [regex]::Matches($text, 'res://[A-Za-z0-9_./-]+\.(gd|tscn|tres|png|json|translation)')) {
            $path = $match.Value
            if ($path.StartsWith("res://$prefix")) {
                if ($null -eq $zip.GetEntry($path.Substring(6))) { $missing.Add("$($entry.FullName) -> $path") }
            }
            elseif ($path.StartsWith('res://mods-unpacked/')) {
                # Legacy alias targets (kuuk / ASM paths) are intentionally not shipped.
                if ($entry.FullName -notmatch 'legacy_scene_aliases\.gd$|verify') { $missing.Add("$($entry.FullName) -> $path (other mod)") }
            }
            else { [void]$external.Add($path) }
        }
    }
    if ($missing.Count -gt 0) { throw "Unresolved references:`n$($missing -join "`n")" }
    foreach ($path in $external) {
        if ($gameResources -notcontains $path) { throw "Unknown game resource referenced: $path" }
    }
}
finally {
    $zip.Dispose()
}

[pscustomobject]@{
    ModId             = $modId
    Version           = if ($build) { "$($manifest.version_number)-$build" } else { [string]$manifest.version_number }
    FilesVerified     = $expected.Count
    Incompatibilities = $incompatibilities -join ', '
    GameResources     = ($external | Sort-Object) -join ', '
    SHA256            = (Get-FileHash -LiteralPath $Archive).Hash.ToLowerInvariant()
    InGameValidation  = 'pending'
}
