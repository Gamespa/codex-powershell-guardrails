$traceRoot = Join-Path $fixtureRoot '.agents/skills/powershell-guardrails'
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $traceRoot) -Force
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'powershell-guardrails') -Destination $traceRoot -Recurse
$goodEvent = @{ type = 'item.completed'; item = @{ type = 'command_execution';
command = 'Get-Content .agents/skills/powershell-guardrails/SKILL.md'; status = 'completed';
exit_code = 0; aggregated_output = [IO.File]::ReadAllText((Join-Path $traceRoot 'SKILL.md')) } }
$evidence = Get-SkillReadEvidence -Workspace $fixtureRoot -Trace (( $goodEvent | ConvertTo-Json -Depth 6 -Compress) + "`n`n{}") -SkillRoot $traceRoot
Assert-Behavior $evidence.entrypoint.verifiedRead 'Successful skill read was not detected.'
$goodEvent.item.exit_code = 1
$evidence = Get-SkillReadEvidence -Workspace $fixtureRoot -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress) -SkillRoot $traceRoot
Assert-Behavior (-not $evidence.entrypoint.verifiedRead -and $evidence.unverifiedReads.Count -eq 1) 'Failed read counted as skill loading.'
$mention = @{ type = 'item.completed'; item = @{ type = 'agent_message'; text = 'I read SKILL.md' } }
$evidence = Get-SkillReadEvidence -Trace ($mention | ConvertTo-Json -Depth 6 -Compress) -SkillRoot $traceRoot
Assert-Behavior (-not $evidence.entrypoint.verifiedRead) 'Self-report counted as skill loading.'
$referenceEvent = @{ type = 'item.completed'; item = @{ type = 'command_execution';
command = 'Get-Content .agents/skills/powershell-guardrails/references/runtime.md -Head 1'; status = 'completed';
exit_code = 0; aggregated_output = '# Runtime Preparation' } }
$evidence = Get-SkillReadEvidence -Workspace $fixtureRoot -Trace ($referenceEvent | ConvertTo-Json -Depth 6 -Compress) -SkillRoot $traceRoot
Assert-Behavior (@($evidence.fileReads | Where-Object { $_.path -eq 'references/runtime.md' -and $_.level -eq 'partial-body' }).Count -eq 1) 'Reference read was not detected.'

$options = @{ SkillRoot = $traceRoot; Workspace = $fixtureRoot }
$goodEvent.item.aggregated_output = 'blocked by policy'
$failedTrace = $goodEvent | ConvertTo-Json -Depth 6 -Compress
$evidence = Get-SkillReadEvidence @options -Trace $failedTrace
Assert-Behavior ($evidence.rejectedReads.Count -eq 1) 'Structured policy rejection was missed.'
$goodEvent.item.exit_code = 0
$goodEvent.item.aggregated_output = [IO.File]::ReadAllText((Join-Path $traceRoot 'SKILL.md'))
$goodTrace = $goodEvent | ConvertTo-Json -Depth 6 -Compress
$evidence = Get-SkillReadEvidence @options -Trace ($failedTrace + "`n" + $goodTrace)
Assert-Behavior ($evidence.entrypoint.verifiedRead -and $evidence.rejectedReads.Count -eq 1 -and $evidence.unverifiedReads.Count -eq 1) 'Later success erased a rejected read.'
foreach ($command in @(
  "Get-Content -LiteralPath '$traceRoot/SKILL.md' -Raw",
  'Get-Content .agents/skills/powershell-guardrails/../powershell-guardrails/SKILL.md',
  "Set-Location '$traceRoot'; Get-Content -Path SKILL.md",
  "pwsh -NoProfile -Command 'Get-Content .agents/skills/powershell-guardrails/SKILL.md'"
)) {
  $goodEvent.item.command = $command
  $evidence = Get-SkillReadEvidence @options -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
  Assert-Behavior $evidence.entrypoint.verifiedRead "Literal read was not resolved: $command"
}
foreach ($command in @(
  'Get-Content C:/unrelated/SKILL.md', 'Get-Content unrelated/SKILL.md',
  'Get-Content .agents/skills/powershell-guardrails-copy/SKILL.md',
  "Write-Output 'Get-Content .agents/skills/powershell-guardrails/SKILL.md'",
  'Get-Content .agents/skills/powershell-guardrails/SKILL.md.backup'
)) {
  $goodEvent.item.command = $command
  $evidence = Get-SkillReadEvidence @options -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
  Assert-Behavior (-not $evidence.entrypoint.verifiedRead -and $evidence.unverifiedReads.Count -eq 0) "Unrelated path or mention counted as candidate read: $command"
}
foreach ($command in @('Get-Content $candidate', 'Get-Content *.md', 'if ($false) { Get-Content SKILL.md }')) {
  $goodEvent.item.command = $command
  $evidence = Get-SkillReadEvidence @options -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
  Assert-Behavior (-not $evidence.entrypoint.verifiedRead -and $evidence.unresolvedReads.Count -gt 0) 'Dynamic or conditional read was guessed.'
}
$goodEvent.item.command = 'Get-Content SKILL.md'
$goodEvent.item.cwd = $traceRoot
$evidence = Get-SkillReadEvidence @options -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
Assert-Behavior $evidence.entrypoint.verifiedRead 'Explicit event working directory was ignored.'
$goodEvent.item.Remove('cwd')
$evidence = Get-SkillReadEvidence -SkillRoot $traceRoot -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
Assert-Behavior (-not $evidence.entrypoint.verifiedRead -and $evidence.unresolvedReads.Count -eq 1) 'Relative path without a working directory was guessed.'
$tracePath = Write-Fixture 'trace.jsonl' $goodTrace
$evidence = Get-SkillReadEvidence @options -TracePath $tracePath
Assert-Behavior $evidence.entrypoint.verifiedRead 'File-backed trace analysis changed evidence.'

