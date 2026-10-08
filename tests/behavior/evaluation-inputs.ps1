foreach ($name in @('cases', 'candidates', 'prompts')) {
  Import-Module (Join-Path $repositoryRoot "scripts/lib/$name.psm1") -Force
}
$importProbe = Write-Fixture 'import-probe.ps1' @'
param([string]$RepositoryRoot, [string]$WorkingDirectory)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
function git { throw 'Module import must not invoke Git.' }
function codex { throw 'Module import must not invoke a model.' }
Set-Location -LiteralPath $WorkingDirectory
$before = @(Get-ChildItem -LiteralPath $WorkingDirectory -Recurse -Force).Count
$output = @(foreach ($file in Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'scripts/lib') -Filter '*.psm1') {
  Import-Module $file.FullName -Force
})
if ($output.Count -ne 0 -or @(Get-ChildItem -LiteralPath $WorkingDirectory -Recurse -Force).Count -ne $before) {
  throw 'Module import produced output or created artifacts.'
}
if (-not $PSNativeCommandUseErrorActionPreference -or $ErrorActionPreference -ne 'Stop') {
  throw 'Module import changed caller preferences.'
}
'@
$importOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File $importProbe $repositoryRoot $fixtureRoot 2>&1
$importExit = $LASTEXITCODE
Assert-Behavior ($importExit -eq 0) "Module import has side effects: $($importOutput -join ' ')"
$casePath = Join-Path $repositoryRoot 'tests/model-cases.json'
$cases = @(Read-ModelCases $casePath)
$subset = @(Read-ModelCases $casePath -CaseIds ordinary_git)
Assert-Behavior ($subset.Count -eq 1 -and -not $subset[0].shouldTrigger) 'Single-case selection lost its negative control.'
Assert-Throws { Read-ModelCases $casePath -CaseIds unknown_case } 'Unknown case ID'
foreach ($mutation in @('duplicate', 'missing', 'type', 'path', 'controls', 'shape', 'validator', 'validator-version', 'validator-extra')) {
  $invalid = @(Get-Content -LiteralPath $casePath -Raw | ConvertFrom-Json)
  switch ($mutation) {
    'duplicate' { $invalid[1].id = $invalid[0].id }
    'missing' { $invalid[0].PSObject.Properties.Remove('expectedOutcome') }
    'type' { $invalid[0].shouldTrigger = 'true' }
    'path' { $invalid[0].id = '../escape' }
    'controls' { $invalid = @($invalid | Where-Object shouldTrigger) }
    'shape' { $invalid = $invalid[0] }
    'validator' { ($invalid | Where-Object id -eq 'modern_native_quotes').validator.id = 'unknown-validator' }
    'validator-version' { ($invalid | Where-Object id -eq 'modern_native_quotes').validator.version = 2 }
    'validator-extra' { ($invalid | Where-Object id -eq 'modern_native_quotes').validator | Add-Member -NotePropertyName script -NotePropertyValue 'untrusted.ps1' }
  }
  $invalidPath = Write-Fixture "$mutation.json" (ConvertTo-Json -InputObject $invalid -Depth 8)
  Assert-Throws { Read-ModelCases $invalidPath } 'case|Case|controls|boolean|validator'
}
foreach ($mode in @('provided-content', 'discovery', 'implicit')) {
  $runs = @(Get-EvaluationRuns -Cases $cases -Mode $mode -Variants none,original,updated -Repeats 2)
  $expectedCount = if ($mode -eq 'implicit') { 6 * $cases.Count } else { 6 }
  Assert-Behavior ($runs.Count -eq $expectedCount) "Wrong run count in $mode."
  Assert-Behavior (@($runs.Name | Select-Object -Unique).Count -eq $runs.Count) 'Run names collide.'
  if ($mode -eq 'implicit') {
    Assert-Behavior (@($runs | Where-Object { $_.Cases.Count -ne 1 }).Count -eq 0) 'Implicit cases were grouped.'
  }
}
$updated = @(Get-CandidateBundle -RepositoryRoot $repositoryRoot -Variant updated)
$original = @(Get-CandidateBundle -RepositoryRoot $repositoryRoot -Variant original -BaselineRef '377c95576f9afff270ec59c65877f330e305d5d6')
$empty = @(Get-CandidateBundle -RepositoryRoot $repositoryRoot -Variant none)
Assert-Behavior ($empty.Count -eq 0) 'No-skill arm contains candidate content.'
foreach ($bundle in @(@{ Files = $updated }, @{ Files = $original })) {
  Assert-Behavior ('SKILL.md' -in $bundle.Files.Path) 'Candidate entrypoint missing.'
  Assert-Behavior (@($bundle.Files | Where-Object Path -like 'references/*').Count -gt 0) 'Candidate references missing.'
  Assert-Behavior (@($bundle.Files | Where-Object Path -match 'pressure-scenarios|tests/|docs/').Count -eq 0) 'Maintenance content leaked into candidate.'
}
Assert-Behavior ('scripts/check-runtime.ps1' -in $updated.Path -and 'agents/openai.yaml' -in $updated.Path) 'Current candidate helpers or metadata missing.'
$nativeBefore = $PSNativeCommandUseErrorActionPreference
Assert-Throws { Get-CandidateBundle -RepositoryRoot $repositoryRoot -Variant original -BaselineRef missing-ref-for-test } 'Cannot resolve baseline'
Assert-Behavior ($PSNativeCommandUseErrorActionPreference -eq $nativeBefore) 'Candidate loading leaked native error preference.'
$provided = New-EvaluationPrompt -Cases $subset -Mode provided-content -Variant updated -Bundle $updated
Assert-Behavior ($provided.Contains('<candidate-skill>') -and $provided.Contains('Do not call any tools')) 'Provided-content prompt lost its content or tool boundary.'
Assert-Behavior (-not $provided.Contains($subset[0].expectedOutcome)) 'Expected outcome leaked into prompt.'
$semanticCase = @($cases | Where-Object id -eq 'modern_native_quotes')
$semanticPrompt = New-EvaluationPrompt -Cases $semanticCase -Mode implicit -Variant updated -Bundle $updated
Assert-Behavior ($semanticPrompt.Contains('$nativeExecutable') -and $semanticPrompt.Contains('$argumentValues') -and
    -not $semanticPrompt.Contains($semanticCase[0].expectedOutcome) -and $semanticPrompt -notmatch '1729|7919') 'Execution interface was omitted or expected fixture values leaked into prompt.'
