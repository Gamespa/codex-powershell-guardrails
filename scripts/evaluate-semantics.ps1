param(
  [Parameter(Mandatory)][string]$AnswersPath,
  [Parameter(Mandatory)][string]$Image,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [string[]]$CaseIds
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
& (Join-Path $repoRoot 'powershell-guardrails/scripts/check-runtime.ps1')
Import-Module (Join-Path $PSScriptRoot 'lib/cases.psm1')
Import-Module (Join-Path $PSScriptRoot 'lib/semantics.psm1')
Import-Module (Join-Path $PSScriptRoot 'lib/artifacts.psm1')
$cases = @(Read-ModelCases -Path (Join-Path $repoRoot 'tests/model-cases.json') -CaseIds $CaseIds)
$response = Get-Content -LiteralPath $AnswersPath -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate
if ($response -isnot [Collections.IDictionary] -or $response['answers'] -isnot [array]) { throw 'Expected an object with an answers array.' }
foreach ($answer in $response.answers) {
  if ($answer -isnot [Collections.IDictionary] -or $answer['id'] -isnot [string] -or $answer['command'] -isnot [string]) {
    throw 'Each answer must contain string id and command fields.'
  }
}
$result = Invoke-SemanticEvaluation -Cases $cases -Answers $response.answers -Image $Image -OutputDirectory $OutputDirectory
Write-EvaluationSnapshot -Path (Join-Path $OutputDirectory 'semantics.json') -Content (ConvertTo-Json -InputObject $result -Depth 16)
$result.summary | ConvertTo-Json
if ($result.summary.failed -or $result.summary.infrastructureErrors) { throw 'Semantic checks failed or infrastructure was unavailable; inspect semantics.json.' }
