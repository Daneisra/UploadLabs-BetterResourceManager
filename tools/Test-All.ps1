[CmdletBinding()]
param(
    [string]$GodotExecutable = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'UploadLabs-Tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'),
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    # Also verify this ZIP (tools/New-Release.ps1 output).
    [string]$Archive
)

# Runs every isolated suite. None of them starts Upload Labs or opens a save.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not (Test-Path -LiteralPath $GodotExecutable)) { throw "Godot console executable not found: $GodotExecutable" }

$results = [Collections.Generic.List[object]]::new()
foreach ($suite in @('Load', 'Hub', 'Demand', 'Unlocks', 'Translations')) {
    $started = Get-Date
    try {
        $output = & (Join-Path $PSScriptRoot "Test-$suite.ps1") -GodotExecutable $GodotExecutable -ProjectRoot $ProjectRoot 2>&1 | ForEach-Object { "$_" }
        $summary = ($output | Where-Object { $_ -match '^(BRM|ASM) [A-Z]+: ' } | Select-Object -Last 1)
        $results.Add([pscustomobject]@{ Suite = $suite; Result = 'passed'; Summary = $summary; Seconds = [int]((Get-Date) - $started).TotalSeconds })
    }
    catch {
        $results.Add([pscustomobject]@{ Suite = $suite; Result = 'FAILED'; Summary = $_.Exception.Message; Seconds = [int]((Get-Date) - $started).TotalSeconds })
    }
}
if ($Archive) {
    try {
        $package = & (Join-Path $PSScriptRoot 'Test-Package.ps1') -Archive $Archive -ProjectRoot $ProjectRoot
        $results.Add([pscustomobject]@{ Suite = 'Package'; Result = 'passed'; Summary = "$($package.FilesVerified) files, sha256 $($package.SHA256)"; Seconds = 0 })
    }
    catch {
        $results.Add([pscustomobject]@{ Suite = 'Package'; Result = 'FAILED'; Summary = $_.Exception.Message; Seconds = 0 })
    }
}
$results | Format-Table -AutoSize -Wrap
if ($results.Result -contains 'FAILED') { throw 'At least one suite failed.' }
