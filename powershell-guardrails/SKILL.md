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

- [Arguments and expansion](references/arguments-and-expansion.md): nested parsers,
  native quoting modes, batch setup, interpolation, and statement syntax.
- [SSH payloads](references/ssh-payloads.md): remote expansion, script transport,
  and shared stdin.
- [Encoding and redirection](references/encoding-and-redirection.md): byte,
  encoding, and newline contracts for stdin, files, and binary output.
- [Command outcomes and structured output](references/command-outcomes.md):
  terminating errors, native exit codes, search outcomes, and JSON structure.
- [Sensitive data](references/sensitive-data.md): credentials and sanitizing
  search output before it crosses the tool boundary.
- [Jobs and cleanup](references/jobs-and-cleanup.md): session polling, timeouts,
  readiness, process identity, and verified filesystem cleanup.
- [Windows diagnostics](references/windows-diagnostics.md): executable resolution,
  execution policy, host rejections, Windows sandbox configuration, and Schannel.
