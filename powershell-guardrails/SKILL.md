---
name: powershell-guardrails
description: Prevent and fix fragile PowerShell 7.6+ commands on Windows involving parser boundaries, native arguments, encoding or redirection, exit status, or process cleanup.
---

# PowerShell Guardrails

Skip routine commands without these risks and pure Bash without a PowerShell layer.
Explicit user requirements override workflow preferences; existing authorization
still applies.

## Runtime

Windows only: do not install or enable this skill on Linux or macOS.
Check the target platform before installing the skill or preparing its runtime.
If invoked on a non-Windows platform, report that it is unsupported and stop;
do not enter the PowerShell installation or upgrade flow there.

Execute repaired task commands only on Windows with `pwsh` 7.6 or later. Prefer
an already installed supported `pwsh` over Windows PowerShell 5.1; if the current
session is unsupported, locate an available `pwsh` (via `Get-Command pwsh
-CommandType Application -All` or a known installation path) and use its explicit
path to start a supported session. Run
[the runtime check](scripts/check-runtime.ps1) once in the actual execution
session before applying the guidance. If no supported runtime is available,
stop executing repaired task commands and report the detected version or missing `pwsh`.
If the user has authorized installation or upgrade, install PowerShell 7.6 or
later automatically; honor authorization already given in the session without
asking again. Otherwise, request authorization with the proposed installation
method, then perform the installation when authorized. Use the
[official Windows installation guide](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows).
When WinGet is available, run `winget install --id Microsoft.PowerShell --source winget`
for a missing installation, or `winget upgrade --id Microsoft.PowerShell --source winget`
for an older WinGet-managed installation. Otherwise, download and run a suitable
official installer from the guide within the authorized scope. Check the installer's
exit status and confirm the installed version meets the minimum; installation
failure or host rejection stops this path. Report any required user action.
Runtime discovery and authorized installation may run from Windows PowerShell 5.1;
this exception does not permit running repaired task commands there.
After installation, resolve the installed `pwsh` path again (the current PATH may
be stale), start that executable, and rerun the runtime check before resuming.
Do not substitute `powershell.exe` for the supported task runtime.
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
