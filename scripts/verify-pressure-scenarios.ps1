Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$casePath = Join-Path $repoRoot 'tests/model-cases.json'
$cases = @(Get-Content -LiteralPath $casePath -Raw -Encoding UTF8 | ConvertFrom-Json)
if ($cases.Count -eq 0) { throw 'Model evaluation needs at least one case.' }
$caseIds = [Collections.Generic.HashSet[string]]::new()
foreach ($case in $cases) {
  if (-not $caseIds.Add($case.id)) { throw "Duplicate case ID: $($case.id)" }
  if ([string]::IsNullOrWhiteSpace($case.prompt) -or [string]::IsNullOrWhiteSpace($case.expectedOutcome)) {
    throw "Case $($case.id) needs a prompt and observable outcome."
  }
  if ($case.shouldTrigger -isnot [bool]) { throw "Case $($case.id) needs a boolean shouldTrigger." }
  if ($case.language -notin @('powershell', 'bash', 'none')) { throw "Invalid language for $($case.id)." }
}
if (@($cases | Where-Object shouldTrigger).Count -eq 0 -or
    @($cases | Where-Object { -not $_.shouldTrigger }).Count -eq 0) {
  throw 'Include both fragile-boundary cases and negative trigger controls.'
}
Write-Host "Model case schema checks passed. Cases: $($cases.Count). No model behavior was evaluated here."
