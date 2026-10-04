Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
& (Join-Path $repoRoot 'powershell-guardrails/scripts/check-runtime.ps1')

foreach ($verifier in @('verify-skill.ps1', 'verify-pressure-scenarios.ps1', 'verify-behavior.ps1')) {
  & (Join-Path $PSScriptRoot $verifier)
}
git -C $repoRoot diff --check
$diffExit = $LASTEXITCODE
if ($diffExit -ne 0) {
  throw "git diff --check failed with exit code $diffExit."
}

Write-Host 'Repository validation chain passed.'
