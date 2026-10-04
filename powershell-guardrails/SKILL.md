---
name: powershell-guardrails
description: Prevent and fix fragile PowerShell 7.6 commands on Windows involving parser boundaries, native arguments, encoding or redirection, exit status, or process cleanup.
---

# PowerShell Guardrails

Skip routine commands without these risks and pure Bash without a PowerShell layer.
Explicit user requirements override workflow preferences; existing authorization
still applies.

## Runtime

Execute this skill's commands only on Windows with `pwsh` 7.6.x. Run
[the runtime check](scripts/check-runtime.ps1) once in the actual execution
session before applying the guidance. Stop on an unsupported runtime and report
the detected version; use an already available 7.6.x runtime if appropriate.
Do not install, upgrade, or substitute `powershell.exe` from this skill.
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
