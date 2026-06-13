---
name: powershell-guardrails
description: Use when composing fragile Windows PowerShell or pwsh commands involving native tools, SSH, curl.exe, process cleanup, quoting, or errors like ParserError, Access is denied, command line is too long, or running scripts is disabled.
---

# PowerShell Guardrails

## Overview

Windows PowerShell, PowerShell 7, native Windows executables, `cmd.exe`, SSH,
remote Linux shells, and embedded parsers all expand text differently.

Core rule: before composing a fragile command, name which layer expands `$`,
quotes, globs, pipes, redirects, regexes, and newlines. Prefer explicit,
inspectable command shapes over clever one-liners.

## When To Use

Use this skill when the active shell is Windows PowerShell or `pwsh` and the
work includes any of these:

- `$`, `$_`, `$()`, quotes, pipes, `&&`, `||`, redirects, here-docs,
  here-strings, or inline JSON/Python/SQL.
- Nested `pwsh -Command`, `ForEach-Object`, `Where-Object`, `$input`,
  `$_.FullName`, member access, or scriptblocks inside another command.
- Regexes or test filters for tools/cmdlets (`rg`, `vitest -t`,
  `npm test -- -t`, `Select-String -Pattern`) with `|`, `[`, `]`, quotes, or
  backslashes.
- Windows-to-Linux SSH with `sudo -u`, `bash -lc`, `trap`, `xargs`, `printf`,
  heredocs, command substitution, or nested quotes.
- `.ps1` scripts, execution-policy errors, `curl`/`curl.exe`,
  `Invoke-WebRequest`, `rg`, `git diff`, wildcard arguments, or
  PATH/tool-resolution uncertainty.
- Large command payloads, generated patches, full-file rewrites, API headers,
  tokens, JSON bodies, file metrics, line counts, or inventory reports.
- PowerShell interpolation where a variable is followed by `:`, `[`, `.`,
  quotes, or other punctuation.
- Local dev servers, smoke-test daemons, `Start-Process`, port probes, PID
  files, log redirection, or process cleanup.
- Errors such as `ParserError`, `An empty pipe element is not allowed`,
  `The token '&&' is not a valid statement separator`,
  `Missing file specification after redirection operator`,
  `Program 'rg.exe' failed to run: Access is denied`,
  `The command line is too long`, or `running scripts is disabled`.

Do not use this skill for pure bash/Linux sessions unless a Windows PowerShell
layer is composing the command.

## Fast Path

If time is short, apply these first:

1. Use `pwsh -NoProfile` when you control the PowerShell process.
2. Put nested PowerShell payloads containing `$`, `$_`, `$input`, or `$()` in
   single quotes, a script file, or a here-string.
3. Send remote Linux work through `ssh <host> bash -s` with an LF-normalized
   script instead of adding quote layers.
4. Verify native tools with `Get-Command`, `where.exe`, and a version probe
   before diagnosing project behavior.
5. Before delete, move, stop, deploy, or other destructive commands, prove the
   target set with a read-only command.
6. For local long-running services, split launch, readiness probe, listener
   check, and cleanup. Record the root PID.
7. For API headers, tokens, JSON bodies, or many endpoint probes, use a script
   file or structured serializer.
8. If interpolation puts punctuation after a variable, use `${name}` or
   `'{0}: {1}' -f $name, $value`.
9. For file metrics, line counts, or inventory reports, use `rg --files`,
   `git ls-files`, a `.ps1` file, or a structured runtime after the first
   nested PowerShell parse failure.
10. If a native command needs success/failure branching, keep the branch in the
    same script file or script block.

## Guardrails

- **Unknown parser boundary:** Name every layer: PowerShell, native executable,
  `cmd.exe`, `ssh`, remote `bash`, Python, SQL, or JSON.
- **Nested PowerShell:** When payloads contain `$`, `$_`, `$input`,
  `$Matches`, or `$()`, use single quotes, a script file, a here-string, or an
  outer scriptblock.
- **Bash syntax in PowerShell:** Keep PowerShell syntax in PowerShell. Do not
  paste heredocs, `&&`, `||`, or command substitutions into a local PowerShell
  layer.
