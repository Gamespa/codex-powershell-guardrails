# Command Outcomes and Structured Output

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

## Sources

- [Native error preferences](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables#psnativecommanduseerroractionpreference)
- [JSON serialization](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-json)
