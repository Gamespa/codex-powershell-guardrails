$traceRoot = Join-Path $repositoryRoot 'powershell-guardrails'
$goodEvent = @{ type = 'item.completed'; item = @{ type = 'command_execution';
command = 'Get-Content .agents/skills/powershell-guardrails/SKILL.md'; status = 'completed';
exit_code = 0; aggregated_output = 'name: powershell-guardrails' } }
$evidence = Get-SkillReadEvidence -Trace (( $goodEvent | ConvertTo-Json -Depth 6 -Compress) + "`n`n{}") -SkillRoot $traceRoot
Assert-Behavior $evidence.skillRead 'Successful skill read was not detected.'
$goodEvent.item.exit_code = 1
$evidence = Get-SkillReadEvidence -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress) -SkillRoot $traceRoot
Assert-Behavior (-not $evidence.skillRead -and $evidence.unverifiedReads.Count -eq 1) 'Failed read counted as skill loading.'
$mention = @{ type = 'item.completed'; item = @{ type = 'agent_message'; text = 'I read SKILL.md' } }
$evidence = Get-SkillReadEvidence -Trace ($mention | ConvertTo-Json -Depth 6 -Compress) -SkillRoot $traceRoot
Assert-Behavior (-not $evidence.skillRead) 'Self-report counted as skill loading.'
$referenceEvent = @{ type = 'item.completed'; item = @{ type = 'command_execution';
command = 'Get-Content .agents/skills/powershell-guardrails/references/runtime.md'; status = 'completed';
exit_code = 0; aggregated_output = '# Runtime Preparation' } }
$evidence = Get-SkillReadEvidence -Trace ($referenceEvent | ConvertTo-Json -Depth 6 -Compress) -SkillRoot $traceRoot
Assert-Behavior ($evidence.referenceReads.Count -eq 1 -and $evidence.referenceReads[0] -eq 'references/runtime.md') 'Reference read was not detected.'
