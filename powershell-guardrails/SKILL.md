---
name: powershell-guardrails
description: Use when running or composing commands in Windows PowerShell or pwsh, especially with native tools, nested quoting, SSH to Linux, long payloads, scripts, process cleanup, PATH/tool resolution, or errors like ParserError, Access is denied, command line is too long, or running scripts is disabled.
---

# PowerShell Guardrails

## Overview

Windows PowerShell, PowerShell 7, native Windows executables, `cmd.exe`, and
remote Linux shells all parse commands differently. Use this skill to choose
command shapes that make the shell boundary explicit before running fragile
commands.

Core rule: identify which shell expands each character before composing the command.

## When To Use

Use this skill when the active shell is Windows PowerShell or `pwsh` and the task involves any of these:

- `$`, `$_`, `$()`, quotes, pipes, `&&`, `||`, redirects, here-docs, here-strings, or inline JSON/Python/SQL.
- Nested `pwsh -Command`, `ForEach-Object`, `Where-Object`, `$input`,
  `$_.FullName`, or scriptblocks inside another PowerShell command.
- Regexes or test filters for tools/cmdlets (`rg`, `vitest -t`,
  `npm test -- -t`, `Select-String -Pattern`) that contain `|`, `[`, `]`,
  quotes, or backslashes.
- `ssh` from Windows to Linux, especially with `sudo -u`, `bash -lc`, `trap`,
  `xargs`, `printf`, heredocs, command substitution, or nested quotes.
- `.ps1` scripts, execution-policy errors, `curl`/`curl.exe`,
  `Invoke-WebRequest`, `rg`, `git diff`, wildcard arguments, or
  PATH/tool-resolution uncertainty.
- Large command payloads, generated patches, full-file rewrites, or long inline scripts.
- Local dev servers, smoke-test daemons, `Start-Process`, port probes,
  PID files, log redirection, or process cleanup with `Stop-Process`,
  `Get-CimInstance Win32_Process`, or broad command-line matching.
- Errors such as `ParserError`, `An empty pipe element is not allowed`,
  `The token '&&' is not a valid statement separator`,
  `Missing file specification after redirection operator`,
  `Program 'rg.exe' failed to run: Access is denied`,
  `The command line is too long`, or `running scripts is disabled`.

Do not use this skill for pure bash/Linux sessions unless a Windows PowerShell layer is composing the command.

## Fast Path

If time is short, apply these first:

1. Use `pwsh -NoProfile` when you control the PowerShell process.
2. Put nested PowerShell payloads that contain `$`, `$_`, `$input`, or `$()`
   in single quotes, a script file, or a here-string.
3. Send remote Linux work through `ssh <host> bash -s` with an LF-normalized
   script instead of adding quote layers.
4. Verify native tools with `Get-Command`, `where.exe`, and a version probe
   before diagnosing project behavior.
5. Before delete, move, stop, deploy, or other destructive commands, prove the
   target set with a read-only command.
6. For local long-running services, split launch, readiness probe, and cleanup
   into separate commands; record the root PID and verify the actual listener.

## Decision Checklist

Before running a fragile command:

1. Name every shell layer: PowerShell, native executable, `cmd.exe`, `ssh`, remote `bash`, Python, SQL, or JSON parser.
2. Prefer `pwsh -NoProfile` when you control invocation. Do not assume `powershell` means PowerShell 7.
3. Verify executables before diagnosing behavior: `Get-Command <tool> | Select-Object Source,Version`.
4. Keep PowerShell syntax in PowerShell. Do not paste bash heredocs, `&&`,
   `||`, or command substitutions into PowerShell and hope they survive.
5. Do not wrap nested PowerShell in double quotes when the payload contains
   `$`, `$_`, `$input`, `$Matches`, or `$()`. Use single quotes, a script file,
   or an outer scriptblock.
6. If the command contains complex payloads, stop building a one-liner. Use a
   single-quoted here-string, a temporary script, stdin, or a file.
7. If a `foreach`, `if`, or other statement emits values before a pipe, wrap the statement in `& { ... } | ...`.
8. If a regex or test filter contains `|`, bind it to a variable or pass it
   through an argument array so it remains one argument.
9. For Windows-to-Linux remote work, assemble the remote script locally,
   normalize it to LF, and pass it through `ssh <host> bash -s`.
10. Treat local Windows TLS errors from `curl.exe`/Schannel as local probe
    failures until cross-checked from Linux, browser, or service logs.
11. For large patches or generated content, use small `apply_patch` hunks or a
    short script invocation. Avoid long command strings.
12. Treat frequent `pwsh`/`pwsh-invocation` usage as a risk signal, not a
    failure by itself. Apply this checklist to the complex invocations.
13. For process cleanup, target a saved root PID and its children. Exclude the
    current shell, the agent process, and their parent chain.
