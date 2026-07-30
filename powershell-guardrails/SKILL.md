---
name: powershell-guardrails
description: Use when composing fragile Windows PowerShell or pwsh commands involving native tools, SSH, child shells, non-interactive automation, broken pipes, policy rejection, sensitive output, remote jobs, encoding, exit codes, process cleanup, quoting, or errors like ParserError, EPIPE, Access is denied, command line is too long, or running scripts is disabled.
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
- Local dev servers, generators, smoke-test daemons, child PowerShell
  processes, `Start-Process`, PID files, log redirection, or process cleanup.
- Native probes where empty output, stderr, or an exit code distinguishes no
  data from command failure.
- Sensitive searches, machine-readable native output, or long-running remote
  builds that must survive a local timeout.
- Errors such as `ParserError`, `An empty pipe element is not allowed`,
  `The token '&&' is not a valid statement separator`,
  `Missing file specification after redirection operator`,
  `Program 'rg.exe' failed to run: Access is denied`,
  `The command line is too long`, `EPIPE`, `blocked by policy`, or
  `running scripts is disabled`.

Do not use this skill for pure bash/Linux sessions unless a Windows PowerShell
layer is composing the command.

## Fast Path

If time is short, apply these first:

1. For automated child PowerShell, use `pwsh -NoLogo -NoProfile
   -NonInteractive` with explicit `-Command` or `-File`. Never start a bare
   child shell.
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
11. Treat empty stdout as ambiguous until the command's exit code and stderr
    prove whether it succeeded, found nothing, or failed.
12. For sensitive searches, emit only sanitized metadata such as path, line,
    and match type. Do not print the matched value.
13. For remote long-running jobs, save the remote PID, log, and exit status;
    check them before retrying after a local timeout.
14. Treat host `blocked by policy` or `rejected` errors as safety boundaries,
    not PowerShell execution-policy errors. Do not disguise or bypass them.
15. After a local batch timeout or broken pipe, inspect descendants and
    validate persisted outputs before reporting failure, success, or retrying.

## Guardrails

- **Unknown parser boundary:** Name every layer: PowerShell, native executable,
  `cmd.exe`, `ssh`, remote `bash`, Python, SQL, or JSON.
- **Nested PowerShell:** When payloads contain `$`, `$_`, `$input`,
  `$Matches`, or `$()`, use single quotes, a script file, a here-string, or an
  outer scriptblock.
- **Automated child PowerShell:** Never start bare `powershell.exe` or `pwsh`
  in a generator or batch wrapper. Use `-NoLogo -NoProfile -NonInteractive`
  plus explicit `-Command` or `-File`. Invoke a native `.cmd` wrapper directly
  when a sibling `.ps1` would consume shared stdin.
- **Bash syntax in PowerShell:** Keep PowerShell syntax in PowerShell. Do not
  paste heredocs, `&&`, `||`, or command substitutions into a local PowerShell
  layer.
- **Statements before pipes:** If `foreach`, `if`, or another statement emits
  values before a pipe, wrap it in `& { ... } | ...`.
- **Regex and test filters:** Bind filters containing `|` or quotes to a
  variable, or pass them through an argument array.
- **Windows-to-Linux SSH:** Assemble the remote script locally, normalize it to
  LF, and pass it through stdin with `ssh <host> bash -s`. Keep remote
  `$...` variables in the remote or embedded-language layer.
- **Generated payloads:** For JSON, code, SQL, regex, or large patches, use a
  single-quoted here-string, temporary script, stdin, file, serializer, or
  `apply_patch`. Send Unix-bound text as LF and UTF-8 without a BOM; use base64
  when exact bytes or control characters must survive multiple parser layers.
- **Native command outcomes:** Know tool-specific exit codes. Empty output is
  not proof of no data; capture stderr and distinguish no match from failure.
- **Structured native output:** Prefer JSON, NUL-delimited output, or objects
  over splitting human-readable `path:line:text` output.
- **Sensitive output:** Filter secrets, tokens, credentials, and connection
  strings inside the same shell or script. Emit only non-sensitive metadata.
- **Destructive cleanup:** First list exact targets, then keep the final command
  in one shell with `-LiteralPath` where supported or native pathspec arguments.
- **Host safety policy:** Distinguish `PSSecurityException` from host
  `blocked by policy` or `rejected` errors. Process-scoped
  `-ExecutionPolicy Bypass` applies only to the former. Do not switch shells,
  obscure commands, or use alternate APIs to evade host policy.
- **Local service startup:** Treat foreground timeout as inconclusive. Probe
  health, listener PID, and logs separately.
- **Local finite jobs:** Treat a timeout, `EPIPE`, or broken pipe as
  inconclusive. Check the downstream exit and stdin contract, child processes,
  logs, and persisted outputs. Require nonempty, structurally valid outputs
  before reporting success or retrying.
- **Remote long-running jobs:** Treat a local SSH timeout as inconclusive.
  Detach all remote standard streams and persist PID, log, and status files.
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
- Using `$PID` as a scratch variable even though PowerShell reserves it.
- Assuming every filesystem cmdlet supports `-LiteralPath`; `New-Item` uses
  `-Path`.

## References

Read `references/pitfalls.md` for concrete symptoms, causes, and replacements,
especially for variable-boundary, API requests, automated child shells, host
policy rejection, broken pipes, native batch setup, recursive inventory,
local services, cleanup, SSH, and quoting failures.

Use `references/pressure-scenarios.md` before changing this skill's rules. Run
`scripts/verify.ps1` after editing those scenarios.
