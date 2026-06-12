# PowerShell Guardrails

Reusable Codex skill for avoiding fragile Windows PowerShell command composition.

This skill helps agents handle the boundary between Windows PowerShell, PowerShell
7, native Windows executables, `cmd.exe`, SSH, remote Linux shells, and embedded
payloads such as JSON, Python, SQL, or regexes. Its core rule is simple: identify
which shell expands each character before composing or running the command.

## When To Use

Use this skill when work is happening from Windows PowerShell or `pwsh` and the
command involves any fragile boundary, including:

- `$`, `$_`, `$()`, quotes, pipes, redirects, here-strings, or inline payloads.
- Nested `pwsh -Command`, `ForEach-Object`, `Where-Object`, `$input`, or
  scriptblocks.
- Regexes or test filters containing `|`, brackets, quotes, or backslashes.
- Windows-to-Linux SSH with `sudo`, `bash -lc`, heredocs, `xargs`, `trap`,
  command substitution, or nested quotes.
- `.ps1` execution policy, `curl` versus `curl.exe`, `rg`, `git diff`, wildcard
  handling, PATH uncertainty, or native tool resolution.
- Large generated patches, full-file rewrites, local smoke-test servers,
  process cleanup, or error messages such as `ParserError`, `An empty pipe
  element is not allowed`, or `The command line is too long`.

Do not use it for pure bash/Linux sessions unless a Windows PowerShell layer is
composing the command.

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

The OpenAI agent metadata is in `powershell-guardrails/agents/openai.yaml`.

## Repository Layout

```text
powershell-guardrails/
  SKILL.md
  agents/
    openai.yaml
  references/
    pitfalls.md
    pressure-scenarios.md
scripts/
  verify.ps1
  verify-pressure-scenarios.ps1
  verify-skill.ps1
```

- `SKILL.md` is the primary skill loaded by agents.
- `references/pitfalls.md` expands recurring symptoms, causes, and safer command
  shapes.
- `references/pressure-scenarios.md` captures prompts that should make an agent
  choose safe command shapes when this skill is loaded.
- `agents/openai.yaml` provides the display name and trigger prompt used by
  Codex-compatible agents.
- `scripts/verify-skill.ps1` runs repository quality gates for this skill.
- `scripts/verify-pressure-scenarios.ps1` verifies that each pressure scenario
  has a prompt, failing answer, failure explanation, and passing answer.
- `scripts/verify.ps1` runs the full repository validation chain.

## Core Guardrails

- Prefer `pwsh -NoProfile` when you control invocation. Do not assume
  `powershell` means PowerShell 7.
- If time is short, prioritize explicit `pwsh`, single-quoted nested payloads,
  stdin for remote bash, executable verification, and read-only target probes
  before destructive commands.
- Verify executable resolution before diagnosing behavior:
  `Get-Command <tool> | Select-Object Source,Version`.
- Keep PowerShell syntax in PowerShell. Do not paste bash heredocs or command
  substitution into a local PowerShell layer.
- Avoid nested double-quoted PowerShell payloads when they contain `$`, `$_`,
  `$input`, `$Matches`, or `$()`.
- For complex payloads, use single-quoted here-strings, a temporary script,
  stdin, structured serializers, or `apply_patch`.
- For Windows-to-Linux SSH, send a normalized script through
  `ssh <host> bash -s` instead of growing a quoted one-liner.
- For process cleanup, target a known root PID and descendants, and exclude the
  current shell and agent process tree.
- For long-running local services, separate launch, readiness probes, listener
  PID checks, and cleanup.

## Safe Patterns

Use a single-quoted here-string for embedded code:

```powershell
$code = @'
print("hello from stdin")
'@
$code | & $pythonExe -
```

Pipe remote Linux work through stdin:

```powershell
$remoteScript = @'
set -euo pipefail
cd /srv/app
docker compose ps
'@
($remoteScript -replace "`r`n", "`n") | ssh my-host bash -s
```

Bind regexes or test filters before passing them to native tools:

```powershell
$testNamePattern = 'rewrites machine text|rewrites singular text'
npm test -- --run path/to/test.spec.ts -t $testNamePattern
```

Use argument arrays when generated commands contain regexes or paths that must
stay single native arguments:

```powershell
$tool = (Get-Command rg -ErrorAction Stop).Source
$searchPattern = 'service-password|service.*password'
$args = @('--', $searchPattern, '.')
& $tool @args
```

Run scripts with an explicit execution policy when needed:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

## Maintenance

Keep the skill reusable across repositories and machines:

- Add durable rules to `SKILL.md`.
- Add concrete failure symptoms and replacements to `references/pitfalls.md`.
- Add or update pressure scenarios in `references/pressure-scenarios.md` when a
  rule is meant to change future agent behavior.
- Keep examples generic. Avoid machine-specific paths, hostnames, secrets, or
  project-only conventions.
- Prefer short, directly actionable guidance over narrative incident reports.

Before committing changes, run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

If you change only scenario wording, rerun the full verifier to keep the chain
honest.

## License

MIT. See `LICENSE`.
