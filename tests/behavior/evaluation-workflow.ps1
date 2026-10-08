Import-Module (Join-Path $repositoryRoot 'scripts/lib/evaluation.psm1') -Force
Import-Module (Join-Path $repositoryRoot 'scripts/lib/process.psm1')
$worker = Join-Path $repositoryRoot 'tests/fixtures/model-worker.ps1'
$options = @{
  RepositoryRoot = $repositoryRoot; Model = 'offline'; BaselineRef = '377c95576f9afff270ec59c65877f330e305d5d6'
  Mode = 'provided-content'; Variants = @('updated'); Repeats = 1; TimeoutSeconds = 10
  CaseIds = @('ordinary_git'); Executable = $childShell; UserProfile = $fixtureRoot
}
foreach ($scenario in @('success', 'late-trace', 'malformed', 'wrongtype', 'missing', 'failure', 'timeout')) {
  $options.OutputDirectory = Join-Path $fixtureRoot $scenario
  $options.TimeoutSeconds = if ($scenario -eq 'timeout') { 2 } else { 10 }
  $runner = {
    param($exe, $arguments, $prompt, $timeout, $stdoutPath, $stderrPath)
    $answerPath = $arguments[[array]::IndexOf($arguments, '--output-last-message') + 1]
    Invoke-EvaluationProcess -Executable $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $worker, '-Scenario', $scenario, '-AnswerPath', $answerPath) -Prompt $prompt -TimeoutSeconds $timeout -StdoutPath $stdoutPath -StderrPath $stderrPath
  }.GetNewClosure()
  $options.ProcessRunner = $runner
  if ($scenario -in @('success', 'late-trace')) {
    Invoke-ModelEvaluation @options 6>$null
  } else {
    Assert-Throws { Invoke-ModelEvaluation @options 6>$null } 'One or more model runs were unavailable or invalid'
  }
  $records = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $options.OutputDirectory 'results.json'))) -NoEnumerate
  Assert-Behavior ($records -is [array] -and $records.Count -eq 1) 'Workflow did not write a single-run result array.'
  $record = $records[0]
  Assert-Behavior ($record.semantics.summary.evaluated -eq 0 -and $null -eq $record.semantics.summary.passRate) 'Model-only workflow claimed semantic execution.'
  $expectedStatus = switch ($scenario) { { $_ -in 'success', 'late-trace' } { 'completed' }; { $_ -in 'failure', 'timeout' } { 'unavailable' }; default { 'response-check-failed' } }
  Assert-Behavior ($record.status -eq $expectedStatus) "Unexpected workflow status for $scenario."
  Assert-Behavior ((Get-Content -LiteralPath $record.tracePath -Raw).Contains('turn.completed')) 'Raw trace not preserved.'
  Assert-Behavior ((Get-Content -LiteralPath (Join-Path $options.OutputDirectory 'updated-1/stderr.txt') -Raw).Contains('fixture diagnostic')) 'Raw stderr not preserved.'
  Assert-Behavior (Test-Path -LiteralPath (Join-Path $options.OutputDirectory 'updated-1/workspace/provided-candidate/SKILL.md')) 'Candidate was not materialized.'
  if ($scenario -eq 'malformed') {
    Assert-Behavior ((Get-Content -LiteralPath $record.answersPath -Raw) -ceq '{invalid') 'Malformed answer overwritten.'
  }
  if ($scenario -eq 'wrongtype') { Assert-Behavior ($record.responseErrors.Count -gt 0) 'Invalid answer type lost its diagnostic.' }
  if ($scenario -eq 'late-trace') {
    Assert-Behavior ((Get-Item -LiteralPath $record.tracePath).Length -gt 131072 -and $record.usage.input_tokens -eq 12) 'Full trace was truncated or analysis used only the preview.'
  }
}
# A failed arm must not prevent later arms from being recorded.
$options.OutputDirectory = Join-Path $fixtureRoot 'multiple'
$options.Variants = @('none', 'updated')
$options.TimeoutSeconds = 10
$options.ProcessRunner = {
  param($exe, $arguments, $prompt, $timeout, $stdoutPath, $stderrPath)
  $answerPath = $arguments[[array]::IndexOf($arguments, '--output-last-message') + 1]
  $scenario = if ($answerPath -match 'none-1') { 'malformed' } else { 'success' }
  Invoke-EvaluationProcess -Executable $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $worker, '-Scenario', $scenario, '-AnswerPath', $answerPath) -Prompt $prompt -TimeoutSeconds $timeout -StdoutPath $stdoutPath -StderrPath $stderrPath
}.GetNewClosure()
Assert-Throws { Invoke-ModelEvaluation @options 6>$null } 'One or more model runs'
$multiple = Get-Content -LiteralPath (Join-Path $options.OutputDirectory 'results.json') -Raw | ConvertFrom-Json -NoEnumerate
Assert-Behavior ($multiple.Count -eq 2 -and $multiple[0].status -eq 'response-check-failed' -and $multiple[1].status -eq 'completed') 'Failure prevented later result preservation.'
Assert-Behavior (-not (Test-Path -LiteralPath (Join-Path $options.OutputDirectory 'none-1/workspace/provided-candidate'))) 'No-skill workspace contains a candidate.'

