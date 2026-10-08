---
name: powershell-guardrails
description: Repair fragile Windows PowerShell commands involving parser boundaries, native arguments, encoding, exit status, or cleanup. Skip routine commands without these risks and pure Bash.
---

# PowerShell Guardrails

Skip routine commands without these risks and pure Bash without a PowerShell layer.
Explicit user requirements override workflow preferences; existing authorization
still applies.

## Runtime

Windows only: do not install or enable this skill on Linux or macOS.
Analysis and proposed repairs do not require a local runtime check or installation.
Before executing repaired task commands, use Windows with `pwsh` 7.6 or later and run
[the runtime check](scripts/check-runtime.ps1) once in the actual execution session.
Prefer an already installed supported runtime. If unavailable, stop task execution
and read [runtime preparation](references/runtime.md); reuse existing installation
authorization. Do not substitute `powershell.exe` for the supported task runtime.
Check the target OS before installation or activation; on Linux/macOS report the
unsupported platform and stop without installing the skill or PowerShell.
For child PowerShell, use `Join-Path $PSHOME 'pwsh.exe'` to keep the checked
installation. Recheck when switching to a different execution environment.

## Boundary Constraints

- **Expansion:** Keep child and remote variables in their owning parser.
  Prefer literal payloads or script files over nested escaping, and avoid
  introducing a child shell when the current shell can do the work.
- **Arguments:** Native quoting depends on the target executable and
  `$PSNativeCommandArgumentPassing`, not just argument arrays.
- **Status:** Unexpected cmdlet errors must terminate validation. Capture
  `$LASTEXITCODE` immediately for native tools; `rg` uses 0 for matches,
  1 for no matches, and 2 for errors.
- **Encoding:** Follow the consumer's encoding and newline contract. Text stdin,
  exact bytes, and file output are separate boundaries; strings piped to native
  stdin can append a platform newline.
- **Secrets:** Keep values out of argv and raw tool output. Filter sensitive
  matches inside the producing process; `rg --json` includes matching text.
- **Targets:** Inspect exact destructive targets and verify containment.
  Keep enumeration and action in one shell with literal paths where supported.
  Verify process identity beyond PID, and protect the shell, agent, and ancestors.
- **Jobs:** Poll an existing host session when its lifetime is sufficient.
  After timeout or broken pipe, inspect the prior job and its outputs before
  relaunching; cleanup targets only verified processes.
- **Policy:** Do not retry a host-rejected operation through equivalent
  syntax, another shell, or another API.

## References

Read only the reference for the affected boundary:

- [Arguments and expansion](references/arguments-and-expansion.md): native
  argument modes, batch environments, nested variables, interpolation, and
  statement pipelines.
- [SSH and encoding](references/ssh-and-encoding.md): remote expansion,
  exact stdin bytes, redirection, LF/BOM, append encoding, and shared stdin.
- [Execution and lifecycle](references/execution-and-lifecycle.md): exit
  status and preferences, structured output, credential metadata, process identity,
  cleanup, and Windows-specific diagnostics.
