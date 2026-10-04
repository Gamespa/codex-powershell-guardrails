# Arguments and Expansion

## Versions and native arguments

`powershell.exe` normally means Windows PowerShell 5.1; `pwsh` means PowerShell
7. Inspect `$PSVersionTable.PSVersion` only when the distinction matters.

| Behavior | Windows PowerShell 5.1 | PowerShell 7 |
| --- | --- | --- |
| `&&` and `||` pipeline chains | Unsupported | Supported |
| Bash heredocs, `NAME=value command` | Unsupported | Unsupported |
| Default native argument passing | Legacy | Configurable from 7.3 |

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

### Interpolation and statements

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

## Sources

- [PowerShell parsing and native arguments](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing)
- [Pipeline chain operators](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_pipeline_chain_operators)
