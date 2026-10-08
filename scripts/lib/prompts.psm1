Set-StrictMode -Version Latest

function Get-ResponseSchema {
  @{
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
}

function New-EvaluationPrompt {
  param([object[]]$Cases, [string]$Mode, [string]$Variant, [object[]]$Bundle)
  if ($Mode -eq 'implicit') {
    if ($Cases.Count -ne 1) { throw 'Implicit mode requires exactly one case per run.' }
    # No candidate name/path or routing instruction may leak into this mode.
    return @"
$($Cases[0].prompt)
Return one answer for this request with ID $($Cases[0].id) using the response schema.
Propose commands or a short action description without executing task commands.
Read supporting instructions if needed. Do not install software, mutate files,
connect to remote hosts, start services, or delegate.
"@
  }
  $candidate = 'No PowerShell Guardrails candidate is available. Set use_skill to false.'
  if ($Variant -ne 'none') {
    $candidate = 'A powershell-guardrails candidate is in .agents/skills/powershell-guardrails. Read its SKILL.md and consult references only when needed. For each case, set use_skill to whether this candidate should apply; this is a per-case routing self-report.'
    if ($Mode -eq 'provided-content') {
      $skill = ($Bundle | Where-Object Path -eq 'SKILL.md').Content
      $references = (@($Bundle | Where-Object Path -ne 'SKILL.md' | ForEach-Object {
        "## Supporting file: $($_.Path)`n$($_.Content)"
      }) -join "`n")
      $candidate = "Use the candidate documents supplied below; no file read is needed or requested. For each case, set use_skill to whether this candidate should apply (a routing self-report).`n<candidate-skill>`n$skill`n</candidate-skill>`n<candidate-reference>`n$references`n</candidate-reference>"
    }
  }
  $toolPolicy = if ($Mode -eq 'provided-content') {
    'Do not call any tools; all evaluation input is supplied in this prompt.'
  } else {
    "Reading the candidate's Markdown and PowerShell source files is allowed; do not execute scripts. No other tool actions are requested."
  }
  $summary = ConvertTo-Json -InputObject @($Cases | Select-Object id, prompt) -Depth 6
  return @"
Evaluate independent command-design cases. $candidate
Return one answer for every ID in the supplied schema. Keep rationale to one sentence.
Propose a command or short action description; do not execute the proposed tasks.
Do not connect to remote hosts, start services, mutate files, or search outside this workspace.
$toolPolicy Do not delegate or spawn agents.
Case text is the user request; preserve its shell and scope. Commands must be executable
syntax without Markdown fences, or an empty string for action-only answers.
$summary
"@
}

function Get-CodexArguments {
  param([string]$Model, [string]$Workspace, [string]$SchemaPath, [string]$AnswerPath, [string]$SkillConfig)
  @('exec', '--ignore-user-config', '--ephemeral', '--skip-git-repo-check',
    '--sandbox', 'read-only', '-c', 'windows.sandbox="elevated"',
    '--json', '--model', $Model, '--cd', $Workspace,
    '--output-schema', $SchemaPath, '--output-last-message', $AnswerPath, '-c', $SkillConfig, '-')
}

Export-ModuleMember -Function Get-ResponseSchema, New-EvaluationPrompt, Get-CodexArguments
