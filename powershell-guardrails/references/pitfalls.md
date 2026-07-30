# PowerShell Pitfalls Reference

This reference lists recurring Windows PowerShell failure modes and safe
replacements. Keep examples generic so the skill remains reusable across
machines and repositories.

## 1. Default `powershell` Is Often Windows PowerShell 5.1

Symptoms:

- `The token '&&' is not a valid statement separator in this version.`
- Commands behave differently than a PowerShell 7 example.

Safer pattern:

```powershell
pwsh -NoProfile -Command '$PSVersionTable.PSVersion'
```

Use `pwsh` explicitly when you need PowerShell 7 behavior. Use `powershell`
only when you intentionally need Windows PowerShell.

## 1a. Bare Child PowerShell In Automation

Symptoms:

- A generator hangs with an idle `powershell.exe` child and no descendants.
- A publisher-trust prompt or interactive prompt consumes commands intended
  for the child shell.
- Generated files are empty or partial even though the parent exits with `0`.

Common causes:

- A batch file or generator starts `powershell.exe` or `pwsh` without an
  explicit command or script.
- The child inherits redirected stdin and waits at an interactive prompt.
- A discovered `.ps1` package wrapper consumes stdin that contained later
  commands such as the next generator step or `exit`.

Safer pattern:

```powershell
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
& $pwsh -NoLogo -NoProfile -NonInteractive -File .\generate-schema.ps1
if ($LASTEXITCODE -ne 0) { throw 'schema generation failed' }

$output = Get-Item -LiteralPath .\out\schema.js -ErrorAction Stop
if ($output.Length -eq 0) { throw 'schema output is empty' }
```

Validate generated content with its real parser or loader when possible. A
nonempty file can still be truncated or structurally incomplete.

When a package exposes both `.cmd` and `.ps1` entry points, invoke the intended
`.cmd` directly if a PowerShell wrapper would share or consume generator stdin.
Do not use parent exit code alone as proof that every child step completed.

## 2. Bash Syntax In PowerShell

Symptoms:

- `Missing file specification after redirection operator`
- `The token '&&' is not a valid statement separator`
- `ParserError`
- `Unexpected token '=' in expression or statement`
- `The term 'head' is not recognized`

Common causes:

- `python - <<'PY'` copied from bash.
- `cmd1 && cmd2` sent to Windows PowerShell 5.1.
- `rg pattern file && $content = Get-Content file` sent to PowerShell 7.
- `rg pattern . | head` copied from bash into local PowerShell.
- Bash `$()` command substitution used in a local PowerShell layer.

Safer pattern:

```powershell
$script = @'
echo "portable payload"
'@
$script | ssh my-host bash -s
```

For native command success checks followed by PowerShell work, keep the control flow in PowerShell:

```powershell
rg pattern file
if ($LASTEXITCODE -eq 0) {
  $content = Get-Content -LiteralPath file
}
```

Do not chain into an assignment with `&&`.

For local output limits, use `Select-Object -First`; reserve `head`, `tail`,
`xargs`, and similar filters for pipelines that fully run in bash, WSL, Git
Bash, or remote Linux.

## 3. Empty Pipe From Premature Variable Expansion

Symptoms:

- `An empty pipe element is not allowed.`
- The error points to a line beginning with `|`.
- `The term '.FullName' is not recognized`
- `Missing type name after '['`
- `The term '.LineNumber.ToString' is not recognized`
- A loop arrives as `foreach ( in )`.
- A nested `pwsh -Command` loses `$_`, `$input`, or another automatic variable.

Common cause:

```powershell
git show HEAD:file.txt | powershell -NoProfile -Command "$input | Set-Content out.txt"
```

The outer PowerShell can expand `$input` before the nested shell receives it.

The same issue happens with pipeline variables:

```powershell
pwsh -NoProfile -Command "Get-ChildItem | ForEach-Object { $_.FullName }"
```

If the outer PowerShell parses this string first, `$_` can disappear and the nested command receives `.FullName`.

This also breaks ordinary variables and index ranges:

```powershell
pwsh -NoProfile -Command "$lines = Get-Content file.txt; $lines[220..228]"
```

The nested shell can receive `= Get-Content file.txt; [220..228]`, because the outer shell expanded `$lines` first.

Safer patterns:

```powershell
git show HEAD:file.txt | pwsh -NoProfile -Command '$input | Set-Content out.txt'
```

```powershell
pwsh -NoProfile -Command 'Get-ChildItem | ForEach-Object { $_.FullName }'
```

