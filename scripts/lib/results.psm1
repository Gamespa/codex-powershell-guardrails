Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'trace.psm1')

function Get-EvaluationResult {
  param($Run, [string]$Model, [string]$BaselineRef, [string]$Mode, $ProcessResult,
    [AllowNull()][string]$AnswerText, [bool]$AnswerExists, [string]$AnswerPath,
    [string]$TracePath, [string]$CandidateRoot)
  $cases = $Run.Cases
  $record = [ordered]@{
    variant = $Run.Variant; repeat = $Run.Repeat; model = $Model; baselineRef = $BaselineRef; mode = $Mode
    exitCode = $ProcessResult.ExitCode; timedOut = $ProcessResult.TimedOut; elapsedSeconds = $ProcessResult.ElapsedSeconds
    status = 'unavailable'; routeCorrect = $null; routeTotal = $null
    syntaxErrors = @(); missingIds = @(); duplicateIds = @(); unexpectedIds = @(); usage = $null
    candidateReadRejected = $false
    caseIds = @($cases.id); skillRead = $null; referenceReads = @(); unverifiedReads = @()
    triggerCorrect = $null
    invocationKind = if ($Mode -eq 'implicit' -and $cases[0].prompt -match '(?i)powershell-guardrails') { 'explicit' } else { $Mode }
    answersPath = $AnswerPath; tracePath = $TracePath
    responseErrors = @(); processError = $ProcessResult.Error
  }
  foreach ($line in $ProcessResult.Stdout -split '\r?\n') {
    try { $event = ConvertFrom-Json -InputObject $line -AsHashtable -NoEnumerate } catch { continue }
    if ($event -is [System.Collections.IDictionary] -and $event['type'] -eq 'turn.completed' -and $event.Contains('usage')) {
      $record.usage = $event.usage
    }
  }
  if ($ProcessResult.ExitCode -ne 0 -or $ProcessResult.TimedOut -or $ProcessResult.Error) {
    return [pscustomobject]$record
  }
  $record.status = 'completed'
  $record.candidateReadRejected = ($ProcessResult.Stdout -match '(?i)(?:Markdown|PowerShell|script|helper) (?:source )?read.{0,100}block|skill read.{0,100}policy.blocked|couldn.t inspect.{0,100}SKILL') -or
    ($ProcessResult.Stderr -match '(?im)SKILL\.md.*blocked by policy|blocked by policy.*SKILL\.md|references[/\\].*blocked by policy')
  if ($Mode -ne 'provided-content' -and $record.candidateReadRejected) { $record.status = 'candidate-read-rejected' }
  if ($Mode -eq 'implicit' -and $Run.Variant -ne 'none') {
    $evidence = Get-SkillReadEvidence -Trace $ProcessResult.Stdout -SkillRoot $CandidateRoot
    $record.skillRead = $evidence.skillRead
    $record.referenceReads = $evidence.referenceReads
    $record.unverifiedReads = $evidence.unverifiedReads
    if (-not $record.candidateReadRejected) { $record.triggerCorrect = $evidence.skillRead -eq $cases[0].shouldTrigger }
    if ($evidence.unverifiedReads.Count -gt 0) { $record.status = 'read-evidence-unverified' }
  }
  try {
    if (-not $AnswerExists) { throw 'Answer file is missing.' }
    $response = ConvertFrom-Json -InputObject $AnswerText -AsHashtable -NoEnumerate -ErrorAction Stop
    if ($response -isnot [System.Collections.IDictionary] -or $response['answers'] -isnot [array]) {
      throw 'Response must be an object with an answers array.'
    }
    if (@($response.Keys | Where-Object { $_ -ne 'answers' }).Count) { throw 'Unexpected response fields.' }
    $answers = $response.answers
    foreach ($answer in $answers) {
      if ($answer -isnot [System.Collections.IDictionary]) { throw 'Each answer must be an object.' }
      foreach ($field in @('id', 'command', 'rationale')) {
        if ($answer[$field] -isnot [string]) { throw "Answer $field must be a string." }
      }
      if ($answer['use_skill'] -isnot [bool]) { throw 'Answer use_skill must be boolean.' }
      if (@($answer.Keys | Where-Object { $_ -notin @('id', 'command', 'rationale', 'use_skill') }).Count) {
        throw 'Unexpected answer fields.'
      }
    }
    $answerIds = @($answers | ForEach-Object { $_.id })
    $record.missingIds = @($cases.id | Where-Object { $_ -notin $answerIds })
    $record.duplicateIds = @($answers | Group-Object id | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)
    $record.unexpectedIds = @($answerIds | Where-Object { $_ -notin $cases.id })
    if ($Run.Variant -ne 'none') { $record.routeTotal = $cases.Count; $record.routeCorrect = 0 }
    foreach ($case in $cases) {
      $answer = @($answers | Where-Object { $_.id -eq $case.id })
      if ($answer.Count -ne 1) { continue }
      if ($Run.Variant -ne 'none' -and $answer[0].use_skill -eq $case.shouldTrigger) { $record.routeCorrect++ }
      if ($case.language -eq 'powershell' -and $answer[0].command) {
        $tokens = $null; $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseInput($answer[0].command, [ref]$tokens, [ref]$errors)
        foreach ($parseError in $errors) { $record.syntaxErrors += "$($case.id): $($parseError.Message)" }
      }
    }
    if ($record.missingIds.Count -or $record.duplicateIds.Count -or $record.unexpectedIds.Count -or $record.syntaxErrors.Count) {
      $record.status = 'response-check-failed'
    }
  } catch {
    $record.responseErrors += $_.Exception.Message
    $record.status = 'response-check-failed'
  }
  [pscustomobject]$record
}

function ConvertTo-EvaluationJson {
  param([AllowEmptyCollection()][object[]]$Records)
  ConvertTo-Json -InputObject @($Records) -Depth 12
}

Export-ModuleMember -Function Get-EvaluationResult, ConvertTo-EvaluationJson