$goodEvent.item.command = 'Get-Content .agents/skills/powershell-guardrails/scripts/check-runtime.ps1'
$goodEvent.item.exit_code = 1
$goodEvent.item.aggregated_output = 'blocked by policy'
$evidence = Get-SkillReadEvidence @options -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
Assert-Behavior ('scripts/check-runtime.ps1' -in $evidence.rejectedReads) 'Rejected candidate helper read was ignored.'
$goodEvent.item.exit_code = 0
$goodEvent.item.command += ' -Head 1'
$goodEvent.item.aggregated_output = 'function Assert-GuardrailsRuntime {'
$evidence = Get-SkillReadEvidence @options -Trace ($goodEvent | ConvertTo-Json -Depth 6 -Compress)
Assert-Behavior (-not $evidence.entrypoint.verifiedRead -and $evidence.unverifiedReads.Count -eq 0) 'Helper source was confused with entrypoint loading.'

# Use a small manifest so coverage and disjoint ranges have exact expectations.
$manifest = "---`nname: powershell-guardrails`ndescription: fixture`n---`n# Instructions`nKeep Case and spaces.`nLast instruction.`n"
[IO.File]::WriteAllText((Join-Path $traceRoot 'SKILL.md'), $manifest)
$readCommand = 'Get-Content .agents/skills/powershell-guardrails/SKILL.md'
function New-ReadTrace {
  param([string]$Command, [string]$Output)
  @{ type = 'item.completed'; item = @{ type = 'command_execution'; command = $Command
    status = 'completed'; exit_code = 0; aggregated_output = $Output } } | ConvertTo-Json -Depth 6 -Compress
}
$headTrace = New-ReadTrace "$readCommand -TotalCount 2" "---`nname: powershell-guardrails"
$evidence = Get-SkillReadEvidence @options -Trace (New-ReadTrace "$readCommand -Head 1" '---')
Assert-Behavior ($evidence.entrypoint.level -eq 'metadata-only' -and $evidence.entrypoint.bodyCoverage.coveredLines -eq 0) 'Frontmatter delimiter was mistaken for body or unverified content.'
$evidence = Get-SkillReadEvidence @options -Trace $headTrace
Assert-Behavior ($evidence.entrypoint.level -eq 'metadata-only' -and $evidence.entrypoint.bodyCoverage.coveredLines -eq 0) 'Metadata became body evidence.'
$partialTrace = New-ReadTrace "$readCommand -Head:5" "---`nname: powershell-guardrails`ndescription: fixture`n---`n# Instructions"
$evidence = Get-SkillReadEvidence @options -Trace $partialTrace
Assert-Behavior ($evidence.entrypoint.level -eq 'partial-body' -and $evidence.entrypoint.bodyCoverage.coveredLines -eq 1 -and $evidence.entrypoint.bodyCoverage.totalLines -eq 3) 'Head range coverage is incorrect.'
$tailTrace = New-ReadTrace "$readCommand -Tail 2" "Keep Case and spaces.`nLast instruction."
$evidence = Get-SkillReadEvidence @options -Trace ($partialTrace + "`n" + $tailTrace + "`n" + $tailTrace)
Assert-Behavior ($evidence.entrypoint.level -eq 'full-body' -and $evidence.entrypoint.bodyCoverage.fraction -eq 1 -and $evidence.entrypoint.attempts.Count -eq 3) 'Disjoint reads did not accumulate or repeated reads inflated coverage.'
Assert-Behavior ($evidence.entrypoint.attempts[1].startLine -eq 6 -and $evidence.entrypoint.attempts[1].endLine -eq 7) 'Tail range provenance was lost.'
foreach ($output in @($manifest, $manifest.Replace("`n", "`r`n"), ($manifest + "`n"))) {
  $evidence = Get-SkillReadEvidence @options -Trace (New-ReadTrace "$readCommand -Raw -Encoding UTF8" $output)
  Assert-Behavior ($evidence.entrypoint.level -eq 'full-body') 'Full body or normalized line endings were rejected.'
}
foreach ($output in @('name: powershell-guardrails', "---`nname: powershell-guardrails", $manifest.Replace('Case', 'case'),
    $manifest.Replace('Case and', 'Case  and'), $manifest.Replace("Keep Case and spaces.`n", ''), ($manifest + 'extra output'))) {
  $evidence = Get-SkillReadEvidence @options -Trace (New-ReadTrace $readCommand $output)
  Assert-Behavior ($evidence.entrypoint.level -eq 'unverified' -and $evidence.entrypoint.bodyCoverage.coveredLines -eq 0) 'Truncated, altered or contaminated output counted as loading.'
}
foreach ($command in @(
    "$readCommand; Write-Output 'name: powershell-guardrails'",
    "$readCommand | Select-Object -First 2",
    "$readCommand > copy.txt",
    "$readCommand, .agents/skills/powershell-guardrails/references/runtime.md",
    "$readCommand; Get-Content .agents/skills/powershell-guardrails/references/runtime.md",
    "$readCommand -Delimiter x", "$readCommand -TotalCount 0", "$readCommand -Tail `$count")) {
  $evidence = Get-SkillReadEvidence @options -Trace (New-ReadTrace $command $manifest)
  Assert-Behavior (-not $evidence.entrypoint.verifiedRead -and ($evidence.unresolvedReads.Count -gt 0 -or $evidence.unverifiedReads.Count -gt 0)) "Ambiguous command counted as loading: $command"
}
# Equal headings in different files must not authenticate mixed output.
foreach ($name in @('one.md', 'two.md')) {
  [IO.File]::WriteAllText((Join-Path $traceRoot "references/$name"), "# Shared`n$name content")
}
$mixed = 'Get-Content .agents/skills/powershell-guardrails/references/one.md, .agents/skills/powershell-guardrails/references/two.md -Head 1'
$evidence = Get-SkillReadEvidence @options -Trace (New-ReadTrace $mixed '# Shared')
Assert-Behavior (@($evidence.fileReads | Where-Object verifiedRead).Count -eq 0 -and $evidence.unverifiedReads.Count -eq 2) 'Shared output was attributed to multiple files.'
$badTrace = New-ReadTrace $readCommand 'truncated'
$evidence = Get-SkillReadEvidence @options -Trace ($badTrace + "`n" + (New-ReadTrace $readCommand $manifest))
Assert-Behavior ($evidence.entrypoint.level -eq 'full-body' -and $evidence.unverifiedReads.Count -eq 1 -and -not $evidence.entrypoint.attempts[0].verified) 'Later coverage erased earlier uncertainty.'