$discovery = New-EvaluationPrompt -Cases $subset -Mode discovery -Variant updated -Bundle $updated
Assert-Behavior ($discovery.Contains('.agents/skills/powershell-guardrails') -and -not $discovery.Contains('<candidate-skill>')) 'Discovery prompt supplied content instead of routing.'
$implicit = New-EvaluationPrompt -Cases $subset -Mode implicit -Variant updated -Bundle $updated
Assert-Behavior ($implicit.Contains($subset[0].prompt) -and $implicit -notmatch 'powershell-guardrails|SKILL.md|use_skill') 'Implicit prompt hints at candidate loading.'
$explicit = @([pscustomobject]@{ id = 'explicit'; prompt = 'Use $powershell-guardrails to review this command.' })
Assert-Behavior ((New-EvaluationPrompt -Cases $explicit -Mode implicit -Variant updated -Bundle $updated).Contains($explicit[0].prompt)) 'Explicit user mention was removed.'
$none = New-EvaluationPrompt -Cases $subset -Mode provided-content -Variant none -Bundle @()
Assert-Behavior ($none.Contains('Set use_skill to false.') -and -not $none.Contains('<candidate-skill>')) 'No-skill prompt contains candidate instructions.'
$schema = Get-ResponseSchema | ConvertFrom-Json
Assert-Behavior ($schema.properties.answers.type -eq 'array' -and 'use_skill' -in $schema.properties.answers.items.required) 'Response schema changed.'
$arguments = @(Get-CodexArguments -Model test-model -Workspace 'C:/space dir' -SchemaPath schema -AnswerPath answer -SkillConfig 'skills.config=[]')
Assert-Behavior ('read-only' -in $arguments -and 'windows.sandbox="elevated"' -in $arguments -and '--ignore-user-config' -in $arguments) 'Evaluation sandbox or isolation changed.'
Assert-Behavior ('C:/space dir' -in $arguments) 'Workspace argument was split.'
