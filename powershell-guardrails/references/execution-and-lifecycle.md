# Execution and Lifecycle

## Command outcomes

`$ErrorActionPreference = 'Stop'` handles unexpected cmdlet errors. Native
nonzero exits also follow it when `$PSNativeCommandUseErrorActionPreference`
is enabled. Capture native status before another native command
overwrites it. In scripts, throw or exit explicitly on failure:

```powershell
$ErrorActionPreference = 'Stop'
git diff --check
$diffExit = $LASTEXITCODE
if ($diffExit -ne 0) { throw "Diff check failed: $diffExit" }
```

Search statuses have a distinct no-data outcome. Locally disable automatic
native errors when a tool uses nonzero status for expected outcomes, then
interpret its exit-code contract explicitly. Do not change the session globally:

```powershell
& {
  $PSNativeCommandUseErrorActionPreference = $false
  rg -l -- 'optional-feature' .
  $searchExit = $LASTEXITCODE
  switch ($searchExit) {
    0 { 'matches-found' }
    1 { 'no-matches' }
    default { throw "rg failed with exit code $searchExit" }
  }
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

## Structured output

Keep original objects until serialization. `Format-Table` and `Format-List`
emit formatting records, so do not feed them into JSON/CSV or business logic.
Functions emit every uncaptured success-stream value, including values before
`return`; suppress incidental output when returning a structured result.

Wrap zero/one/many results in `@(...)` when downstream code requires an array.
Use `ConvertTo-Json -InputObject @($items)` to preserve an array's shape, and
choose `-Depth` to cover the actual nested structure (the default is 2).
Use `ConvertFrom-Json -NoEnumerate` for a one-element JSON array round trip.
Read JSON text with `Get-Content -LiteralPath $path -Raw` before parsing.

## Sensitive data

Keep credentials out of command-line arguments, including positional arguments
to `ssh ... bash -s --`. Quoting or base64 does not hide process arguments.

Build authentication headers in the process. Keep credentials out of request
debug output and unsanitized errors. A scoped environment variable is one input
option, not a secret store; avoid persisting tokens in scripts or profiles.

For remote secrets, use the application's documented secret-store or protected
stdin protocol. Do not assume `sudo` consumes an application password. Do not
share secret stdin with a `bash -s` script. Establish the remote input contract
before constructing a command when it is unknown.

For credential searches, `rg -l` can return filenames only. For line numbers,
filter JSON records before the outer command runner sees output:

```powershell
& {
  $PSNativeCommandUseErrorActionPreference = $false
  $results = rg --json -- 'api_token' .\fixtures
  $searchExit = $LASTEXITCODE
  if ($searchExit -notin @(0, 1)) { throw 'Credential search failed' }
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

Poll an attached SSH session when sufficient. To survive disconnect, use a
scheduler or detach stdin/stdout/stderr, retaining unique job identity, logs,
and final exit status. Inspect prior state before retrying; `kill -0` does not
prove ownership. Use a lock or scheduler when concurrent launch is possible.

## Windows-specific diagnostics

- **Resolution:** Use `Get-Command <tool> -All` and `where.exe <tool>` when
  aliases or packaged shims are suspect. Discover bundled runtime paths through
  the host's dependency tool rather than caching plugin paths.
- **Execution policy:** A local `PSSecurityException` differs from host denial.
  Process-scoped `-ExecutionPolicy Bypass` can address local policy for a trusted,
  authorized script; it cannot override Group Policy or host restrictions.
- **curl / Schannel:** Use `curl.exe` when command resolution is ambiguous.
  Cross-check a Schannel failure with another client or
  logs before declaring an outage; retain native and HTTP status separately.


## Sources

- [PowerShell execution policies](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)
- [Native error preferences](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables#psnativecommanduseerroractionpreference)
- [JSON serialization](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-json)
