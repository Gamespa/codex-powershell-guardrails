$traceRoot = Join-Path $fixtureRoot '.agents/skills/powershell-guardrails'
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $traceRoot) -Force
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'powershell-guardrails') -Destination $traceRoot -Recurse
$goodEvent = @{ type = 'item.completed'; item = @{ type = 'command_execution';
command = 'Get-Content .agents/skills/powershell-guardrails/SKILL.md'; status = 'completed';
exit_code = 0; aggregated_output = 'name: powershell-guardrails' } }
$evidence = Get-SkillReadEvidence -Workspace $fixtureRoot -Trace (( $goodEvent | ConvertTo-Json -Depth 6 -Compress) + "`n`n{}") -SkillRoot $traceRoot
Assert-Behavior $evidence.skillRead 'Successful skill read was not detected.'
$goodEvent.item.exit_code = 1
$evidence = Get-SkillReadEvidence -Workspace $fixtureRoot -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress) -SkillRoot $traceRoot
Assert-Behavior (-not $evidence.skillRead -and $evidence.unverifiedReads.Count -eq 1) 'Failed read counted as skill loading.'
$mention = @{ type = 'item.completed'; item = @{ type = 'agent_message'; text = 'I read SKILL.md' } }
$evidence = Get-SkillReadEvidence -Trace ($mention | ConvertTo-Json -Depth 6 -Compress) -SkillRoot $traceRoot
Assert-Behavior (-not $evidence.skillRead) 'Self-report counted as skill loading.'
$referenceEvent = @{ type = 'item.completed'; item = @{ type = 'command_execution';
command = 'Get-Content .agents/skills/powershell-guardrails/references/runtime.md'; status = 'completed';
exit_code = 0; aggregated_output = '# Runtime Preparation' } }
$evidence = Get-SkillReadEvidence -Workspace $fixtureRoot -Trace ($referenceEvent | ConvertTo-Json -Depth 6 -Compress) -SkillRoot $traceRoot
Assert-Behavior ($evidence.referenceReads.Count -eq 1 -and $evidence.referenceReads[0] -eq 'references/runtime.md') 'Reference read was not detected.'

$options = @{ SkillRoot = $traceRoot; Workspace = $fixtureRoot }
$goodEvent.item.aggregated_output = 'blocked by policy'
$failedTrace = $goodEvent | ConvertTo-Json -Depth 6 -Compress
$evidence = Get-SkillReadEvidence @options -Trace $failedTrace
Assert-Behavior ($evidence.rejectedReads.Count -eq 1) 'Structured policy rejection was missed.'
$goodEvent.item.exit_code = 0
$goodEvent.item.aggregated_output = 'name: powershell-guardrails'
$goodTrace = $goodEvent | ConvertTo-Json -Depth 6 -Compress
$evidence = Get-SkillReadEvidence @options -Trace ($failedTrace + "`n" + $goodTrace)
Assert-Behavior ($evidence.skillRead -and $evidence.rejectedReads.Count -eq 1 -and $evidence.unverifiedReads.Count -eq 1) 'Later success erased a rejected read.'
foreach ($command in @(
  "Get-Content -LiteralPath '$traceRoot/SKILL.md' -Raw",
  'Get-Content .agents/skills/powershell-guardrails/../powershell-guardrails/SKILL.md',
  "Set-Location '$traceRoot'; Get-Content -Path SKILL.md",
  "pwsh -NoProfile -Command 'Get-Content .agents/skills/powershell-guardrails/SKILL.md'"
)) {
  $goodEvent.item.command = $command
  $evidence = Get-SkillReadEvidence @options -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
  Assert-Behavior $evidence.skillRead "Literal read was not resolved: $command"
}
foreach ($command in @(
  'Get-Content C:/unrelated/SKILL.md', 'Get-Content unrelated/SKILL.md',
  'Get-Content .agents/skills/powershell-guardrails-copy/SKILL.md',
  "Write-Output 'Get-Content .agents/skills/powershell-guardrails/SKILL.md'",
  'Get-Content .agents/skills/powershell-guardrails/SKILL.md.backup'
)) {
  $goodEvent.item.command = $command
  $evidence = Get-SkillReadEvidence @options -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
  Assert-Behavior (-not $evidence.skillRead -and $evidence.unverifiedReads.Count -eq 0) "Unrelated path or mention counted as candidate read: $command"
}
foreach ($command in @('Get-Content $candidate', 'Get-Content *.md', 'if ($false) { Get-Content SKILL.md }')) {
  $goodEvent.item.command = $command
  $evidence = Get-SkillReadEvidence @options -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
  Assert-Behavior (-not $evidence.skillRead -and $evidence.unresolvedReads.Count -gt 0) 'Dynamic or conditional read was guessed.'
}
$goodEvent.item.command = 'Get-Content SKILL.md'
$goodEvent.item.cwd = $traceRoot
$evidence = Get-SkillReadEvidence @options -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
Assert-Behavior $evidence.skillRead 'Explicit event working directory was ignored.'
$goodEvent.item.Remove('cwd')
$evidence = Get-SkillReadEvidence -SkillRoot $traceRoot -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
Assert-Behavior (-not $evidence.skillRead -and $evidence.unresolvedReads.Count -eq 1) 'Relative path without a working directory was guessed.'
$tracePath = Write-Fixture 'trace.jsonl' $goodTrace
$evidence = Get-SkillReadEvidence @options -TracePath $tracePath
Assert-Behavior $evidence.skillRead 'File-backed trace analysis changed evidence.'

$goodEvent.item.command = 'Get-Content .agents/skills/powershell-guardrails/scripts/check-runtime.ps1'
$goodEvent.item.exit_code = 1
$goodEvent.item.aggregated_output = 'blocked by policy'
$evidence = Get-SkillReadEvidence @options -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
Assert-Behavior ('scripts/check-runtime.ps1' -in $evidence.rejectedReads) 'Rejected candidate helper read was ignored.'
$goodEvent.item.exit_code = 0
$goodEvent.item.aggregated_output = 'function Assert-GuardrailsRuntime {'
$evidence = Get-SkillReadEvidence @options -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
Assert-Behavior (-not $evidence.skillRead -and $evidence.unverifiedReads.Count -eq 0) 'Helper source was confused with entrypoint loading.'