```powershell
$script = @'
$lines = Get-Content -LiteralPath 'C:\path\file.md'
$lines[220..228]
'@
pwsh -NoProfile -Command $script
```

or avoid nested PowerShell and write to a file directly from the outer command.

## 3a. Piping After PowerShell Statements

Symptoms:

- `ParserError`
- `An empty pipe element is not allowed.`
- The error points at `} | Format-Table`, `} | Format-List`, or another pipe after a statement.
- The error appears after `foreach (...) { ... } | ConvertTo-Json` or `if (...) { ... } | Format-Table`.

Common cause:

```powershell
foreach ($item in $items) {
  [pscustomobject]@{ Name = $item.Name }
} | Format-Table
```

`foreach` is a statement, not an expression in the pipeline position.

Safer pattern:

```powershell
& {
  foreach ($item in $items) {
    [pscustomobject]@{ Name = $item.Name }
  }
} | Format-Table
```

Use the same wrapper before `ConvertTo-Json`, `Sort-Object`, `Where-Object`, or any other downstream command.

## 3b. Regex And Test Names Containing Pipe Characters

Symptoms:

- `The term 'rewrites' is not recognized`
- `The term 'hydrates' is not recognized`
- `The term 'localizes' is not recognized`
- `The term 'service.*password' is not recognized`
- `The module 'id=' could not be loaded`
- `rg: regex parse error`
- `error: unclosed group`
- `Missing property name after reference operator`

Common causes:

```powershell
npm test -- -t "rewrites machine text|rewrites singular text"
rg "service-password|service.*password" .
rg -n "<div class=\"trace-step\"|id=\"tab-" .\src
```

These can be valid in a single PowerShell layer, but they become fragile when
generated by another shell, nested inside `pwsh -Command`, or mixed with
interpolation. Embedded quotes can also end the PowerShell string early, so the
next alternation branch is parsed as a command or module name before `rg` ever
receives the intended pattern.

Safer patterns:

```powershell
$testNamePattern = 'rewrites machine text|rewrites singular text'
npm test -- --run path/to/test.spec.ts -t $testNamePattern
```

```powershell
$searchPattern = 'service-password|service.*password'
rg -- $searchPattern .
```

For complex command construction, build an argument array and invoke with
`& $tool @args` so the regex remains one native argument.

```powershell
$tool = (Get-Command rg -ErrorAction Stop).Source
$searchPattern = 'service-password|service.*password'
$args = @('--', $searchPattern, '.')
& $tool @args
```

When the intent is to find several literal snippets, avoid making one giant
regex. Use fixed-string searches with a bound argument:

```powershell
$tool = (Get-Command rg -ErrorAction Stop).Source
$needles = @('<div class="trace-step"', 'id="tab-', 'data-tab=')
foreach ($needle in $needles) {
  & $tool -n -F -- $needle .\src
}
```

Use the same pattern for test runners when a generated command contains spaces,
quotes, brackets, or pipes in one filter argument.

## 3c. Inline JSON, Code, And Regex Payloads

Symptoms:

- `Unexpected token 'components...'`
- `Unexpected token 'components\": components::components(),"'`
- A quote fix creates a new parse error somewhere else in the same one-liner.

Common cause:

PowerShell, JSON, Rust, JavaScript, regex, or another language are all being escaped in one inline string.

Safer patterns:

- Use `apply_patch` for repository edits.
- Use a single-quoted here-string for script payloads.
- Use a temporary file when the payload contains many quotes or backslashes.
- Use a structured serializer for JSON instead of hand-escaped JSON text.
- For API calls with headers, tokens, JSON bodies, or several endpoints, write
  a `.ps1` file or use a structured runtime. Do not hide the whole request in
  nested `pwsh -Command` strings.
- In a `.ps1` file, put the `param` block before setup statements,
  assignments, or output-emitting lines.

```powershell
param(
  [string]$Token,
  [string]$Uri
)

$headers = @{ Authorization = "Bearer $Token" }
$body = [pscustomobject]@{ state = 'ready' } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri $Uri -Headers $headers -Body $body -ContentType 'application/json'
```

## 3d. Member Access And Indexing In Nested Commands

Symptoms:

- `.StatusCode: The term '.StatusCode' is not recognized`
- `.ToString: The term '.ToString' is not recognized`
- `.Path: The term '.Path' is not recognized`
- `Unexpected token '[423]' in expression or statement`
- `Missing type name after '['`

Common causes:

```powershell
pwsh -NoProfile -Command "$response = Invoke-WebRequest $uri; $response.StatusCode"
```

