[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GodotExecutable,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Loads every mod script/scene in an isolated project with test doubles of
# Upload Labs' classes, autoloads and base scenes. Copies of the scenes point
# the game icon at a placeholder texture (the real PNG needs the game's import).
$runtime = Join-Path $ProjectRoot ('release/load-' + [guid]::NewGuid().ToString('N'))
$modRoot = Join-Path $runtime 'mods-unpacked/Daneisra-BetterResourceManager'
New-Item -ItemType Directory -Path $modRoot | Out-Null
Copy-Item -Path (Join-Path $ProjectRoot 'tests/load/*') -Destination $runtime -Recurse
foreach ($item in @('manifest.json', 'mod_main.gd', 'data', 'scenes', 'scripts', 'translations')) {
    Copy-Item -LiteralPath (Join-Path $ProjectRoot $item) -Destination $modRoot -Recurse
}
foreach ($scene in Get-ChildItem -LiteralPath $modRoot -Filter '*.tscn' -Recurse) {
    $text = [IO.File]::ReadAllText($scene.FullName)
    $text = $text.Replace('type="Texture2D" path="res://textures/icons/brain.png"', 'type="Texture2D" path="res://stubs/textures/placeholder.tres"')
    [IO.File]::WriteAllText($scene.FullName, $text, [Text.UTF8Encoding]::new($false))
}
New-Item -ItemType Directory -Path (Join-Path $runtime 'scenes/windows'), (Join-Path $runtime 'themes/fonts') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $runtime 'stubs/scenes/window_base.tscn') -Destination (Join-Path $runtime 'scenes/windows')
Copy-Item -LiteralPath (Join-Path $runtime 'stubs/scenes/input_container.tscn'), (Join-Path $runtime 'stubs/scenes/output_container.tscn') -Destination (Join-Path $runtime 'scenes')
Copy-Item -LiteralPath (Join-Path $runtime 'stubs/textures/font.tres') -Destination (Join-Path $runtime 'themes/fonts/main.tres')
$cache = Join-Path $runtime '.godot'
New-Item -ItemType Directory -Path $cache | Out-Null
Copy-Item -LiteralPath (Join-Path $runtime 'global_script_class_cache.cfg') -Destination $cache

$log = Join-Path $runtime 'verification.log'
# Godot writes failures to stderr; under 'Stop' PowerShell 5.1 would abort on
# the first line and cut the run short.
$ErrorActionPreference = 'Continue'
$output = & $GodotExecutable --headless --path $runtime --script res://verify_load.gd 2>&1 | ForEach-Object { "$_" }
$exit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
Set-Content -LiteralPath $log -Value $output -Encoding utf8
$output | Where-Object { $_ -match '^BRM LOAD|^ERROR|^SCRIPT ERROR|Parse Error' } | Select-Object -First 40
if ($exit -ne 0) { throw "Load verification failed (exit $exit). Log: $log" }
if (-not ($output -match '^BRM LOAD: \d+ checks, 0 failures$')) { throw "Load success summary missing. Log: $log" }
if ($output -match '^SCRIPT ERROR:|^ERROR:') { throw "Godot reported an error. Log: $log" }
Write-Output "Verified load log: $log"