14. For destructive commands, first list the exact targets with a read-only
    command, then keep the final command in one shell with explicit
    `-LiteralPath` or native pathspec arguments.
15. For local smoke-test servers, do not treat a foreground timeout as a
    startup failure by itself. A server may simply be running. Probe the health
    endpoint, listener PID, and logs in separate commands.
16. If many simple PowerShell commands time out together, retry with smaller
    read-only commands or a longer timeout before diagnosing project behavior.

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
($remoteScript -replace "`r`n", "`n") | ssh my-host bash -s
```

Write remote scripts to files when they need `trap`, `sudo bash -lc`, or many quotes:

```powershell
$remoteScript = @'
set -euo pipefail
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
tar -xf /tmp/app.tar -C "$tmp_dir"
'@
[IO.File]::WriteAllText($scriptPath, $remoteScript -replace "`r`n", "`n")
scp $scriptPath my-host:/tmp/deploy.sh
ssh my-host bash /tmp/deploy.sh
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

Build argument arrays when regexes, paths, or test filters must remain one
native argument:

```powershell
$tool = (Get-Command rg -ErrorAction Stop).Source
$searchPattern = 'service-password|service.*password'
$args = @('--', $searchPattern, '.')
& $tool @args
```

For mixed quoted literals and regex alternation, bind the pattern first or use
fixed-string searches:

```powershell
$tool = (Get-Command rg -ErrorAction Stop).Source
$needles = @('<div class="trace-step"', 'id="tab-')
foreach ($needle in $needles) {
  & $tool -n -F -- $needle .\src
}
```

Start a long-running local service separately from readiness checks:

```powershell
$pidPath = Join-Path $env:TEMP 'app-smoke.pid'
$proc = Start-Process -FilePath .\app-server.exe -WorkingDirectory (Get-Location).Path -WindowStyle Hidden -PassThru
Set-Content -LiteralPath $pidPath -Value $proc.Id
Invoke-WebRequest -Uri $env:APP_HEALTH_URL -UseBasicParsing -TimeoutSec 5
Get-NetTCPConnection -LocalPort $env:APP_PORT -State Listen -ErrorAction SilentlyContinue |
  Select-Object LocalAddress, LocalPort, State, OwningProcess
```

Avoid broad process cleanup:

```powershell
# Prefer a saved root PID from startup, then walk descendants and exclude the
# current PowerShell/agent process tree before Stop-Process.
```

## Common Mistakes

- Using `powershell` by habit and accidentally running Windows PowerShell 5.1.
- Wrapping nested PowerShell or bash payloads in double quotes so `$input`,
  `$_`, `$Matches`, `$Host`, `$(mktemp -d)`, or `$()` expands in the wrong
  layer.
- Piping directly after a `foreach` statement block instead of wrapping the statement in `& { ... }`.
- Letting an outer PowerShell strip `$lines` from `$lines[220..228]`, `$_`
  from `$_.LineNumber`, or loop variables from `foreach ($x in $xs)`.
- Passing regex/test filters with `|` through multiple shell layers without proving they stayed one native argument.
- Passing quoted markup or regex alternation to `rg` in one double-quoted
  string until PowerShell treats pieces such as `id=` as a module or command.
- Mixing PowerShell assignments with bash-style `&&`, such as `rg ... && $c = Get-Content ...`.
- Running long-lived servers in the foreground under a short tool timeout, then
  treating the timeout alone as evidence that startup failed.
- Trusting a PID file alone for cleanup when the actual listener may be owned
  by a child process. Verify the listener owner before stopping processes.
- Using double-quoted here-strings for remote bash scripts that contain `$()`, `$var`, or `trap`.
- Building JSON, Rust, regex, or code patches as dense inline strings instead
  of using a here-string, temp file, structured serializer, or `apply_patch`.
- Using reserved or automatic variable names such as `$host`, `$matches`, or `$input` for ordinary data.
- Assuming `pnpm`, `rg`, `node`, or another native tool exists without first
  checking `Get-Command` when resolution is suspicious.
- Calling `curl` without deciding whether you mean the PowerShell alias or `curl.exe`.
- Treating local Windows Schannel errors from `curl.exe` as proof that a remote HTTPS service is down.
- Treating `Access is denied` on temp, database, or PID files as only a
  permissions problem before checking file locks and owning processes.
- Trusting PowerShell wildcard expansion when the target tool has its own glob/pathspec syntax.
- Fixing quoting by adding more quotes to a one-liner after the command already has multiple shell layers.

## Pitfall Reference

For concrete symptoms, causes, and safe replacements, read
`references/pitfalls.md` when any checklist item is unclear or a command has
already failed.

For validation prompts that exercise the most important failure modes, read
`references/pressure-scenarios.md` before changing this skill's rules.
