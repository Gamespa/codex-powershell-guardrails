Set-StrictMode -Version Latest
foreach ($module in @('cases', 'candidates', 'prompts', 'process', 'results', 'artifacts', 'semantics')) {
  Import-Module (Join-Path $PSScriptRoot "$module.psm1")
}

function Invoke-ModelEvaluation {
  param([string]$RepositoryRoot, [string]$Model, [string]$BaselineRef,
    [ValidateSet('provided-content', 'discovery', 'implicit')][string]$Mode,
    [ValidateSet('none', 'original', 'updated')][string[]]$Variants,
    [int]$Repeats, [int]$TimeoutSeconds, [string[]]$CaseIds, [string]$OutputDirectory,
    [string]$Executable, [string]$UserProfile, [string]$SemanticImage,
    # Internal seam for offline tests; the public CLI always uses the real runner.
    [scriptblock]$ProcessRunner = { param($exe, $arguments, $prompt, $timeout, $stdoutPath, $stderrPath)
      Invoke-EvaluationProcess -Executable $exe -Arguments $arguments -Prompt $prompt -TimeoutSeconds $timeout -StdoutPath $stdoutPath -StderrPath $stderrPath
    })
  $ErrorActionPreference = 'Stop'
  if ($Repeats -lt 1 -or $TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 2147483) {
    throw 'Repeats and timeout must be positive; timeout cannot exceed 2147483 seconds.'
  }
  if ([string]::IsNullOrWhiteSpace($Model) -or -not $Variants -or
      @($Variants | Select-Object -Unique).Count -ne $Variants.Count) {
    throw 'Model and distinct, nonempty variants are required.'
  }
  $cases = @(Read-ModelCases -Path (Join-Path $RepositoryRoot 'tests/model-cases.json') -CaseIds $CaseIds)
  # Load every requested candidate before creating artifacts or launching a model.
  $bundles = @{}
  foreach ($variant in $Variants) {
    $bundles[$variant] = @(Get-CandidateBundle -RepositoryRoot $RepositoryRoot -Variant $variant -BaselineRef $BaselineRef)
  }
  if (-not $Executable) {
    $Executable = (Get-Command codex -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
  }
  if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $RepositoryRoot ('artifacts/model-eval-' + [guid]::NewGuid().ToString('N'))
  }
  $runs = @(Get-EvaluationRuns -Cases $cases -Mode $Mode -Variants $Variants -Repeats $Repeats)
  $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
  $outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
  $outputLock = Open-EvaluationLock -OutputRoot $outputRoot
  try {
    # Prevent stale answers/traces from an earlier run from being counted as fresh evidence.
    foreach ($run in $runs) {
      if (Test-Path -LiteralPath (Join-Path $OutputDirectory $run.Name)) { throw "Run directory already exists: $($run.Name)" }
    }
    if (Test-Path -LiteralPath (Join-Path $OutputDirectory 'results.json')) { throw 'Output directory already contains results.json.' }
    $utf8 = [Text.UTF8Encoding]::new($false)
    $schemaPath = Join-Path $outputRoot 'response-schema.json'
    [IO.File]::WriteAllText($schemaPath, (Get-ResponseSchema), $utf8)
    $disabledSkills = @()
    foreach ($base in @('.agents', '.codex')) {
      $installedPath = Join-Path $UserProfile "$base/skills/powershell-guardrails/SKILL.md"
      if (Test-Path -LiteralPath $installedPath) {
        $tomlPath = ($installedPath -replace '\\', '/') | ConvertTo-Json -Compress
        $disabledSkills += "{path=$tomlPath,enabled=false}"
      }
    }
    $skillConfig = 'skills.config=[' + ($disabledSkills -join ',') + ']'
    $records = [Collections.Generic.List[object]]::new()
    foreach ($run in $runs) {
      $runRoot = Join-Path $outputRoot $run.Name
      $workspace = Join-Path $runRoot 'workspace'
      $null = New-Item -ItemType Directory -Path $workspace -Force
      $candidateDirectory = if ($Mode -eq 'provided-content') { 'provided-candidate' } else { '.agents/skills/powershell-guardrails' }
      $candidateRoot = Join-Path $workspace $candidateDirectory
      foreach ($file in $bundles[$run.Variant]) {
        $destination = Join-Path $candidateRoot $file.Path
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
        [IO.File]::WriteAllText($destination, $file.Content, $utf8)
      }
      $prompt = New-EvaluationPrompt -Cases $run.Cases -Mode $Mode -Variant $run.Variant -Bundle $bundles[$run.Variant]
      $answerPath = Join-Path $runRoot 'answers.json'
      $tracePath = Join-Path $runRoot 'trace.jsonl'
      $stderrPath = Join-Path $runRoot 'stderr.txt'
      $arguments = @(Get-CodexArguments -Model $Model -Workspace $workspace -SchemaPath $schemaPath -AnswerPath $answerPath -SkillConfig $skillConfig)
      Write-Host "Evaluating $($run.Variant), repeat $($run.Repeat), model ${Model}..."
      try { $processResult = & $ProcessRunner $Executable $arguments $prompt $TimeoutSeconds $tracePath $stderrPath }
      catch {
        $processResult = [pscustomobject]@{ ExitCode = $null; TimedOut = $false; ElapsedSeconds = 0; Stdout = ''; Stderr = ''; Error = $_.Exception.Message }
      }
      # Compatibility for injected offline runners returning text instead of files.
      if (-not (Test-Path -LiteralPath $tracePath)) { [IO.File]::WriteAllText($tracePath, $processResult.Stdout, $utf8) }
      if (-not (Test-Path -LiteralPath $stderrPath)) { [IO.File]::WriteAllText($stderrPath, $processResult.Stderr, $utf8) }
      $answerExists = Test-Path -LiteralPath $answerPath -PathType Leaf
      $answerText = if ($answerExists) { [IO.File]::ReadAllText($answerPath) } else { $null }
      $resultOptions = @{
        Run = $run; Model = $Model; BaselineRef = $BaselineRef; Mode = $Mode
        ProcessResult = $processResult; AnswerText = $answerText; AnswerExists = $answerExists
        AnswerPath = $answerPath; TracePath = $tracePath; CandidateRoot = $candidateRoot; Workspace = $workspace; StderrPath = $stderrPath
      }
      $record = Get-EvaluationResult @resultOptions
      $answers = if ($record.status -eq 'completed') { @((ConvertFrom-Json -InputObject $answerText).answers) } else { @() }
      $semantic = Invoke-SemanticEvaluation -Cases $run.Cases -Answers $answers -Image $SemanticImage -OutputDirectory (Join-Path $runRoot 'semantics') -ResponseValid ($record.status -eq 'completed')
      $record | Add-Member -NotePropertyName semantics -NotePropertyValue $semantic
      $records.Add($record)
      Write-EvaluationSnapshot -Path (Join-Path $outputRoot 'results.json') -Content (ConvertTo-EvaluationJson -Records $records.ToArray())
      Write-Host "Finished $($run.Variant): $($record.status), exit $($record.exitCode)."
      Write-Host "Semantics: $($semantic.summary.passed) passed, $($semantic.summary.failed) failed, $($semantic.summary.infrastructureErrors) infrastructure errors, $($semantic.summary.notEvaluated) not evaluated."
    }
    Write-Host "Model evaluation artifacts: $outputRoot"
    Write-Host 'Routing is self-reported; syntax checks are not semantic execution. Provided-content mode does not test skill discovery.'
    Write-Host 'Inspect completed read evidence and review commands against expectedOutcome; unsupported read protocols require manual trace review.'
    if (@($records | Where-Object status -ne 'completed').Count -gt 0) {
      throw 'One or more model runs were unavailable or invalid; inspect stderr and results rather than reporting a pass.'
    }
    if (@($records | Where-Object { $_.semantics.summary.failed -gt 0 -or $_.semantics.summary.infrastructureErrors -gt 0 }).Count) {
      throw 'Semantic evaluation failed or its isolated backend was unavailable; inspect semantics in results.json.'
    }
  } finally { $outputLock.Dispose() }
}

Export-ModuleMember -Function Invoke-ModelEvaluation