- **Statements before pipes:** If `foreach`, `if`, or another statement emits
  values before a pipe, wrap it in `& { ... } | ...`.
- **Regex and test filters:** Bind filters containing `|` or quotes to a
  variable, or pass them through an argument array.
- **Windows-to-Linux SSH:** Assemble the remote script locally, normalize it to
  LF, and pass it through stdin with `ssh <host> bash -s`.
- **Generated payloads:** For JSON, code, SQL, regex, or large patches, use a
  single-quoted here-string, temporary script, stdin, file, serializer, or
  `apply_patch`.
- **Destructive cleanup:** First list exact targets, then keep the final command
  in one shell with explicit `-LiteralPath` or native pathspec arguments.
- **Local service startup:** Treat foreground timeout as inconclusive. Probe
  health, listener PID, and logs separately.
- **Process cleanup:** Target a saved root PID and descendants. Exclude the
  current shell, agent process, and their parent chain.
- **Suspicious tool behavior:** Verify executable resolution before diagnosing
  behavior.
- **Windows TLS probes:** Treat `curl.exe`/Schannel errors as local probe
  failures until cross-checked elsewhere.
- **Native batch setup:** Use `cmd.exe /d /c "call ... && ..."`. `.bat` files
  do not mutate the parent PowerShell process.
- **One-command environment variables:** Set `$env:NAME` in PowerShell or use a
  wrapper script. Bash-style `NAME=value command` is not PowerShell syntax.

## Safe Patterns

Use single-quoted here-strings for embedded code:

```powershell
$code = @'
print("hello from stdin")
'@
$code | & $pythonExe -
```

Send remote Linux scripts through stdin:

```powershell
$remoteScript = @'
set -euo pipefail
cd /srv/app
docker compose ps
'@
($remoteScript -replace "`r`n", "`n") | ssh my-host bash -s
```

Build argument arrays when regexes, paths, or test filters must stay single
native arguments:

```powershell
$tool = (Get-Command rg -ErrorAction Stop).Source
$searchPattern = 'service-password|service.*password'
$args = @('--', $searchPattern, '.')
& $tool @args
```

Start local smoke-test services separately from readiness checks:

```powershell
$pidPath = Join-Path $env:TEMP 'app-smoke.pid'
$proc = Start-Process -FilePath .\app-server.exe -WorkingDirectory (Get-Location).Path -WindowStyle Hidden -PassThru
Set-Content -LiteralPath $pidPath -Value $proc.Id
Invoke-WebRequest -Uri $env:APP_HEALTH_URL -UseBasicParsing -TimeoutSec 5
Get-NetTCPConnection -LocalPort $env:APP_PORT -State Listen -ErrorAction SilentlyContinue |
  Select-Object LocalAddress, LocalPort, State, OwningProcess
```

Run `.ps1` files with an explicit execution policy when needed:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

## Common Mistakes

- Using `powershell` by habit and accidentally running Windows PowerShell 5.1.
- Wrapping nested PowerShell or bash payloads in double quotes so variables or
  command substitutions expand in the wrong layer.
- Piping directly after `foreach`, `if`, or another statement block.
- Passing regex/test filters through multiple shell layers without proving they
  stayed one argument.
- Using `\"` as if it escapes nested double quotes in PowerShell.
- Mixing PowerShell assignments with bash-style chaining or environment syntax.
- Hiding API calls, `param` blocks, generated JSON, or native `.bat` setup
  inside dense one-liners.
- Trusting PID files, PowerShell wildcards, or local TLS errors without a
  second read-only check.
- Assuming `pnpm`, `rg`, `node`, `curl`, or another native tool resolves to the
  executable you intended.

## References

Read `references/pitfalls.md` for concrete symptoms, causes, and replacements,
especially for variable-boundary, API request, native batch setup, recursive
inventory, local service, cleanup, SSH, and quoting failures.

Use `references/pressure-scenarios.md` before changing this skill's rules. Run
`scripts/verify.ps1` after editing those scenarios.
