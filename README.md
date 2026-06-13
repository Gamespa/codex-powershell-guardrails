# PowerShell Guardrails

Reusable Codex skill for avoiding fragile Windows PowerShell command
composition.

This repository packages one skill: `powershell-guardrails`. Use it when a
Windows PowerShell or `pwsh` layer is composing commands that cross into native
executables, `cmd.exe`, SSH, remote Linux shells, inline payloads, regexes,
scripts, process cleanup, or local smoke tests.

The runtime guidance lives in `powershell-guardrails/SKILL.md`. Longer examples
and failure-mode details live in `powershell-guardrails/references/`.

## Installation

Copy the skill directory into your Codex skills directory:

```powershell
$skillsDir = Join-Path $env:USERPROFILE '.codex\skills'
New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
Copy-Item -Recurse -Force .\powershell-guardrails (Join-Path $skillsDir 'powershell-guardrails')
```

Then invoke it in Codex with:

```text
Use $powershell-guardrails
```

Agent metadata is in `powershell-guardrails/agents/openai.yaml`.

## Repository Layout

```text
powershell-guardrails/
  SKILL.md                         Main skill loaded by agents
  agents/openai.yaml               Codex-compatible display metadata
  references/pitfalls.md           Detailed symptoms and safer replacements
  references/pressure-scenarios.md Behavior checks for future edits
scripts/
  verify.ps1                       Full repository validation entrypoint
  verify-skill.ps1                 Skill structure and content checks
  verify-pressure-scenarios.ps1    Pressure scenario format checks
```

## Verification

Run the full validation chain before committing changes:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

That command runs `scripts/verify-skill.ps1`,
`scripts/verify-pressure-scenarios.ps1`, and `git diff --check`.

## Maintenance

- Keep `SKILL.md` short, actionable, and focused on decisions agents must make.
- Move long explanations, incident patterns, and extra examples into
  `references/pitfalls.md`.
- Add or update `references/pressure-scenarios.md` when a rule should change
  future agent behavior.
- Keep examples generic. Avoid machine-specific paths, hostnames, secrets, or
  project-only conventions.
- Run the full verifier after any edit, even wording-only changes.

## License

MIT. See `LICENSE`.
