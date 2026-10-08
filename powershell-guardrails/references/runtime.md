# Runtime Preparation

Read this only when execution needs a supported runtime that the current session
does not provide. Reviewing or proposing a Windows command needs no installation.

This skill executes repaired commands only on Windows with Core `pwsh` 7.6 or
later. Do not install or activate it on Linux/macOS, even if PowerShell is present.

## Discover an installed runtime

Use `Get-Command pwsh -CommandType Application -All` or a known installation path.
Start the supported executable by explicit path and run `scripts/check-runtime.ps1`
from this skill in that execution session. Do not use Windows PowerShell 5.1 for
repaired task commands. Discovery and authorized installation may run under 5.1.

## Install only when needed and authorized

If no supported runtime exists, report the detected version or missing executable.
Reuse installation or upgrade authorization already given in the session. If none
exists, request authorization with a concrete installation method before installing.

Follow the [official Windows installation guide](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows).
When WinGet is available, use `winget install --id Microsoft.PowerShell --source winget`
for a missing installation or `winget upgrade --id Microsoft.PowerShell --source winget`
for an older WinGet-managed installation. Otherwise use a suitable official installer
from the guide within the authorized scope.

Check installer exit status and the installed version. Installation failure or host
rejection stops this path; report required user action. Resolve the installed `pwsh`
path again because the current PATH may be stale. Start that executable and rerun
the runtime check before resuming repaired task execution.
