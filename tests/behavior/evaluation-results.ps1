Import-Module (Join-Path $repositoryRoot 'scripts/lib/results.psm1') -Force
$case = [pscustomobject]@{ id = 'case'; shouldTrigger = $true; language = 'powershell'; prompt = 'Review command' }
$run = [pscustomobject]@{ Variant = 'updated'; Repeat = 1; Cases = @($case) }
$trace = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tests/fixtures/read-evidence.jsonl') -Raw
$processResult = [pscustomobject]@{ ExitCode = 0; TimedOut = $false; ElapsedSeconds = 0.1; Stdout = ''; Stderr = ''; Error = $null }
$options = @{
  Run = $run; Model = 'test'; BaselineRef = 'HEAD'; Mode = 'provided-content'; ProcessResult = $processResult
  AnswerExists = $true; AnswerPath = 'answer'; TracePath = 'trace'; CandidateRoot = (Join-Path $repositoryRoot 'powershell-guardrails')
}
$validAnswer = '{"id":"case","use_skill":true,"command":"Get-Item .","rationale":"test"}'
$valid = '{"answers":[' + $validAnswer + ']}'
$record = Get-EvaluationResult @options -AnswerText $valid
Assert-Behavior ($record.status -eq 'completed' -and $record.routeCorrect -eq 1) 'Valid answer rejected.'
foreach ($invalid in @('', '{bad', '{}', ('[' + $valid + ']'), '{"answers":{}}', '{"answers":[null]}',
    '{"answers":[{"id":"case","use_skill":"true","command":"","rationale":"test"}]}',
    '{"answers":[{"id":"case","use_skill":true,"command":1,"rationale":"test"}]}',
    '{"answers":[{"id":"case","use_skill":true,"command":""}]}')) {
  $record = Get-EvaluationResult @options -AnswerText $invalid
  Assert-Behavior ($record.status -eq 'response-check-failed' -and $record.responseErrors.Count -gt 0) 'Malformed answer was not recorded as failure.'
}
$options.AnswerExists = $false
$record = Get-EvaluationResult @options -AnswerText $null
Assert-Behavior ($record.status -eq 'response-check-failed') 'Missing answer did not fail.'
$options.AnswerExists = $true
$record = Get-EvaluationResult @options -AnswerText '{"answers":[]}'
Assert-Behavior ($record.missingIds.Count -eq 1 -and $record.status -eq 'response-check-failed') 'Missing case ID passed.'
$record = Get-EvaluationResult @options -AnswerText ('{"answers":[' + $validAnswer + ',' + $validAnswer + ']}')
Assert-Behavior ($record.duplicateIds.Count -eq 1 -and $record.status -eq 'response-check-failed') 'Duplicate case ID passed.'
$record = Get-EvaluationResult @options -AnswerText ($valid.Replace('"case"', '"other"'))
Assert-Behavior ($record.unexpectedIds.Count -eq 1 -and $record.missingIds.Count -eq 1) 'Unexpected ID not reported.'
$record = Get-EvaluationResult @options -AnswerText ($valid.Replace('Get-Item .', 'if ('))
Assert-Behavior ($record.syntaxErrors.Count -gt 0 -and $record.status -eq 'response-check-failed') 'Invalid PowerShell syntax passed.'
$options.Mode = 'implicit'
$record = Get-EvaluationResult @options -AnswerText $valid
Assert-Behavior ($record.status -eq 'completed' -and $record.triggerCorrect -eq $false) 'Trigger mismatch should remain a completed result with false metric.'
$processResult.Stdout = $trace
$record = Get-EvaluationResult @options -AnswerText $valid
Assert-Behavior ($record.skillRead -and $record.referenceReads.Count -eq 1 -and $record.unverifiedReads.Count -eq 1 -and $record.status -eq 'read-evidence-unverified') 'Trace evidence was misclassified.'
Assert-Behavior ($record.usage.input_tokens -eq 12) 'Usage record lost.'
$processResult.Stdout = ''
$processResult.Stderr = 'SKILL.md blocked by policy'
$options.Mode = 'discovery'
$record = Get-EvaluationResult @options -AnswerText $valid
Assert-Behavior ($record.status -eq 'candidate-read-rejected') 'Discovery read rejection accepted.'
$processResult.ExitCode = 17
$record = Get-EvaluationResult @options -AnswerText $valid
Assert-Behavior ($record.status -eq 'unavailable' -and $record.exitCode -eq 17) 'Nonzero process exit accepted.'
$processResult.ExitCode = 0
$processResult.TimedOut = $true
$record = Get-EvaluationResult @options -AnswerText $valid
Assert-Behavior ($record.status -eq 'unavailable' -and $record.timedOut) 'Timed out process accepted.'
foreach ($count in @(0, 1, 2)) {
  $records = @(for ($i = 0; $i -lt $count; $i++) { $record })
  $json = ConvertTo-EvaluationJson -Records $records
  $parsed = ConvertFrom-Json -InputObject $json -NoEnumerate
  Assert-Behavior ($parsed -is [array] -and $parsed.Count -eq $count) "Result array shape changed at $count records."
}
