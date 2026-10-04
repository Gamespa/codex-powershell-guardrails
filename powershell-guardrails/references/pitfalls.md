# PowerShell Boundary Reference

Read the section relevant to the actual failure. These are conditional patterns,
not a checklist to run for every command.

## Contents

- [Versions and native arguments](#versions-and-native-arguments)
- [Expansion and embedded payloads](#expansion-and-embedded-payloads)
- [SSH and Unix-bound text](#ssh-and-unix-bound-text)
- [Command outcomes](#command-outcomes)
- [Sensitive data](#sensitive-data)
- [Jobs and cleanup](#jobs-and-cleanup)
- [Conditional diagnostics](#conditional-diagnostics)

## Versions and native arguments

`powershell.exe` normally means Windows PowerShell 5.1; `pwsh` means PowerShell
7. Inspect `$PSVersionTable.PSVersion` only when the distinction matters.

| Behavior | Windows PowerShell 5.1 | PowerShell 7 |
| --- | --- | --- |
| `&&` and `||` pipeline chains | Unsupported | Supported |
| Bash heredocs, `NAME=value command` | Unsupported | Unsupported |
| Default native argument passing | Legacy | Configurable from 7.3 |
| `-Encoding utf8` when writing files | UTF-8 with BOM | UTF-8 without BOM |
| Native stdin text encoding | Usually ASCII by default | UTF-8 by default |

PowerShell 7 pipeline chains operate on pipelines, not arbitrary statements.
Use an `if` block when an assignment or control-flow statement makes a chain
unclear. PowerShell's `$()` is a subexpression, not Bash command substitution.

### Native arguments from PowerShell 7.3

`$PSNativeCommandArgumentPassing` can be `Legacy`, `Standard`, or `Windows`.
`Standard` preserves embedded quotes and empty arguments. Windows defaults to
`Windows`, which uses legacy passing for `cmd.exe`, `.cmd`, `.bat`, and some
script hosts. Earlier PowerShell versions and explicit `Legacy` need different
handling. Do not change this preference globally to repair one invocation.

An argument array keeps logical arguments separate, but does not override
native passing mode or a downstream parser:

```powershell
$searchArguments = @('-n', '-F', '--', '<div class="trace-step"', '.\src')
rg @searchArguments
```

A bound string containing `|` is already safe in a simple PowerShell invocation.
For a quote-sensitive tool, verify received arguments with a harmless
argument-echo probe in the affected mode, rather than adding escaping blindly.

`--%` is an escape hatch for native Windows commands, especially legacy empty
arguments. It stops parsing through the newline or pipe, still expands `%ENV%`,
and prevents normal `$variable` expansion. Do not recommend it automatically
for modern native executables.

### Batch setup and environment

A `.bat` setup script changes its child `cmd.exe` environment, not its parent
PowerShell environment. Run the dependent native build in that same child:

```powershell
$devCmd = $env:DEV_CMD_PATH
if (-not $devCmd) { throw 'Set DEV_CMD_PATH to the trusted setup script' }
cmd.exe /d /c "call ""$devCmd"" && cargo test"
if ($LASTEXITCODE -ne 0) { throw 'Native build failed' }
```

This assumes a trusted setup path; do not interpolate untrusted input into
batch code. For a one-command environment override, restore the prior value:

```powershell
$previousPrompt = $env:GIT_TERMINAL_PROMPT
try {
  $env:GIT_TERMINAL_PROMPT = '0'
  git ls-remote origin
  if ($LASTEXITCODE -ne 0) { throw 'Git probe failed' }
} finally {
  $env:GIT_TERMINAL_PROMPT = $previousPrompt
}
```

## Expansion and embedded payloads

Use the current shell unless another interpreter is needed. A nested
double-quoted `-Command` string expands outer variables before the child sees
them. This can lose `$_`, `$input`, `$LASTEXITCODE`, or member expressions.

For automated child PowerShell, use an explicit payload and
`-NoLogo -NoProfile -NonInteractive`. Do not launch a bare interactive shell:

```powershell
pwsh -NoLogo -NoProfile -NonInteractive -Command 'Get-ChildItem -File | ForEach-Object { $_.FullName }'
if ($LASTEXITCODE -ne 0) { throw 'Child probe failed' }
```

Use a script file for complex payloads, or a literal here-string for embedded
code. Backslash does not escape PowerShell quotes. Keep each embedded language
separate, with the closing marker at the start of its own line:

```powershell
$code = @'
print("ready")
'@
$code | python -
if ($LASTEXITCODE -ne 0) { throw 'Python failed' }
```

For repository edits, prefer file-editing tools over generated shell patches.
Serialize JSON; set `ConvertTo-Json -Depth` explicitly for deeply nested data.

### Interpolation, statements, and inventories

`"$name: $value"` is ambiguous with scoped-variable syntax. Use
`"${name}: $value"` or `'{0}: {1}' -f $name, $value`. For member expressions in
expandable strings, use `"status=$($response.StatusCode)"`; `${response}` alone
does not evaluate `.StatusCode`.

Collect statement results, use pipeline cmdlets, or wrap statements before a
pipe. `foreach` and `if` cannot directly occupy a pipeline's first position:

```powershell
& {
  foreach ($item in $items) {
    [pscustomobject]@{ Name = $item.Name }
  }
} | Sort-Object Name
```

Avoid automatic variables such as `$PID`, `$Host`, `$Input`, `$Matches`,
`$Error`, and `$args` as scratch storage. Names are case-insensitive.
Use `$processId`, `$inputText`, or `$searchArguments` instead.

For inventories, use `rg --files` or `git ls-files` when their file scope fits,
and `Get-ChildItem` for a filesystem inventory. A complex report may benefit
from a script file or structured runtime. Ordinary pipelines do not need one
merely because they contain `$_` or `ForEach-Object`.

## SSH and Unix-bound text

A tiny remote command without local interpolation can be one single-quoted
argument. For remote `$()`, heredocs, embedded languages, or several quoting
layers, pass a literal script via stdin:

```powershell
$remoteScript = @'
set -euo pipefail
cd /srv/app
printf 'user=%s\n' "$(id -un)"
'@
$previousEncoding = $OutputEncoding
try {
  $OutputEncoding = [Text.UTF8Encoding]::new($false)
  ($remoteScript -replace "`r`n", "`n") | ssh my-host bash -s
  $remoteExit = $LASTEXITCODE
} finally {
  $OutputEncoding = $previousEncoding
}
if ($remoteExit -ne 0) { throw "Remote script failed: $remoteExit" }
```

The encoding wrapper matters in Windows PowerShell 5.1 or when the native
stdin preference has been overridden. A known PowerShell 7 UTF-8 session
usually needs only LF normalization; LF alone does not guarantee UTF-8.

Uploaded file encoding is separate from native stdin encoding:

```powershell
$scriptLf = $remoteScript -replace "`r`n", "`n"
[IO.File]::WriteAllText($scriptPath, $scriptLf, [Text.UTF8Encoding]::new($false))
scp $scriptPath my-host:/tmp/script.sh
if ($LASTEXITCODE -ne 0) { throw 'Script upload failed' }
ssh my-host bash /tmp/script.sh
if ($LASTEXITCODE -ne 0) { throw 'Remote script failed' }
```

Use unique remote paths for concurrent runs and clean up within the authorized
scope. Transfer exact binary bytes through a binary-safe file or explicit byte
stream. Base64 can help at text-only boundaries, but does not protect secrets.

`bash -s` consumes stdin. Programs inside it can also read and consume script
text. Upload the script or provide a separate protected input channel when a
remote program needs stdin data.

For remote searches, handle expected no-match statuses under `set -e`.
With `pipefail`, `head` can give the producer SIGPIPE. Use a consumer that
drains input or handle that pipeline's status deliberately. `sed -n '1,50p'`
limits displayed lines but still reads the full stream and does not reduce
search work.

## Command outcomes

`$ErrorActionPreference = 'Stop'` handles unexpected cmdlet errors, not every
native nonzero exit. Capture native status before another native command
overwrites it. In scripts, throw or exit explicitly on failure:

```powershell
$ErrorActionPreference = 'Stop'
git diff --check
$diffExit = $LASTEXITCODE
if ($diffExit -ne 0) { throw "Diff check failed: $diffExit" }
```

Search statuses have a distinct no-data outcome:

```powershell
rg -l -- 'optional-feature' .
$searchExit = $LASTEXITCODE
switch ($searchExit) {
  0 { 'matches-found' }
  1 { 'no-matches' }
  default { throw "rg failed with exit code $searchExit" }
}
```

Do not mask genuine search failures with `|| true`. A no-match result is not a
failed search unless the application contract requires a match.

Validate expected artifacts as well as exit status. A generated file can be
empty, truncated, stale, or structurally invalid after zero exit. Use the real
parser or loader where practical.

Prefer machine-readable native output. Splitting `path:line:text` on `:` breaks
drive-letter paths and timestamps. `rg --json` has path and line fields, but
also contains raw matches; sanitize inside the producing process when sensitive.

## Sensitive data

Keep credentials out of command-line arguments, including positional arguments
to `ssh ... bash -s --`. Quoting or base64 does not hide process arguments.

Obtain API tokens from the approved source inside the process, build headers
in memory, and serialize the body. Do not print raw headers, request bodies,
debug traces, or unsanitized errors:

```powershell
if (-not $env:APP_API_TOKEN) { throw 'API token is unavailable' }
$headers = @{ Authorization = 'Bearer ' + $env:APP_API_TOKEN }
$body = [pscustomobject]@{ state = 'ready' } | ConvertTo-Json
try {
  $null = Invoke-RestMethod -Method Post -Uri $env:APP_API_URI -Headers $headers `
    -Body $body -ContentType 'application/json' -ErrorAction Stop
  'request-completed'
} catch {
  throw 'API request failed; inspect sanitized diagnostics'
}
```

A scoped environment variable is one input option, not a general secret store.
Avoid persisting tokens in temporary scripts or user profiles.

For remote secrets, use the application's documented secret-store or protected
stdin protocol. Do not assume `sudo` consumes an application password. Do not
share secret stdin with a `bash -s` script. Establish the remote input contract
before constructing a command when it is unknown.

For credential searches, `rg -l` can return filenames only. For line numbers,
filter JSON records before the outer command runner sees output:

```powershell
$results = rg --json -- 'api_token' .\fixtures
$searchExit = $LASTEXITCODE
if ($searchExit -gt 1) { throw 'Credential search failed' }
foreach ($record in $results) {
  $event = $record | ConvertFrom-Json
  if ($event.type -eq 'match') {
    [pscustomobject]@{
      Path = $event.data.path.text
      Line = $event.data.line_number
      MatchType = 'credential-marker'
    }
  }
}
```

Never stream unfiltered JSON or matching line text to tool output. For large
searches, process events incrementally inside the same shell/runtime.

## Jobs and cleanup

### Local sessions and detached services

Prefer the command runner's persistent session and polling if it supports the
needed lifetime. A yielded session is still running; poll its identifier
rather than launching a duplicate.

Use `Start-Process` when a service must outlive the tool session or the host
lacks persistent execution. Record PID, start time, executable, working
directory, and logs. Use unique state paths and `-WindowStyle Hidden` for
background services unless a visible window was requested. `-ArgumentList`
joins strings; it does not guarantee structured quote-preserving arguments.

Probe readiness with a bounded deadline/retry loop. Immediate connection
failure can be normal during startup. Correlate health, listener owner,
ancestry, and logs. A wrapper PID can differ from the listener's PID.

Before stopping, recheck identity. A stale PID can belong to another process
after reuse. Verify start time and executable as well as PID, inspect
descendants, and protect the current shell, agent, and ancestors. Stop only
the authorized root and verified descendants, not a broad name match.

For filesystem cleanup, resolve the intended root and inspect literal targets.
Verify containment with a directory-separator boundary; account for reparse
points when recursively traversing an untrusted tree. Use the inspected set
in the same shell. `New-Item` takes `-Path`, not `-LiteralPath`.

### Finite jobs, timeouts, and broken pipes

After timeout or `EPIPE`, inspect processes, logs, artifact timestamps, and
parsed outputs before retrying. Check whether the downstream tool accepts
stdin or exited early. A producer's broken pipe may be a secondary symptom.
A nonempty output file alone does not prove success.

Automated child PowerShell needs an explicit noninteractive script or command.
If a `.ps1` package wrapper shares generator stdin, use its `.cmd` entrypoint
when it fits the input contract. Validate child exit and artifacts.

### Remote jobs

Keep and poll an attached SSH session if its lifetime is sufficient. For jobs
that must survive disconnect, use a remote scheduler or detach all three
standard streams. Persist unique job identity, PID, log, and final exit status;
publish status atomically when practical.

Inspect existing state before relaunching. `kill -0` proves only that a PID
exists, not ownership. Fixed PID filenames and check-then-launch do not prevent
concurrent duplicate jobs; use a lock or scheduler when concurrency is possible.

## Conditional diagnostics

- **PATH / Access is denied:** When resolution is suspect, use `Get-Command
  <tool> -All`, `where.exe <tool>`, and a version probe. Discover bundled
  runtimes through the host's dependency tool when available. Do not assume
  cached plugin paths are stable or install software after one failed probe.
- **Script execution policy:** Distinguish `PSSecurityException` from host
  rejection. For a trusted, authorized script, process-scoped
  `-ExecutionPolicy Bypass` may address local policy; it cannot override Group
  Policy or host denial. Do not routinely weaken machine policy.
- **Host rejection:** Stop equivalent retries after `blocked by policy` or
  rejection. Use an independently permitted operation only within its allowed
  scope; otherwise report the rejected action and remaining work.
- **curl / Schannel:** `curl` may be an alias in Windows PowerShell 5.1. Use
  `curl.exe` for the native binary. Cross-check TLS failures with another client
  or logs before diagnosing an outage. Preserve native and HTTP status
  separately; do not disable certificate checks as the default remedy.
- **Missing Bash / WSL:** Confirm availability only when needed. A missing
  wrapper is not a project failure; simple local file checks can use PowerShell.
- **Cold startup / timeouts:** Retry a minimal read-only probe with a suitable
  deadline when startup is suspect. Keep context reads bounded; several
  timed-out reads are not evidence of independent project failures.

## Sources

- [PowerShell parsing and native arguments](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing)
- [Pipeline chain operators](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_pipeline_chain_operators)
- [Character encoding](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding)
- [Execution policies](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)
