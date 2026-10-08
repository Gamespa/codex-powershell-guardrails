Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repositoryRoot 'powershell-guardrails/scripts/check-runtime.ps1')
. (Join-Path $repositoryRoot 'tests/helpers.ps1')
Import-Module (Join-Path $PSScriptRoot 'lib/trace.psm1') -Force
$childShell = Join-Path $PSHOME 'pwsh.exe'
$searchTool = (Get-Command rg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$checks = 0
foreach ($suite in Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'tests/behavior') -Filter '*.ps1' -File | Sort-Object Name) {
  # Each suite gets a separate scope and disposable directory.
  & {
    $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('powershell-guardrails-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $fixtureRoot
    $PSNativeCommandUseErrorActionPreference = $false
    try { . $suite.FullName } finally { Remove-TestFixture $fixtureRoot }
  }
  Write-Host "Passed behavior suite: $($suite.BaseName)"
}
Write-Host "Executable behavior verification passed. Assertions: $checks."
