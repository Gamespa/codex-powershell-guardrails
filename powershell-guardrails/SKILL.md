---
name: powershell-guardrails
description: Use when running or composing commands in Windows PowerShell or pwsh, especially with native tools, nested quoting, SSH to Linux, long payloads, scripts, process cleanup, PATH/tool resolution, or errors like ParserError, Access is denied, command line is too long, or running scripts is disabled.
---

# PowerShell Guardrails

## Overview

Windows PowerShell, PowerShell 7, native Windows executables, `cmd.exe`, and remote Linux shells all parse commands differently. Use this skill to choose command shapes that make the shell boundary explicit before running fragile commands.

Core rule: identify which shell expands each character before composing the command.

## When To Use

Use this skill when the active shell is Windows PowerShell or `pwsh` and the task involves any of these:

- `$`, `$_`, `$()`, quotes, pipes, `&&`, `||`, redirects, here-docs, or inline JSON/Python/SQL.
- `ssh` from Windows to Linux, especially with `sudo -u`, `xargs`, `printf`, heredocs, or nested quotes.
- `.ps1` scripts, execution-policy errors, `curl`/`Invoke-WebRequest`, `rg`, `git diff`, wildcard arguments, or PATH/tool-resolution uncertainty.
- Large command payloads, generated patches, full-file rewrites, or long inline scripts.
- Process cleanup with `Stop-Process`, `Get-CimInstance Win32_Process`, or broad command-line matching.
- Errors such as `ParserError`, `An empty pipe element is not allowed`, `The token '&&' is not a valid statement separator`, `Missing file specification after redirection operator`, `Program 'rg.exe' failed to run: Access is denied`, `The command line is too long`, or `running scripts is disabled`.

Do not use this skill for pure bash/Linux sessions unless a Windows PowerShell layer is composing the command.

## Decision Checklist

Before running a fragile command:

1. Name every shell layer: PowerShell, native executable, `cmd.exe`, `ssh`, remote `bash`, Python, SQL, or JSON parser.
2. Prefer `pwsh -NoProfile` when you control invocation. Do not assume `powershell` means PowerShell 7.
3. Verify executables before diagnosing behavior: `Get-Command <tool> | Select-Object Source,Version`.
4. Keep PowerShell syntax in PowerShell. Do not paste bash heredocs, `&&`, `||`, or command substitutions into PowerShell and hope they survive.
5. If the command contains complex payloads, stop building a one-liner. Use a here-string, a temporary script, stdin, or a file.
6. For Windows-to-Linux remote work, assemble the remote script locally and pass it through `ssh <host> bash -s`.
7. For large patches or generated content, use small `apply_patch` hunks or a short script invocation. Avoid long command strings.
8. For process cleanup, target a saved root PID and its children. Exclude the current shell, the agent process, and their parent chain.

## Safe Patterns

Use PowerShell here-strings instead of bash heredocs:

```powershell
$code = @'
print("hello from stdin")
'@
$code | & $pythonExe -
```

Send remote Linux scripts through stdin instead of nested `ssh "..."` quoting:

```powershell
$remoteScript = @'
set -euo pipefail
cd /srv/app
docker compose ps
'@
$remoteScript | ssh my-host bash -s
```

Run `.ps1` files with an explicit process policy:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

Resolve native tools explicitly when behavior is suspicious:

```powershell
Get-Command rg | Select-Object Source,Version
rg --version
```

Avoid broad process cleanup:

```powershell
# Prefer a saved root PID from startup, then walk descendants and exclude the
# current PowerShell/agent process tree before Stop-Process.
```

## Common Mistakes

- Using `powershell` by habit and accidentally running Windows PowerShell 5.1.
- Wrapping a PowerShell command in double quotes so `$input`, `$_`, `$Matches`, `$Host`, or `$()` expands in the wrong layer.
- Using reserved or automatic variable names such as `$host`, `$matches`, or `$input` for ordinary data.
- Calling `curl` without deciding whether you mean the PowerShell alias or `curl.exe`.
- Treating local Windows Schannel errors from `curl.exe` as proof that a remote HTTPS service is down.
- Trusting PowerShell wildcard expansion when the target tool has its own glob/pathspec syntax.
- Fixing quoting by adding more quotes to a one-liner after the command already has multiple shell layers.

## Pitfall Reference

For concrete symptoms, causes, and safe replacements, read `references/pitfalls.md` when any checklist item is unclear or a command has already failed.
