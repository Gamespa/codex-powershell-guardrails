# PowerShell Pitfalls Reference

This reference lists recurring Windows PowerShell failure modes and safe replacements. Keep examples generic so the skill remains reusable across machines and repositories.

## 1. Default `powershell` Is Often Windows PowerShell 5.1

Symptoms:

- `The token '&&' is not a valid statement separator in this version.`
- Commands behave differently than a PowerShell 7 example.

Safer pattern:

```powershell
pwsh -NoProfile -Command '$PSVersionTable.PSVersion'
```

Use `pwsh` explicitly when you need PowerShell 7 behavior. Use `powershell` only when you intentionally need Windows PowerShell.

## 2. Bash Syntax In PowerShell

Symptoms:

- `Missing file specification after redirection operator`
- `The token '&&' is not a valid statement separator`
- `ParserError`

Common causes:

- `python - <<'PY'` copied from bash.
- `cmd1 && cmd2` sent to Windows PowerShell 5.1.
- Bash `$()` command substitution used in a local PowerShell layer.

Safer pattern:

```powershell
$script = @'
echo "portable payload"
'@
$script | ssh my-host bash -s
```

## 3. Empty Pipe From Premature Variable Expansion

Symptoms:

- `An empty pipe element is not allowed.`
- The error points to a line beginning with `|`.

Common cause:

```powershell
git show HEAD:file.txt | powershell -NoProfile -Command "$input | Set-Content out.txt"
```

The outer PowerShell can expand `$input` before the nested shell receives it.

Safer patterns:

```powershell
git show HEAD:file.txt | pwsh -NoProfile -Command '$input | Set-Content out.txt'
```

or avoid nested PowerShell and write to a file directly from the outer command.

## 4. Windows To Remote Linux Quoting

Symptoms:

- Remote command receives missing variables.
- `$(...)`, `$VAR`, quotes, or heredocs behave differently than expected.
- Inline `ssh "..."` keeps growing quote layers.

Safer pattern:

```powershell
$remote = @'
set -euo pipefail
user="$(id -un)"
printf 'user=%s\n' "$user"
'@
$remote | ssh my-host bash -s
```

Switch to this pattern when remote commands include `$(...)`, heredocs, `xargs`, `sudo -u`, embedded JSON/Python/SQL, or nested quotes.

## 5. PATH Or Packaged Tool Resolution

Symptoms:

- `Program 'rg.exe' failed to run: Access is denied`
- A tool works in one terminal but not inside the agent.
- The command resolves to a packaged app or WindowsApps location.

Safer pattern:

```powershell
Get-Command rg | Select-Object Source,Version
where.exe rg
rg --version
```

Install tools in a normal user or system directory and ensure that directory precedes packaged app shims in PATH.

## 6. Long Command Strings And Large Patches

Symptoms:

- `The command line is too long.`
- Large inline patches fail before the target tool starts.

Safer patterns:

- Prefer small `apply_patch` hunks.
- Split changes by file and by behavior.
- Put large generated content into a temporary script or file, then invoke it with a short command.

```powershell
pwsh -NoProfile -File .\apply-large-change.ps1
```

## 7. Script Execution Policy

Symptoms:

- `cannot be loaded because running scripts is disabled on this system`
- `PSSecurityException`
- Functions are missing because a dot-sourced script failed to load.

Safer pattern:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1
```

Use process-scoped policy for the command instead of asking the user to weaken the machine policy.

## 8. Reserved And Automatic Variables

Symptoms:

- `Cannot overwrite variable Host because it is read-only or constant.`
- A collection becomes a regex match table after `-match`.
- Unexpected values appear in `$input`, `$error`, `$matches`, or `$host`.

Avoid using these names for ordinary variables:

- `$Host` / `$host`
- `$Matches` / `$matches`
- `$Input` / `$input`
- `$Error` / `$error`

Use specific names such as `$hostName`, `$hostPath`, `$matchRecords`, or `$inputText`.

## 9. `curl`, `curl.exe`, `Invoke-WebRequest`, And Schannel

Symptoms:

- `curl: (35) schannel: next InitializeSecurityContext failed`
- `CRYPT_E_REVOCATION_OFFLINE`
- `Invoke-WebRequest -Method Head` disagrees with another probe.

Safer patterns:

- Use `curl.exe` when you need the native curl binary.
- Use `Invoke-WebRequest` when you intentionally want the PowerShell cmdlet.
- Cross-check suspicious HTTPS failures from Windows with a remote Linux probe, browser, or service logs before declaring the service down.

## 10. Missing Bash Or WSL

Symptoms:

- `/bin/bash` is not available from the Windows environment.
- A bash wrapper fails although the underlying validation is just file/text checks.

Safer pattern:

- Confirm `bash` availability before relying on bash scripts.
- If the script only checks files or text, reproduce the same assertions in PowerShell.
- Do not report a project failure when only the shell wrapper is unavailable.

## 11. Unsafe Process Cleanup

Symptoms:

- Cleanup kills the active shell or agent.
- `Stop-Process -Force` is used with broad `CommandLine -like` filters.

Safer pattern:

- Save the root PID when starting a local service stack.
- Enumerate only descendants of that PID.
- Exclude the current PowerShell process, the agent process, and their parent chain.
- Stop specific descendants, not every process matching a project name.

## 12. Wildcards And Pathspecs

Symptoms:

- `git diff`, `rg`, or another native tool receives different paths than expected.
- PowerShell expands a wildcard before the target tool can apply its own glob rules.

Safer patterns:

- Prefer explicit paths for small sets.
- Use the target tool's own glob/pathspec options when possible.
- Quote arguments intentionally and verify with a read-only command before destructive operations.

## 13. OpenSSH Argument Parsing From PowerShell

Symptoms:

- An OpenSSH command says an option requires an argument even though an empty argument was supplied.
- PowerShell rewrites quotes around flags such as `-N ""`.

Safer pattern:

```powershell
ssh-keygen --% -q -t ed25519 -f C:\path\to\key -C "comment" -N ""
```

Use PowerShell stop-parsing `--%` only for native Windows commands where passing the rest verbatim is the goal. Do not use it for commands that need PowerShell variable expansion after that point.
