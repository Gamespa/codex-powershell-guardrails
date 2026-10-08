# Arguments and Expansion

## Native arguments

`$PSNativeCommandArgumentPassing` can be `Legacy`, `Standard`, or `Windows`.
`Standard` preserves embedded quotes and empty arguments. Windows defaults to
`Windows`, which uses legacy passing for `cmd.exe`, `.cmd`, `.bat`, and some
script hosts. Explicit `Legacy` needs different handling.
Do not change this preference globally to repair one invocation.

An argument array keeps logical arguments separate, but does not override
native passing mode or a downstream parser:

```powershell
$searchArguments = @('-n', '-F', '--', '<div class="trace-step"', '.\src')
rg @searchArguments
```

A bound string containing `|` is already safe in a simple PowerShell invocation.
For a quote-sensitive tool, verify received arguments with a harmless
argument-echo probe in the affected mode, rather than adding escaping blindly.

PowerShell does not expand wildcard path arguments for native executables.
On Windows, `rg -n 'marker' .\data\*.json` can pass the literal `*.json` path
to `rg` and fail with an invalid filename. Search the directory and let `rg`
filter filenames instead:

```powershell
rg -n -g '*.json' -- 'marker' .\data
```

Use `rg --files -g '*.json' .\data` for a file inventory. If another native
tool has no glob option, enumerate concrete paths before invoking it; account
for an empty result instead of passing an unmatched wildcard.

Reserve `--%` for a fixed native command that requires it. It stops parsing
through a newline or pipe, still expands `%ENV%`, and prevents `$variable`
expansion; prefer direct arguments for modern executables.

## Batch setup and environment

A `.bat` setup script changes its child `cmd.exe` environment, not its parent
PowerShell environment. Run the dependent native build in that same child:

```powershell
$devCmd = $env:DEV_CMD_PATH
if (-not $devCmd) { throw 'Set DEV_CMD_PATH to the trusted setup script' }
cmd.exe /d /c "call ""$devCmd"" && cargo test"
if ($LASTEXITCODE -ne 0) { throw 'Native build failed' }
```

This assumes a trusted setup path; do not interpolate untrusted input into
batch code. For temporary environment overrides, save the prior value, set and
use the override inside `try`, and restore it in `finally`, including on failure.

## Expansion and embedded payloads

Use the current shell unless another interpreter is needed. A nested
double-quoted `-Command` string expands outer variables before the child sees
them. This can lose `$_`, `$input`, `$LASTEXITCODE`, or member expressions.

For automated child PowerShell, use an explicit payload and
`-NoLogo -NoProfile -NonInteractive`. Do not launch a bare interactive shell:

```powershell
$childShell = Join-Path $PSHOME 'pwsh.exe'
& $childShell -NoLogo -NoProfile -NonInteractive -Command 'Get-ChildItem -File | ForEach-Object { $_.FullName }'
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

Use `"${name}: $value"` to avoid colon/scoped-variable ambiguity and
`"status=$($response.StatusCode)"` to evaluate a member inside a string.

Collect statement results, use pipeline cmdlets, or wrap statements before a
pipe. `foreach` and `if` cannot directly occupy a pipeline's first position:

```powershell
& { foreach ($item in $items) { $item.Name } } | Sort-Object
```

Avoid automatic variables such as `$PID`, `$Host`, `$Input`, `$Matches`,
`$Error`, and `$args` as scratch storage. Names are case-insensitive.
Use `$processId`, `$inputText`, or `$searchArguments` instead.

### Logical expressions and literal matching

Wrap cmdlet invocations before combining their results with `-and` or `-or`:
`if ((Test-Path -LiteralPath $first) -or (Test-Path -LiteralPath $second)) { ... }`.
Otherwise the operator can be parsed as a cmdlet parameter.

Quoting a path does not disable wildcard interpretation. Use `-LiteralPath`
for a concrete name such as `report[1].txt` where the cmdlet supports it.
Keep regex, wildcard, and literal matching separate: use `rg -F` or
`Select-String -SimpleMatch` for literal text, and `[regex]::Escape()` when
inserting literal data into a larger regex. Prefer single-quoted regex
replacements such as `'$1'` when PowerShell interpolation is not intended.

## Sources

- [PowerShell parsing and native arguments](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing)
