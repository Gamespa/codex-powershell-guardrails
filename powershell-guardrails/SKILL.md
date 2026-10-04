---
name: powershell-guardrails
description: Resolve fragile PowerShell commands that cross shell/parser boundaries, pass complex native arguments, or fail with quoting, encoding, exit-status, or process-lifecycle errors. Skip ordinary single-shell commands and pure Bash work.
---

# PowerShell Guardrails

Keep values intact across PowerShell, native Windows tools, `cmd.exe`, SSH,
and embedded languages. Apply the relevant constraint below; do not turn a
simple command into a diagnostic itinerary.

## Scope

Use for nested shell payloads, ambiguous native argument handling, Unix-bound
text, misleading command outcomes, and uncertain job or cleanup state.
Ordinary `rg`, `git status`, `.ps1` execution, and file inventories do not need
this skill unless one of those boundaries is involved.

Explicit user requirements take precedence over this skill's workflow
preferences. Existing authorization still applies; a read-only target check
does not imply another permission request.

## Core Constraints

- **Expansion:** Work out which parser owns variables and quoting when the
  boundary is uncertain. Avoid an unnecessary child shell. For complex child
  or remote code, prefer a literal payload, script file, or structured API over
  repeated escaping. Explain parser layers only when that helps the user.
- **Version:** Distinguish Windows PowerShell 5.1 from PowerShell 7 when the
  distinction affects the command. PowerShell 7 supports `&&` and `||`.
  Native argument behavior also depends on version and
  `$PSNativeCommandArgumentPassing`; an argument array is not a universal fix.
- **Outcomes:** In probes and validation, make unexpected cmdlet errors
  terminating. Capture a native command's `$LASTEXITCODE` immediately and
  interpret its contract: `rg` uses 0 for matches, 1 for no matches, and 2 for
  errors. Check expected artifacts rather than trusting a completion message.
- **Text and secrets:** Serialize structured data. For Unix-bound scripts,
  control LF line endings and UTF-8 without a BOM; file encoding and native
  stdin encoding are separate. Keep secrets out of arguments and raw output;
  sanitize inside the producing process before data reaches tool logs.
- **Targets:** Before destructive filesystem or process actions, inspect exact
  targets and verify they belong to the requested scope. Keep enumeration and
  action in one shell, use `-LiteralPath` where supported, and protect the
  current shell, agent, and their ancestors. A saved PID alone is not identity.
- **Jobs:** Use the host's persistent execution session when it meets the job's
  lifetime needs. Detach only when necessary. After a timeout or broken pipe,
  inspect existing job state, logs, and outputs before retrying; cleanup must
  target the verified process or job.
- **Policy:** Respect host execution policy; do not retry a rejected operation
  through equivalent syntax, another shell, or another API.

## Read Only the Relevant Reference

Use [pitfalls.md](references/pitfalls.md) for a specific boundary:

| Situation | Section / search term |
| --- | --- |
| Version, empty arguments, embedded quotes, `.cmd`/`.bat` | `Versions and native arguments` |
| Nested `$`, `$_`, `$()`, `${name}:`, statement pipelines | `Expansion and embedded payloads` |
| SSH, remote `$()`, Unicode, CRLF, BOM, stdin | `SSH and Unix-bound text` |
| `rg` no matches, nonterminating errors, JSON parsing | `Command outcomes` |
| API tokens, credential searches, secret transport | `Sensitive data` |
| Sessions, readiness, PID identity, `EPIPE`, remote builds | `Jobs and cleanup` |
| `Access is denied`, PATH, Schannel, execution policy | `Conditional diagnostics` |

Resolve tool paths and inspect versions when there is evidence of wrong
resolution or incompatible behavior, rather than before every native command.

## Small Examples

Preserve a remote script literally; check the SSH native status afterward.
This text pipeline assumes PowerShell 7's UTF-8 native stdin setting. See the
SSH reference for Windows PowerShell 5.1 or byte-exact payloads.

```powershell
$remoteScript = @'
set -euo pipefail
printf 'user=%s\n' "$(id -un)"
'@
($remoteScript -replace "`r`n", "`n") | ssh my-host bash -s
if ($LASTEXITCODE -ne 0) { throw 'Remote script failed' }
```

Handle a native search's three outcomes without inventing a nested shell:

```powershell
rg -l -- 'optional-feature' .
$searchExit = $LASTEXITCODE
switch ($searchExit) {
  0 { 'matches-found' }
  1 { 'no-matches' }
  default { throw "rg failed with exit code $searchExit" }
}
```

## Maintaining This Skill

Use [pressure-scenarios.md](references/pressure-scenarios.md) when changing a
decision boundary. Repository maintainers can run `scripts/verify.ps1` for
structural checks and executable regressions. Model comparisons are a separate
evaluation; passing the repository verifier does not prove model behavior.
