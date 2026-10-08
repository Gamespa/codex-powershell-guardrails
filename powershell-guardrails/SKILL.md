---
name: powershell-guardrails
description: Repair fragile Windows PowerShell commands involving parser boundaries, native arguments, encoding, exit status, or cleanup. Skip routine commands without these risks and pure Bash.
---

# PowerShell Guardrails

Explicit user requirements override workflow preferences; existing authorization
still applies.

## Runtime

Windows only: check the target OS before installation or activation; on Linux/macOS
stop without installing the skill or PowerShell. Analysis needs no runtime check.
Before repaired task execution, run [the runtime check](scripts/check-runtime.ps1)
once in the actual Windows/Core `pwsh` 7.6+ session. Prefer an installed supported
runtime; otherwise stop execution and read [runtime preparation](references/runtime.md),
reusing existing installation authorization. Do not substitute `powershell.exe`.
Use `Join-Path $PSHOME 'pwsh.exe'` for children; recheck when changing environments.

## Boundaries and References

Before repairing a command, read the references for its affected boundaries;
the summaries below do not replace them. Skip unrelated references.

- [Arguments and expansion](references/arguments-and-expansion.md): keep variables
  in their owning parser; prefer literal payloads/files and the current shell.
  Native quoting depends on the executable and `$PSNativeCommandArgumentPassing`,
  not just arrays. Covers batch environments and PowerShell expression pitfalls.
- [SSH payloads](references/ssh-payloads.md): preserve remote expansion and exact
  script bytes; account for shared stdin.
- [Encoding and redirection](references/encoding-and-redirection.md): follow the
  consumer's byte, encoding, and newline contract. Native text stdin can append a
  platform newline; file output is a separate boundary.
- [Command outcomes and structured output](references/command-outcomes.md):
  terminate unexpected cmdlet errors; capture native `$LASTEXITCODE` immediately.
  `rg`: 0 matches, 1 no matches, 2 error. Preserve objects until serialization.
- [Sensitive data](references/sensitive-data.md): keep secrets out of argv and
  raw tool output; filter matches inside the producing process, including `rg --json`.
- [Jobs and cleanup](references/jobs-and-cleanup.md): poll existing sessions;
  inspect prior jobs/outputs before retrying timeouts or broken pipes. Inspect exact
  destructive targets and containment in one shell with literal paths. Verify
  process identity beyond PID; protect the shell, agent, and ancestors.
- [Windows diagnostics](references/windows-diagnostics.md): read for resolution,
  execution-policy, host-rejection, or Schannel failures. Never retry a host-rejected
  operation through equivalent syntax, another shell, or another API.