# Public preparation paths must fail before the injected runner is reachable.
$options.ProcessRunner = { throw 'Unexpected model execution' }
Assert-Throws { Invoke-ModelEvaluation @options 6>$null } 'Run directory already exists'
$options.OutputDirectory = Join-Path $fixtureRoot 'invalid-input'
$options.CaseIds = @('missing-case')
Assert-Throws { Invoke-ModelEvaluation @options 6>$null } 'Unknown case ID'
Assert-Behavior (-not (Test-Path -LiteralPath $options.OutputDirectory)) 'Invalid cases created artifacts.'
$options.CaseIds = @('ordinary_git')
$options.Variants = @('original')
$options.BaselineRef = 'nonexistent-baseline'
Assert-Throws { Invoke-ModelEvaluation @options 6>$null } 'Cannot resolve baseline'
Assert-Behavior (-not (Test-Path -LiteralPath $options.OutputDirectory)) 'Invalid baseline created artifacts.'
$options.Variants = @('updated', 'updated')
Assert-Throws { Invoke-ModelEvaluation @options 6>$null } 'distinct'
$options.Variants = @()
Assert-Throws { Invoke-ModelEvaluation @options 6>$null } 'nonempty'
$options.Variants = @('updated')
$options.Repeats = 0
Assert-Throws { Invoke-ModelEvaluation @options 6>$null } 'positive'
$options.Repeats = 1
$options.TimeoutSeconds = 2147484
Assert-Throws { Invoke-ModelEvaluation @options 6>$null } 'timeout'

$options.TimeoutSeconds = 10
$options.OutputDirectory = Join-Path $fixtureRoot 'locked-output'
$null = New-Item -ItemType Directory -Path $options.OutputDirectory
Import-Module (Join-Path $repositoryRoot 'scripts/lib/artifacts.psm1')
$heldLock = Open-EvaluationLock $options.OutputDirectory
try { Assert-Throws { Invoke-ModelEvaluation @options 6>$null } 'Cannot acquire evaluation output lock' }
finally { $heldLock.Dispose() }
Assert-Behavior (-not (Test-Path -LiteralPath (Join-Path $options.OutputDirectory 'updated-1'))) 'Contending evaluation created run artifacts.'

$options.OutputDirectory = Join-Path $fixtureRoot 'runner-exception'
$options.ProcessRunner = { throw 'offline runner crashed' }
Assert-Throws { Invoke-ModelEvaluation @options 6>$null } 'One or more model runs'
$crashed = Get-Content -LiteralPath (Join-Path $options.OutputDirectory 'results.json') -Raw | ConvertFrom-Json -NoEnumerate
Assert-Behavior ($crashed[0].status -eq 'unavailable' -and $crashed[0].processError -match 'offline runner crashed') 'Runner exception lost its result record.'
$releasedLock = Open-EvaluationLock $options.OutputDirectory
$releasedLock.Dispose()
