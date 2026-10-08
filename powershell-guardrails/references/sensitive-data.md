# Sensitive Data

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
