[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GodotExecutable,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Isolated project: the real mod scripts at their res://mods-unpacked/...
# paths, plus WindowBase / ResourceContainer / Utils test doubles. Never loads
# Upload Labs or a save.
$runtime = Join-Path $ProjectRoot ('release/hub-' + [guid]::NewGuid().ToString('N'))
$modRoot = Join-Path $runtime 'mods-unpacked/Daneisra-BetterResourceManager'
New-Item -ItemType Directory -Path $modRoot | Out-Null
Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tests/hub') -File | Copy-Item -Destination $runtime
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'scripts') -Destination $modRoot -Recurse
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'data/brm_data.json') -Destination $runtime
$cache = Join-Path $runtime '.godot'
New-Item -ItemType Directory -Path $cache | Out-Null
Copy-Item -LiteralPath (Join-Path $runtime 'global_script_class_cache.cfg') -Destination $cache

$log = Join-Path $runtime 'verification.log'
# Godot writes failures to stderr; under 'Stop' PowerShell 5.1 would abort on
# the first line and cut the run short.
$ErrorActionPreference = 'Continue'
$output = & $GodotExecutable --headless --path $runtime --script res://verify_hub.gd 2>&1 | ForEach-Object { "$_" }
$exit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
Set-Content -LiteralPath $log -Value $output -Encoding utf8
$output | Where-Object { $_ -match '^BRM HUB|^ERROR: \[' }
if ($exit -ne 0) { throw "Hub verification failed (exit $exit). Log: $log" }
if (-not (Select-String -LiteralPath $log -Pattern '^BRM HUB: \d+ checks, 0 failures$' -Quiet)) {
    throw "Hub success summary missing. Log: $log"
}
if (Select-String -LiteralPath $log -Pattern '^SCRIPT ERROR:|^ERROR:' -Quiet) {
    throw "Godot reported an error. Log: $log"
}
Write-Output "Verified hub log: $log"
