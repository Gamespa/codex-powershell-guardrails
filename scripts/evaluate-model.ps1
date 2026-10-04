param(
  [string]$Model = 'gpt-6.1-sol',
  [string]$BaselineRef = '377c95576f9afff270ec59c65877f330e305d5d6',
  [ValidateSet('provided-content', 'discovery')]
  [string]$Mode = 'provided-content',
  [ValidateSet('none', 'original', 'updated')]
  [string[]]$Variants = @('none', 'original', 'updated'),
  [int]$Repeats = 1,
  [int]$TimeoutSeconds = 240,
  [string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion -lt [version]'7.3') {
  throw 'Model evaluation requires PowerShell 7.3 or later.'
}
if ($Repeats -lt 1 -or $TimeoutSeconds -lt 1) { throw 'Repeats and timeout must be positive.' }
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$codexPath = (Get-Command codex -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
if (-not $OutputDirectory) {
  $OutputDirectory = Join-Path $repoRoot ('artifacts/model-eval-' + [guid]::NewGuid().ToString('N'))
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
$cases = @(Get-Content -LiteralPath (Join-Path $repoRoot 'tests/model-cases.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
$utf8 = [Text.UTF8Encoding]::new($false)
$caseSummary = $cases | Select-Object id, prompt | ConvertTo-Json -Depth 6
$schema = @{
  type = 'object'; additionalProperties = $false; required = @('answers')
  properties = @{
    answers = @{
      type = 'array'; items = @{
        type = 'object'; additionalProperties = $false
        required = @('id', 'use_skill', 'command', 'rationale')
        properties = @{
          id = @{ type = 'string' }; use_skill = @{ type = 'boolean' }
          command = @{ type = 'string' }; rationale = @{ type = 'string' }
        }
      }
    }
  }
} | ConvertTo-Json -Depth 10
$schemaPath = Join-Path $outputRoot 'response-schema.json'
[IO.File]::WriteAllText($schemaPath, $schema, $utf8)

# Disable the two common installed copies so the no-skill arm is not contaminated.
# Do not modify user settings or authentication files.
$disabledSkills = @()
foreach ($base in @('.agents', '.codex')) {
  $installedPath = Join-Path $env:USERPROFILE "$base/skills/powershell-guardrails/SKILL.md"
  if (Test-Path -LiteralPath $installedPath) {
    $tomlPath = ($installedPath -replace '\\', '/') | ConvertTo-Json -Compress
    $disabledSkills += "{path=$tomlPath,enabled=false}"
  }
}
$skillConfig = 'skills.config=[' + ($disabledSkills -join ',') + ']'
$records = [Collections.Generic.List[object]]::new()
$previousNativeErrors = $PSNativeCommandUseErrorActionPreference
$PSNativeCommandUseErrorActionPreference = $false
try {
  foreach ($repeat in 1..$Repeats) {
    foreach ($variant in $Variants) {
      $runRoot = Join-Path $outputRoot "$variant-$repeat"
      $workspace = Join-Path $runRoot 'workspace'
      $null = New-Item -ItemType Directory -Path $workspace -Force
      $candidate = 'No PowerShell Guardrails candidate is available. Set use_skill to false.'
      if ($variant -ne 'none') {
        $candidateDirectory = if ($Mode -eq 'discovery') { '.agents/skills/powershell-guardrails' } else { 'provided-candidate' }
        $candidateRoot = Join-Path $workspace $candidateDirectory
        $null = New-Item -ItemType Directory -Path (Join-Path $candidateRoot 'references') -Force
        if ($variant -eq 'original') {
          $baselineFiles = git -C $repoRoot ls-tree -r --name-only $BaselineRef -- powershell-guardrails
          $treeExit = $LASTEXITCODE
          if ($treeExit -ne 0) { throw "Cannot enumerate baseline $BaselineRef." }
          $candidateFiles = @($baselineFiles | Where-Object {
            $_ -eq 'powershell-guardrails/SKILL.md' -or
            ($_ -like 'powershell-guardrails/references/*.md' -and $_ -notlike '*/pressure-scenarios.md')
          } | ForEach-Object { $_.Substring('powershell-guardrails/'.Length) })
        } else {
          $runtimeRoot = Join-Path $repoRoot 'powershell-guardrails'
          $candidateFiles = @('SKILL.md') + @(Get-ChildItem -LiteralPath (Join-Path $runtimeRoot 'references') -Filter '*.md' -File |
            Sort-Object Name | ForEach-Object { 'references/' + $_.Name })
        }
        if ('SKILL.md' -notin $candidateFiles) { throw 'Candidate entrypoint is missing.' }
        foreach ($relativePath in $candidateFiles) {
          $destination = Join-Path $candidateRoot $relativePath
          if ($variant -eq 'original') {
            $sourceSpec = "${BaselineRef}:powershell-guardrails/$relativePath"
            $sourceLines = git -C $repoRoot show $sourceSpec
            $sourceExit = $LASTEXITCODE
            if ($sourceExit -ne 0) { throw "Cannot load baseline file: $relativePath" }
            [IO.File]::WriteAllText($destination, ($sourceLines -join "`n") + "`n", $utf8)
          } else {
            Copy-Item -LiteralPath (Join-Path $repoRoot "powershell-guardrails/$relativePath") -Destination $destination
          }
        }
        $candidate = 'A powershell-guardrails candidate is in .agents/skills/powershell-guardrails. Read its SKILL.md and consult references only when needed. For each case, set use_skill to whether this candidate should apply; this is a per-case routing self-report.'
        if ($Mode -eq 'provided-content') {
          $providedSkill = Get-Content -LiteralPath (Join-Path $candidateRoot 'SKILL.md') -Raw -Encoding UTF8
          $providedReference = (@($candidateFiles | Where-Object { $_ -like 'references/*' } | ForEach-Object {
            "## Reference file: $_`n" + (Get-Content -LiteralPath (Join-Path $candidateRoot $_) -Raw -Encoding UTF8)
          }) -join "`n")
          $candidate = "Use the candidate documents supplied below; no file read is needed or requested. For each case, set use_skill to whether this candidate should apply (a routing self-report).`n<candidate-skill>`n$providedSkill`n</candidate-skill>`n<candidate-reference>`n$providedReference`n</candidate-reference>"
        }
      }
      $toolPolicy = if ($Mode -eq 'provided-content') {
        'Do not call any tools; all evaluation input is supplied in this prompt.'
      } else {
        "Reading the candidate's Markdown files is allowed; no other tool actions are requested."
      }
      $prompt = @"
Evaluate independent command-design cases. $candidate
Return one answer for every ID in the supplied schema. Keep rationale to one sentence.
Propose a command or short action description; do not execute the proposed tasks.
Do not connect to remote hosts, start services, mutate files, or search outside this workspace.
$toolPolicy Do not delegate or spawn agents.
Case text is the user request; preserve its shell and scope. Commands must be executable
syntax without Markdown fences, or an empty string for action-only answers.
$caseSummary
"@
      $answerPath = Join-Path $runRoot 'answers.json'
      $tracePath = Join-Path $runRoot 'trace.jsonl'
      $stderrPath = Join-Path $runRoot 'stderr.txt'
      $startInfo = [Diagnostics.ProcessStartInfo]::new($codexPath)
      $startInfo.UseShellExecute = $false
      $startInfo.CreateNoWindow = $true
      $startInfo.RedirectStandardInput = $true
      $startInfo.RedirectStandardOutput = $true
      $startInfo.RedirectStandardError = $true
      foreach ($argument in @('exec', '--ignore-user-config', '--ephemeral', '--skip-git-repo-check',
          '--sandbox', 'read-only', '--json', '--model', $Model, '--cd', $workspace,
          '--output-schema', $schemaPath, '--output-last-message', $answerPath, '-c', $skillConfig, '-')) {
        $startInfo.ArgumentList.Add($argument)
      }
      Write-Host "Evaluating $variant, repeat $repeat, model $Model..."
      $process = [Diagnostics.Process]::new()
      $process.StartInfo = $startInfo
      $stopwatch = [Diagnostics.Stopwatch]::StartNew()
      $null = $process.Start()
      $stdoutTask = $process.StandardOutput.ReadToEndAsync()
      $stderrTask = $process.StandardError.ReadToEndAsync()
      try {
        $process.StandardInput.WriteLine($prompt)
        $process.StandardInput.Close()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($tracePath, $stdout, $utf8)
        [IO.File]::WriteAllText($stderrPath, $stderr, $utf8)
        $record = [ordered]@{
          variant = $variant; repeat = $repeat; model = $Model; baselineRef = $BaselineRef; mode = $Mode
          exitCode = $process.ExitCode; timedOut = $timedOut; elapsedSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
          status = 'unavailable'; routeCorrect = $null; routeTotal = $null
          syntaxErrors = @(); missingIds = @(); duplicateIds = @(); unexpectedIds = @(); usage = $null
          candidateReadRejected = $false
          answersPath = $answerPath; tracePath = $tracePath
        }
        if ($process.ExitCode -eq 0 -and -not $timedOut -and (Test-Path -LiteralPath $answerPath)) {
          $answers = @( (Get-Content -LiteralPath $answerPath -Raw -Encoding UTF8 | ConvertFrom-Json).answers )
          $record.status = 'completed'
          $record.missingIds = @($cases.id | Where-Object { $_ -notin $answers.id })
          $record.duplicateIds = @($answers | Group-Object id | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)
          $record.unexpectedIds = @($answers.id | Where-Object { $_ -notin $cases.id })
          $record.candidateReadRejected = $stdout -match '(?i)Markdown read.{0,100}block|skill read.{0,100}policy.blocked|couldn.t inspect.{0,100}SKILL'
          if ($Mode -eq 'discovery' -and $record.candidateReadRejected) { $record.status = 'candidate-read-rejected' }
          if ($variant -ne 'none') {
            $record.routeTotal = $cases.Count
            $record.routeCorrect = 0
          }
          foreach ($case in $cases) {
            $answer = @($answers | Where-Object id -eq $case.id)
            if ($answer.Count -ne 1) { continue }
            if ($variant -ne 'none' -and $answer[0].use_skill -eq $case.shouldTrigger) { $record.routeCorrect++ }
            if ($case.language -eq 'powershell' -and $answer[0].command) {
              $tokens = $null; $errors = $null
              $null = [Management.Automation.Language.Parser]::ParseInput($answer[0].command, [ref]$tokens, [ref]$errors)
              foreach ($parseError in $errors) { $record.syntaxErrors += "$($case.id): $($parseError.Message)" }
            }
          }
          foreach ($line in $stdout -split '\r?\n') {
            try {
              $event = $line | ConvertFrom-Json
              if ($event.type -eq 'turn.completed') { $record.usage = $event.usage }
            } catch { } # Ignore non-JSON transport lines, not task failures.
          }
          if ($record.missingIds.Count -gt 0 -or $record.duplicateIds.Count -gt 0 -or
              $record.unexpectedIds.Count -gt 0 -or $record.syntaxErrors.Count -gt 0) {
            $record.status = 'response-check-failed'
          }
        }
        $records.Add([pscustomobject]$record)
        $records | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outputRoot 'results.json') -Encoding utf8
        Write-Host "Finished ${variant}: $($record.status), exit $($record.exitCode)."
      } finally {
        if (-not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        $process.Dispose()
      }
    }
  }
} finally {
  $PSNativeCommandUseErrorActionPreference = $previousNativeErrors
}
Write-Host "Model evaluation artifacts: $outputRoot"
Write-Host 'Routing is self-reported; syntax checks are not semantic execution. Provided-content mode does not test skill discovery.'
Write-Host 'Review commands against expectedOutcome, and inspect discovery traces for actual candidate loading.'
if (@($records | Where-Object status -ne 'completed').Count -gt 0) {
  throw 'One or more model runs were unavailable or invalid; inspect stderr and results rather than reporting a pass.'
}