```powershell
pwsh -NoProfile -Command "(Get-Content -LiteralPath .\notes.md) [423]"
```

The first command lets the outer PowerShell expand `$response`, so the nested
process receives `.StatusCode` as a command. The second separates an expression
from its index operation and becomes fragile when nested or generated.

Safer patterns:

```powershell
pwsh -NoProfile -Command '$response = Invoke-WebRequest $env:PROBE_URI; $response.StatusCode'
```

```powershell
pwsh -NoProfile -Command '$lines = Get-Content -LiteralPath .\notes.md; $lines[423]'
```

For several member accesses, indexes, or endpoint probes, switch to a script
file and pass values through parameters or environment variables.

## 3e. Complex Local Inventory One-Liners

Symptoms:

- A recursive file metric command fails with `An empty pipe element is not allowed`.
- `$files`, `$_`, `.Name`, `.FullName`, or `.FullName.Substring` disappears.
- Several "fixed" versions of the same `Get-ChildItem | Where-Object |
  ForEach-Object | Sort-Object` one-liner fail differently.
- The command times out while trying to measure many files through PowerShell
  pipelines.

Common cause:

```powershell
pwsh -NoProfile -Command "$files = Get-ChildItem -Recurse -File; `
  $files | ForEach-Object { [pscustomobject]@{ Name=$_.Name; `
  Lines=(Get-Content -LiteralPath $_.FullName | Measure-Object -Line).Lines } } | `
  Sort-Object Lines"
```

This combines nested PowerShell, loop variables, member access, hashtables,
pipeline statements, and a potentially large filesystem walk in one generated
string. When it fails, adding quote layers usually creates new parse errors or
silently corrupts the measurement.

Safer patterns:

- For tracked repository files, prefer `git ls-files` plus a small script.
- For search-oriented inventories, prefer `rg --files` and post-process the
  plain path list.
- For line counts or grouped metrics, use a `.ps1` file or structured runtime
  such as Node/Python.
- Keep the first probe bounded with explicit roots and `Select-Object -First`
  before broadening the scan.

PowerShell script-file shape:

```powershell
$root = (Get-Location).Path
Get-ChildItem -LiteralPath . -Recurse -File |
  Where-Object { $_.FullName -notmatch '\\(target|node_modules|\.git)\\' } |
  ForEach-Object {
    $lineCount = (Get-Content -LiteralPath $_.FullName -ErrorAction SilentlyContinue |
      Measure-Object -Line).Lines
    [pscustomobject]@{
      Lines = $lineCount
      Path = $_.FullName.Substring($root.Length + 1)
    }
  } |
  Sort-Object Lines -Descending |
  Select-Object -First 50
```

If that script is itself being generated through another shell layer, save it
to a `.ps1` file and run `pwsh -NoProfile -File` instead of passing it through
nested `-Command`.

## 3f. Exit-Code Branches In Fragile Commands

Symptoms:

- A combined probe fails because `$LASTEXITCODE` disappears or becomes a bare
  token.
- `-eq: The term '-eq' is not recognized` or `-ne: The term '-ne' is not
  recognized` after a nested probe is squeezed into one string.
- `if ($LASTEXITCODE -ne 0) { ... }` is appended to a nested one-liner and
  starts a new parse error.
- The command works as two separate lines but breaks when compressed into one
  generated string.

Risky shape:

```powershell
pwsh -NoProfile -Command "rg pattern file; if ($LASTEXITCODE -ne 0) { exit 1 }"
```

From an outer PowerShell prompt, the double-quoted `-Command` payload lets the
outer layer expand `$LASTEXITCODE` before the child shell sees it. In generated
or nested commands, adding a success/failure branch to the same string also
makes the parser and control flow share the same fragile layer.

Safer patterns:

```powershell
& {
  rg pattern file
  if ($LASTEXITCODE -ne 0) {
    exit 1
  }
}
```

Or move the branch into a `.ps1` file and keep the native probe and PowerShell
control flow together there. If the command already spans multiple tools or
shell layers, do not add a one-liner exit-code shim after the fact.

## 3g. Empty Output And Native Search Exit Codes

Symptoms:

- A successful search with no matches is reported as a command failure.
- An actual search error is reported as "nothing found."
- `set -e` stops a remote script before later checks run.

Common cause:

Search tools often have more than two outcomes. For `rg` and `grep`, exit code
`0` means a match, `1` means no match, and `2` or greater means an error. Empty
stdout alone does not identify which outcome occurred.

Safer pattern:

```powershell
$tool = (Get-Command rg -ErrorAction Stop).Source
& $tool -l -- 'optional-feature' .
$searchExit = $LASTEXITCODE

switch ($searchExit) {
  0 { 'matches-found' }
  1 { 'no-matches' }
  default { throw "rg failed with exit code $searchExit" }
}
```

In remote bash scripts that use `set -e`, put an expected no-match probe inside
an explicit `if` or temporarily capture its status before restoring strict
error handling. Do not append `|| true` when real search errors must remain
visible.

## 3h. Parsing Human-Readable Native Output

Symptoms:

- Splitting `path:line:text` on `:` corrupts Windows paths or timestamped log
  lines.
- A path, line number, or match value is assigned to the wrong field.
- Colored or localized output breaks a parser that previously worked.

Safer pattern:

Use a native machine-readable mode when one exists. For example, parse
`rg --json` events instead of splitting display text:

```powershell
$tool = (Get-Command rg -ErrorAction Stop).Source
& $tool --json -- 'request failed' . |
  ForEach-Object {
    $event = $_ | ConvertFrom-Json
    if ($event.type -eq 'match') {
      [pscustomobject]@{
        Path = $event.data.path.text
        Line = $event.data.line_number
      }
    }
  }
```

Prefer JSON, NUL-delimited records, CSV, or PowerShell objects. Parse display
text only when the tool has no stable machine-readable format.

## 3i. Sensitive Searches Without Secret Output

Symptoms:

- A search for a credential prints the credential into tool output or logs.
- A token appears in a generated command line, process list, or error report.
- Redaction happens after raw output has already crossed the trust boundary.

Safer patterns:

- Filter raw matches inside the same shell or script that runs the search.
- Emit only path, line number, match type, status code, or other non-sensitive
  metadata.
- Do not print `rg --json` line text when the match may contain a secret.
- Pass secrets through an appropriate secret store, protected stdin, or a
  scoped environment variable rather than a command-line argument.
- Redirect or sanitize debug output before invoking tools that echo headers,
  request bodies, configuration files, or full matching lines.

If exact match verification is required, compare a hash, length, or boolean in
the trusted process and return only that result.

## 4. Windows To Remote Linux Quoting

Symptoms:

- Remote command receives missing variables.
- `$(...)`, `$VAR`, quotes, or heredocs behave differently than expected.
- Inline `ssh "..."` keeps growing quote layers.

Safer pattern:

```powershell
$remote = @'
set -euo pipefail
user="$(id -un)"
printf 'user=%s\n' "$user"
'@
($remote -replace "`r`n", "`n") | ssh my-host bash -s
```

Switch to this pattern when remote commands include `$(...)`, heredocs,
`xargs`, `sudo -u`, embedded JSON/Python/SQL, or nested quotes.

Do the same when the remote payload contains target-language `$...` variables
such as shell positional args, awk fields, or Perl variables:

```powershell
$remote = @'
find . -type f | awk '{print $1}'
printf '%s\n' "$1"
'@
($remote -replace "`r`n", "`n") | ssh my-host bash -s -- value
```

## 4a. Remote `$(...)` Executed By Local PowerShell

Symptoms:

- `The term 'mktemp' is not recognized`
- A remote command such as `$(mktemp -d)` fails locally before SSH runs it.
- Remote variables arrive empty or malformed.

Common causes:

```powershell
ssh my-host "tmp_dir=$(mktemp -d); tar -xf /tmp/app.tar -C $tmp_dir"
```

```powershell
$script = @"
set -euo pipefail
tmp_dir="$(mktemp -d)"
"@
$script | ssh my-host bash -s
```

PowerShell expands `$()` inside double-quoted strings and double-quoted here-strings.

Safer pattern:

```powershell
$script = @'
set -euo pipefail
tmp_dir="$(mktemp -d)"
tar -xf /tmp/app.tar -C "$tmp_dir"
'@
($script -replace "`r`n", "`n") | ssh my-host bash -s
```

Use single-quoted here-strings for remote bash. Normalize CRLF to LF before sending to Linux.

## 4b. `trap`, `sudo bash -lc`, And Nested Remote Quotes

Symptoms:

- `ParserError: Unexpected token 'set'`
- `line 1: 'rm -rf...`
- Bash `trap` lines are truncated or quoted incorrectly.
- Adding more backslashes makes a command more fragile instead of fixing it.

Common causes:

```powershell
$remote = "printf '%s' '$pw' | sudo bash -lc \"set -euo pipefail; source /etc/app.env; app reset\""
ssh my-host $remote
```

```powershell
ssh my-host "bash -lc 'tmp_dir=$(mktemp -d); trap 'rm -rf "$tmp_dir"' EXIT; app deploy'"
```

These commands cross PowerShell, OpenSSH, remote bash, nested bash, and
sometimes `sudo`. Each layer has different quote rules.

Safer pattern:

```powershell
$script = @'
set -euo pipefail
password="$1"
printf '%s' "$password" | sudo bash -lc 'set -euo pipefail; source /etc/app.env; app reset --password-stdin'
'@
($script -replace "`r`n", "`n") | ssh my-host bash -s -- $pw
```

If the remote script has `trap` cleanup, write it as a local `.sh` file with LF
line endings, upload it, then run `ssh my-host bash /tmp/script.sh`.

## 4c. Encoding And Line Endings In Unix-Bound Payloads

Symptoms:

- `command not found` where the command looks valid.
- Error text includes a hidden carriage return such as `sort\r`.
- Linux tools see paths or command names with a trailing `\r`.
- A script begins with a BOM or arrives as UTF-16 instead of UTF-8.
- Non-ASCII source text changes while crossing PowerShell, SSH, and bash.
- `git apply`, `patch`, `sed`, `awk`, or a compiler rejects generated text
  that looked valid in PowerShell.

Common cause:

PowerShell generated a script, patch, stdin payload, or temporary file with
Windows CRLF, a BOM, or a version-dependent default encoding and sent it to a
Unix or strict text tool unchanged.

Safer patterns:

```powershell
($script -replace "`r`n", "`n") | ssh my-host bash -s
```

```powershell
$scriptLf = $script -replace "`r`n", "`n"
[IO.File]::WriteAllText($scriptPath, $scriptLf, [Text.UTF8Encoding]::new($false))
scp $scriptPath my-host:/tmp/script.sh
ssh my-host bash /tmp/script.sh
```

Normalize line endings before piping or uploading scripts, patches, or other
generated text for Unix tools. When exact bytes, control characters, or several
text encodings are involved, base64-encode the payload, decode it in the target
layer, and keep the encoded value out of logs if it contains secrets.

## 4d. Remote Search Regexes In Inline SSH

Symptoms:

- Local PowerShell reports a regex branch as an unknown term or module.
- `ParserError` points at `|`, `()`, or quotes inside a remote `grep`,
  `git grep`, or `rg` pattern.

Common cause:

```powershell
ssh my-host "cd /srv/app && grep -R \"Foo\|Bar\|baz()\" -n src | head -n 50"
```

Backslash does not escape nested double quotes for PowerShell, so the local
PowerShell layer can parse pieces of the remote regex before OpenSSH sends it.

Safer patterns:

For a tiny command with no local interpolation, make the whole remote command
one local single-quoted argument:

```powershell
ssh my-host 'cd /srv/app && grep -RInE -- "Foo|Bar|baz\(\)" src | head -n 50'
```

For anything longer, use the stdin script pattern from section 4 and bind the
regex inside remote bash.

## 5. PATH Or Packaged Tool Resolution

Symptoms:

- `Program 'rg.exe' failed to run: Access is denied`
- `The term 'pnpm' is not recognized`
- `The term '...\node.exe' is not recognized`
- A tool works in one terminal but not inside the agent.
- The command resolves to a packaged app or WindowsApps location.
- A hard-coded bundled runtime path no longer exists after a plugin or app update.

Safer pattern:

```powershell
Get-Command rg | Select-Object Source,Version
where.exe rg
rg --version
```

Install tools in a normal user or system directory and ensure that directory precedes packaged app shims in PATH.

For bundled runtimes, discover the current executable before invoking it:

```powershell
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw "node was not found on PATH" }
& $node.Source --version
```

For package-manager commands, verify the tool before diagnosing the project:

```powershell
$pnpm = Get-Command pnpm -ErrorAction SilentlyContinue
if (-not $pnpm) { throw 'pnpm was not found; use the repo package manager or enable corepack first' }
& $pnpm.Source --version
```

Do not assume a cached plugin path is stable across app updates.

## 5a. Native Batch Toolchain Boundaries

Symptoms:

- A command arrives as `=...\toolchain.bat` or `=` and PowerShell says the term
  is not recognized.
- A compiler or native tool is installed, but build commands still cannot find
  it on PATH.
- A batch setup script appears to run, but the environment change is not visible
  to the next PowerShell command.

Common causes:

```powershell
pwsh -NoProfile -Command "$devCmd = $env:DEV_CMD_PATH; cmd.exe /c call $devCmd && cargo test"
```

```powershell
& $env:DEV_CMD_PATH
cargo test
```

The first command lets an outer PowerShell expand variables before the nested
process sees them. The second calls a `.bat` file in a child process, so PATH
changes do not persist in the parent PowerShell session.

Safer pattern:

```powershell
$devCmd = $env:DEV_CMD_PATH
if (-not $devCmd) { throw 'Set DEV_CMD_PATH to the batch file path first' }
cmd.exe /d /c "call ""$devCmd"" && cargo test"
```

Keep discovery of the batch file in PowerShell, then run dependent native
commands inside the same `cmd.exe /d /c` payload. If the payload becomes long,
write a small `.cmd` or `.ps1` wrapper instead of adding more quote layers.

## 6. Long Command Strings And Large Patches

Symptoms:

- `The command line is too long.`
- Large inline patches fail before the target tool starts.

Safer patterns:

- Prefer small `apply_patch` hunks.
- Split changes by file and by behavior.
- Put large generated content into a temporary script or file, then invoke it with a short command.

```powershell
pwsh -NoProfile -File .\apply-large-change.ps1
```

## 7. Script Execution Policy

Symptoms:

- `cannot be loaded because running scripts is disabled on this system`
- `PSSecurityException`
- Functions are missing because a dot-sourced script failed to load.

Safer pattern:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1
```

Use process-scoped policy for the command instead of asking the user to weaken the machine policy.

## 7a. Host Safety Policy Is Not Execution Policy

Symptoms:

- The command runner reports `blocked by policy` or `rejected` before
  PowerShell executes the command.
- Adding `-ExecutionPolicy Bypass` changes nothing.
- Rewriting the same deletion with arrays, another shell, or alternate APIs is
  also rejected.

These are host safety decisions, not PowerShell script execution policy.

Safer pattern:

- Stop retrying semantically equivalent destructive commands.
- Prove exact targets with a read-only command, then use a supported operation
  with literal targets if one is available.
- Use `apply_patch` for scoped text-file changes when appropriate.
- If no allowed operation exists, leave the artifact in place and report it.

Do not switch shells, hide the target, or call lower-level filesystem APIs to
evade the host policy.

## 8. Reserved And Automatic Variables

Symptoms:

- `Cannot overwrite variable Host because it is read-only or constant.`
- `Cannot overwrite variable PID because it is read-only or constant.`
- A collection becomes a regex match table after `-match`.
- Unexpected values appear in `$input`, `$error`, `$matches`, `$host`, or
  `$PID`.

Avoid using these names for ordinary variables:

- `$Host` / `$host`
- `$Matches` / `$matches`
- `$Input` / `$input`
- `$Error` / `$error`
- `$PID`

Use specific names such as `$hostName`, `$processId`, `$matchRecords`, or
`$inputText`.

## 8a. Variables Followed By Punctuation

Symptoms:

- `Variable reference is not valid. ':' was not followed by a valid variable name character.`
- A string such as `$path:` or `$reqId:` fails before the command reaches the
  target tool.
- A here-string that mixes status labels and variables stops with a
  `ParserError`.

Common cause:

```powershell
$name = 'request'
$value = 'ok'
"$name: $value"
```

Inside a double-quoted string or expandable here-string, PowerShell treats the
colon as part of scoped-variable syntax unless the variable boundary is
explicit.

Safer patterns:

```powershell
"${name}: $value"
```

```powershell
'{0}: {1}' -f $name, $value
```

Use the same rule when punctuation follows a variable before JSON, Markdown,
HTTP headers, log labels, or generated command text.

## 9. `curl`, `curl.exe`, `Invoke-WebRequest`, And Schannel

Symptoms:

- `curl: (35) schannel: next InitializeSecurityContext failed`
- `curl: (35) schannel: failed to receive handshake`
- `CRYPT_E_REVOCATION_OFFLINE`
- `Invoke-WebRequest -Method Head` disagrees with another probe.
- `The term 'true' is not recognized` when a supposed remote `curl ... || true` probe runs.

Safer patterns:

- Use `curl.exe` when you need the native curl binary.
- Use `Invoke-WebRequest` when you intentionally want the PowerShell cmdlet.
- Cross-check suspicious HTTPS failures from Windows with a remote Linux probe,
  browser, or service logs before declaring the service down.

When probing from remote Linux, do not embed `curl ... || true` inside a
fragile `ssh "bash -lc '...'"` one-liner. Send a script:

```powershell
$script = @'
set -euo pipefail
code="$(curl -sS -o /tmp/probe.out -w '%{http_code}' https://example.com/health || true)"
printf '%s\n' "$code"
cat /tmp/probe.out 2>/dev/null || true
'@
($script -replace "`r`n", "`n") | ssh my-host bash -s
```

If PowerShell reports `The term 'true' is not recognized`, local PowerShell parsed the bash fallback.

## 10. Missing Bash Or WSL

Symptoms:

- `/bin/bash` is not available from the Windows environment.
- A bash wrapper fails although the underlying validation is just file/text checks.

Safer pattern:

- Confirm `bash` availability before relying on bash scripts.
- If the script only checks files or text, reproduce the same assertions in PowerShell.
- Do not report a project failure when only the shell wrapper is unavailable.

## 11. Unsafe Process Cleanup

Symptoms:

- Cleanup kills the active shell or agent.
- `Stop-Process -Force` is used with broad `CommandLine -like` filters.
- `Access to the path '...\postmaster.pid' is denied`
- `Access is denied` when removing temp, database, or PID files.

Safer pattern:

- Save the root PID when starting a local service stack.
- Enumerate only descendants of that PID.
- Exclude the current PowerShell process, the agent process, and their parent chain.
- Stop specific descendants, not every process matching a project name.
- For locked files, identify the owner process first. Treat stale database and
  temp directories as possible file-lock residue before changing ACLs or
  deleting broadly.

## 11a. Long-Running Local Services And Smoke Tests

Symptoms:

- A foreground server command ends with `command timed out`.
- No PID file or log file is written even though the wrapper attempted to start
  a server and poll readiness in one command.
- A recorded PID differs from the process that owns the listening port.
- A later health probe succeeds even though the first command timed out.

Common causes:

```powershell
& .\app-server.exe
```

```powershell
$proc = Start-Process -FilePath .\app-server.exe -PassThru
Set-Content -LiteralPath .\run\app.pid -Value $proc.Id
for ($i = 0; $i -lt 30; $i++) {
  Invoke-WebRequest -Uri $env:APP_HEALTH_URL -TimeoutSec 2
}
```

The first command may simply be a healthy server running until the tool timeout.
The second combines launch, polling, logging, and cleanup state in one fragile
step, which makes it hard to tell whether PowerShell, the executable, or the
readiness probe is stuck. Some servers also spawn a child process that owns the
listening port, so the PID returned by `Start-Process` is not always enough for
cleanup.

Safer pattern:

```powershell
$pidPath = Join-Path $env:TEMP 'app-smoke.pid'
$proc = Start-Process -FilePath .\app-server.exe -WorkingDirectory (Get-Location).Path -WindowStyle Hidden -PassThru
Set-Content -LiteralPath $pidPath -Value $proc.Id
"started root pid=$($proc.Id)"
```

Then probe readiness separately:

```powershell
try {
  $response = Invoke-WebRequest -Uri $env:APP_HEALTH_URL -UseBasicParsing -TimeoutSec 5
  "status=$($response.StatusCode)"
} catch {
  "request-failed=$($_.Exception.Message)"
}
```

Then verify the actual listener before cleanup:

```powershell
Get-NetTCPConnection -LocalPort $env:APP_PORT -State Listen -ErrorAction SilentlyContinue |
  Select-Object LocalAddress, LocalPort, State, OwningProcess
```

If the recorded root PID and listener owner differ, inspect the process tree
before stopping anything. Cleanup should target the verified process or
descendants, not a broad process-name filter.

## 11b. Long-Running Remote Jobs And SSH Timeouts

Symptoms:

- A local SSH command times out while the remote build keeps running.
- Retrying starts a second build because the first job was never checked.
- The remote process survives, but its final exit code is lost.
- A background command still holds the SSH session open.

Common cause:

The remote command was only suffixed with `&`, leaving stdin, stdout, or stderr
attached to SSH. The local timeout then says nothing about remote completion.

Safer pattern:

```powershell
$remoteScript = @'
set -euo pipefail
cd "$1"

pid_file=.agent-build.pid

if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
  printf 'already-running pid=%s\n' "$(cat "$pid_file")"
  exit 0
fi

rm -f .agent-build.status
nohup bash -c '
  set +e
  ./build.sh >.agent-build.log 2>&1
  rc=$?
  printf "%s\n" "$rc" >.agent-build.status.tmp
  mv .agent-build.status.tmp .agent-build.status
' </dev/null >/dev/null 2>&1 &

printf '%s\n' "$!" >"$pid_file"
printf 'started pid=%s\n' "$!"
'@
($remoteScript -replace "`r`n", "`n") | ssh my-host bash -s -- /srv/app
```

Probe the PID, status file, and log with a separate read-only command. Do not
start another job until the prior PID is gone or the saved status proves it
finished. A local timeout remains inconclusive unless the remote state is
checked.

## 11c. Local Batch Timeouts And Closed Pipes

Symptoms:

- A finite generator or indexer reaches the command timeout and reports
  `EPIPE`, broken pipe, or that the pipe is being closed.
- The producer reports a pipe error after the downstream tool rejects its
  input or exits early.
- A child process or partially written output remains after the command runner
  has returned.

Common causes:

- The command runner closes its output capture pipe at timeout while the native
  process is still writing.
- The downstream CLI does not accept stdin, rejects `-`, or fails before
  consuming all producer output.
- A retry begins before the prior process tree or output state is checked.

Safer pattern:

- Confirm from `--help` or documentation that the downstream tool accepts
  stdin before building a native pipeline.
- When both native exit codes matter, use the producer's output-file option or
  a temporary file handoff instead of an opaque pipeline.
- After timeout, inspect the recorded root process and descendants, then check
  logs and output timestamps, sizes, and structure.
- Do not retry until the prior process is gone or its persisted state proves
  completion.

A producer-side broken-pipe message can be secondary evidence of downstream or
transport failure. It does not identify the root cause by itself.

## 12. Wildcards And Pathspecs

Symptoms:

- `git diff`, `rg`, or another native tool receives different paths than expected.
- PowerShell expands a wildcard before the target tool can apply its own glob rules.

Safer patterns:

- Prefer explicit paths for small sets.
- Use the target tool's own glob/pathspec options when possible.
- Quote arguments intentionally and verify with a read-only command before destructive operations.

For delete, move, stop, deploy, or cleanup commands, first print the exact
targets with the same filter logic. Keep enumeration and action in the same
shell, and prefer `-LiteralPath` for PowerShell filesystem operations.

`-LiteralPath` is not universal. Confirm the cmdlet's parameters with
`Get-Command <cmdlet> -Syntax`; for example, `New-Item` accepts `-Path`, not
`-LiteralPath`. Resolve and validate the parent directory first when a creation
path contains wildcard characters.

## 13. OpenSSH Argument Parsing From PowerShell

Symptoms:

- An OpenSSH command says an option requires an argument even though an empty argument was supplied.
- PowerShell rewrites quotes around flags such as `-N ""`.

Safer pattern:

```powershell
ssh-keygen --% -q -t ed25519 -f C:\path\to\key -C "comment" -N ""
```

Use PowerShell stop-parsing `--%` only for native Windows commands where passing
the rest verbatim is the goal. Do not use it for commands that need PowerShell
variable expansion after that point.

## 13a. Git Auth And Environment Assignments

Symptoms:

- `=0: The term '=0' is not recognized`
- `Permission denied (publickey)` from `git push`, `git fetch`, or
  `git ls-remote`
- A command works in Git Bash but fails when pasted into PowerShell.

Common causes:

```powershell
GIT_TERMINAL_PROMPT=0 git ls-remote origin
```

```powershell
pwsh -NoProfile -Command "GIT_TERMINAL_PROMPT='0'; git push origin HEAD"
```

PowerShell does not support bash-style one-command environment assignment. An
SSH `Permission denied (publickey)` error is also an authentication failure, not
proof that the remote repository or branch is missing.

Safer pattern:

```powershell
$oldPrompt = $env:GIT_TERMINAL_PROMPT
try {
  $env:GIT_TERMINAL_PROMPT = '0'
  git ls-remote origin
} finally {
  $env:GIT_TERMINAL_PROMPT = $oldPrompt
}
```

If SSH auth fails, verify the configured remote and credential path explicitly
before switching protocols or concluding that the repository is unavailable.

## 14. Parallel PowerShell Startup And Short Timeouts

Symptoms:

- Several simple commands such as `Get-Content` or `git status` time out in the
  same parallel batch.
- Retrying a smaller command succeeds without changing the repository.
- The failure has no project error output, only `command timed out`.

Common cause:

PowerShell process startup, antivirus scanning, disk pressure, or a busy
workspace can make several simultaneous short-timeout probes expire together.
That is a measurement failure, not proof that every file read or git command is
broken.

Safer patterns:

- Retry the minimum read-only command first.
- Increase the timeout for large files, cold workspaces, or first commands in a
  new session.
- Split broad context gathering into smaller batches and keep outputs bounded
  with `Select-Object -First`, `-TotalCount`, or targeted `rg` searches.
- Report the timeout as an environment or shell startup uncertainty until a
  focused retry confirms a real project failure.
