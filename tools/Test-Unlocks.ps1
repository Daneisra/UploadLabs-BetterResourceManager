[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GodotExecutable,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$runtime = Join-Path $ProjectRoot ('release/unlocks-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runtime | Out-Null
Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tests/unlocks') -File | Copy-Item -Destination $runtime
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'scripts/global/manager_unlocks.gd') -Destination $runtime
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'data/brm_data.json') -Destination $runtime
$log = Join-Path $runtime 'verification.log'
& $GodotExecutable --headless --path $runtime --log-file $log --script res://verify_unlocks.gd
if ($LASTEXITCODE -ne 0) { throw "Unlock verification failed. Log: $log" }
if (-not (Select-String -LiteralPath $log -Pattern '^ASM UNLOCKS: \d+ checks, 0 failures$' -Quiet)) {
    throw "Unlock success summary missing. Log: $log"
}
if (Select-String -LiteralPath $log -Pattern '^SCRIPT ERROR:|^ERROR:' -Quiet) {
    throw "Godot reported an error. Log: $log"
}
Write-Output "Verified unlock log: $log"
