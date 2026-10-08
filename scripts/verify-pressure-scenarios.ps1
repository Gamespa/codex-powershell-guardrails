Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $PSScriptRoot 'lib/cases.psm1')
$cases = @(Read-ModelCases -Path (Join-Path $repoRoot 'tests/model-cases.json'))
Write-Host "Model case schema checks passed. Cases: $($cases.Count). No model behavior was evaluated here."
