[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GodotExecutable,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$TranslationDirectory = (Join-Path $ProjectRoot 'translations'),
    [switch]$Rebuild
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$runtime = Join-Path $ProjectRoot ('release/translations-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runtime | Out-Null
Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tests/translations') -File | Copy-Item -Destination $runtime
Copy-Item -LiteralPath (Join-Path $TranslationDirectory 'BetterResourceManager.csv') -Destination $runtime
if ($Rebuild) {
    $buildLog = Join-Path $runtime 'build.log'
    & $GodotExecutable --headless --path $runtime --log-file $buildLog --script res://build_translation.gd
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $buildLog -Pattern '^SCRIPT ERROR:|^ERROR:' -Quiet)) {
        throw "Translation build failed. Log: $buildLog"
    }
}
else {
    Get-ChildItem -LiteralPath $TranslationDirectory -Filter 'BetterResourceManager.*.translation' | Copy-Item -Destination $runtime
}
$log = Join-Path $runtime 'verification.log'
& $GodotExecutable --headless --path $runtime --log-file $log --script res://verify_translation.gd -- res://BetterResourceManager.csv
if ($LASTEXITCODE -ne 0) { throw "Translation verification failed. Log: $log" }
if (-not (Select-String -LiteralPath $log -Pattern '^BRM TRANSLATION: \d+ messages x \d+ locales verified, 0 failures$' -Quiet)) {
    throw "Translation success summary missing. Log: $log"
}
if (Select-String -LiteralPath $log -Pattern '^SCRIPT ERROR:|^ERROR:' -Quiet) { throw "Godot reported an error. Log: $log" }
if ($Rebuild) {
    Get-ChildItem -LiteralPath $runtime -Filter 'BetterResourceManager.*.translation' | Copy-Item -Destination $TranslationDirectory -Force
}
Write-Output "Verified translation log: $log"
