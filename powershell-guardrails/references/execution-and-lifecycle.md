# Execution and Lifecycle

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

Build API headers in the process and keep credentials out of command arguments,
request debug output, and unsanitized errors:

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

## Windows-specific diagnostics

- **Resolution:** Use `Get-Command <tool> -All` and `where.exe <tool>` when
  aliases or packaged shims are suspect. Discover bundled runtime paths through
  the host's dependency tool rather than caching plugin paths.
- **Execution policy:** A local `PSSecurityException` differs from host denial.
  Process-scoped `-ExecutionPolicy Bypass` can address local policy for a trusted,
  authorized script; it cannot override Group Policy or host restrictions.
- **curl / Schannel:** Windows PowerShell 5.1 may alias `curl`; use `curl.exe`
  for the native binary. Cross-check a Schannel failure with another client or
  logs before declaring an outage; retain native and HTTP status separately.


## Source

- [PowerShell execution policies](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)
