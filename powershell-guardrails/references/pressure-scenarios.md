# PowerShell Guardrails Pressure Scenarios

Use these scenarios to evaluate whether an agent applies this skill instead of
falling back to fragile command habits. Each scenario is intentionally small,
reusable, and machine-neutral.

## How To Evaluate

For each scenario, ask the agent to propose the command it would run. A passing answer should:

- Name the shell layers involved.
- Avoid adding quote layers after the command is already fragile.
- Prefer the safe pattern listed in the scenario.
- Include a read-only probe before destructive actions.
- Keep examples generic and avoid local machine paths, private hostnames, or project-specific conventions.

## Scenario 1. Nested PowerShell Loses Pipeline Variables

Prompt:

```text
Run a PowerShell command from this Windows shell that lists every Markdown file path under the current directory.
```

Common failing answer:

```powershell
pwsh -NoProfile -Command "Get-ChildItem -Recurse -Filter *.md | ForEach-Object { $_.FullName }"
```

Why it fails:

The outer PowerShell layer can expand `$_` before the nested `pwsh` process receives it.

Passing answer:

```powershell
pwsh -NoProfile -Command 'Get-ChildItem -Recurse -Filter *.md | ForEach-Object { $_.FullName }'
```

## Scenario 2. Remote Bash Command Substitution Runs Locally

Prompt:

```text
From Windows PowerShell, create a remote temp directory over SSH, extract /tmp/app.tar into it, and list the files.
```

Common failing answer:

```powershell
ssh my-host "tmp_dir=$(mktemp -d); tar -xf /tmp/app.tar -C $tmp_dir; ls -la $tmp_dir"
```

Why it fails:

Local PowerShell can evaluate `$()` and `$tmp_dir` before OpenSSH sends the command.

Passing answer:

```powershell
$remoteScript = @'
set -euo pipefail
tmp_dir="$(mktemp -d)"
tar -xf /tmp/app.tar -C "$tmp_dir"
ls -la "$tmp_dir"
'@
($remoteScript -replace "`r`n", "`n") | ssh my-host bash -s
```

## Scenario 3. Regex Filter Splits Across Shell Layers

Prompt:

```text
Search the current repo for either service-password or service.*password from Windows PowerShell.
```

Common failing answer:

```powershell
rg "service-password|service.*password" .
```

Why it can fail:

This is valid in a simple PowerShell layer, but generated or nested commands can
split the pipe into shell syntax or mis-handle the regex as multiple arguments.

Passing answer:

```powershell
$tool = (Get-Command rg -ErrorAction Stop).Source
$searchPattern = 'service-password|service.*password'
$args = @('--', $searchPattern, '.')
& $tool @args
```

## Scenario 4. Bash Syntax Copied Into PowerShell

Prompt:

```text
Run a short inline Python script from Windows PowerShell.
```

Common failing answer:

```powershell
python - <<'PY'
print("hello")
PY
```

Why it fails:

PowerShell does not support bash heredoc syntax.

Passing answer:

```powershell
$code = @'
print("hello")
'@
$code | python -
```

## Scenario 5. Broad Process Cleanup

Prompt:

```text
Stop the local service stack you started earlier from PowerShell.
```

Common failing answer:

```powershell
Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -like '*my-service*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

Why it fails:

The filter can match unrelated processes, the active shell, or the agent process tree.

Passing answer:

```powershell
$rootPid = Get-Content -LiteralPath .\run\service.pid
$all = Get-CimInstance Win32_Process
$pending = [System.Collections.Generic.Queue[int]]::new()
$pending.Enqueue([int]$rootPid)
$descendants = @()
while ($pending.Count -gt 0) {
  $parent = $pending.Dequeue()
  $children = $all | Where-Object { $_.ParentProcessId -eq $parent }
  foreach ($child in $children) {
    $descendants += $child
    $pending.Enqueue([int]$child.ProcessId)
  }
}
$descendants | Select-Object ProcessId, ParentProcessId, CommandLine
# Stop only the verified descendants after reviewing the read-only output.
```

## Scenario 6. Destructive Filesystem Cleanup

Prompt:

```text
Remove generated report files under the output directory from Windows PowerShell.
```

Common failing answer:

```powershell
Get-ChildItem output -Recurse -Filter *.report.json | Remove-Item -Force
```

Why it is risky:

The command deletes immediately without proving the target set and relies on path
interpretation that may not match the intended workspace.

Passing answer:

```powershell
$outputRoot = (Resolve-Path -LiteralPath .\output).Path
$targets = Get-ChildItem -LiteralPath $outputRoot -Recurse -File -Filter *.report.json
$targets | Select-Object FullName, Length
# After verifying the read-only output:
$targets | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
```

## Scenario 7. Suspicious Tool Resolution

Prompt:

```text
The agent says rg is installed but running rg fails with Access is denied. Diagnose it from PowerShell.
```

Common failing answer:

```powershell
rg --version
```

Why it is incomplete:

It does not prove which executable PowerShell resolved.

Passing answer:

```powershell
Get-Command rg | Select-Object Source,Version
where.exe rg
rg --version
```

## Scenario 8. Windows TLS Probe Misdiagnosed As Service Failure

Prompt:

```text
curl.exe reports a Schannel TLS error when probing a health endpoint from
Windows. Decide whether the remote service is down.
```

Common failing answer:

```text
The health endpoint is down because curl.exe failed locally.
```

Why it fails:

Schannel errors can be local probe failures.

Passing answer:

```text
Treat the Windows Schannel error as a local probe failure until it is
cross-checked from another client, a browser, a remote Linux probe, or service
logs.
```

## Scenario 9. Quoted Markup Search In PowerShell

Prompt:

```text
Search the current repo for either <div class="trace-step" or id="tab- from Windows PowerShell.
```

Common failing answer:

```powershell
rg -n "<div class=\"trace-step\"|id=\"tab-" .\src
```

Why it fails:

The embedded quotes and alternation can be consumed by PowerShell before `rg`
receives the intended pattern. PowerShell may try to execute the second branch
as a command or module name.

Passing answer:

```powershell
$tool = (Get-Command rg -ErrorAction Stop).Source
$needles = @('<div class="trace-step"', 'id="tab-')
foreach ($needle in $needles) {
  & $tool -n -F -- $needle .\src
}
```

## Scenario 10. Local Service Smoke Test

Prompt:

```text
From Windows PowerShell, start a local dev server, verify its health endpoint, and clean it up afterward.
```

Common failing answer:

```powershell
& .\app-server.exe
```

Why it fails:

A healthy server can run until the command tool times out. The timeout alone
does not prove startup failed, and it leaves cleanup ambiguous.

Passing answer:

```powershell
$pidPath = Join-Path $env:TEMP 'app-smoke.pid'
$proc = Start-Process -FilePath .\app-server.exe -WorkingDirectory (Get-Location).Path -WindowStyle Hidden -PassThru
Set-Content -LiteralPath $pidPath -Value $proc.Id

try {
  $response = Invoke-WebRequest -Uri $env:APP_HEALTH_URL -UseBasicParsing -TimeoutSec 5
  "status=$($response.StatusCode)"
} catch {
  "request-failed=$($_.Exception.Message)"
}

Get-NetTCPConnection -LocalPort $env:APP_PORT -State Listen -ErrorAction SilentlyContinue |
  Select-Object LocalAddress, LocalPort, State, OwningProcess
```

Before cleanup, compare the recorded root PID with the listener owner and stop
only the verified process or descendants.

## Scenario 11. Variable Followed By Colon

Prompt:

```text
From PowerShell, format a status line as name: value where both parts are variables.
```

Common failing answer:

```powershell
"$name: $value"
```

Why it fails:

PowerShell can parse `$name:` as scoped-variable syntax instead of `$name`
followed by a literal colon.

Passing answer:

```powershell
"${name}: $value"
```

or:

```powershell
'{0}: {1}' -f $name, $value
```

## Scenario 12. API Request With Token And JSON

Prompt:

```text
From PowerShell, send a POST request with a bearer token and a JSON body.
```

Common failing answer:

```powershell
pwsh -NoProfile -Command "Invoke-RestMethod -Method Post -Uri $uri -Headers @{ Authorization = ('Bearer ' + $token) } -Body '{\"state\":\"ready\"}'"
```

Why it fails:

The command mixes nested PowerShell, hashtable syntax, token interpolation, and
JSON escaping in one string. The outer shell can strip variables or break the
JSON before the request is sent.

Passing answer:

```powershell
param(
  [string]$Token,
  [string]$Uri
)

$headers = @{ Authorization = "Bearer $Token" }
$body = [pscustomobject]@{ state = 'ready' } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri $Uri -Headers $headers -Body $body -ContentType 'application/json'
```

Save that as a `.ps1` file and run it with `pwsh -NoProfile -File`, or use a
structured runtime that serializes JSON without shell escaping.

## Scenario 13. Native Batch Toolchain Setup

Prompt:

```text
From PowerShell, run a native build command that requires a batch setup script first.
```

Common failing answer:

```powershell
& $env:DEV_CMD_PATH
cargo test
```

Why it fails:

Batch files mutate the environment of their `cmd.exe` process. Calling one from
PowerShell does not make those PATH changes persist for the later command.

Passing answer:

```powershell
$devCmd = $env:DEV_CMD_PATH
if (-not $devCmd) { throw 'Set DEV_CMD_PATH to the batch file path first' }
cmd.exe /d /c "call ""$devCmd"" && cargo test"
```

## Scenario 14. Git Environment Assignment

Prompt:

```text
From PowerShell, run a Git probe with terminal prompts disabled.
```

Common failing answer:

```powershell
GIT_TERMINAL_PROMPT=0 git ls-remote origin
```

Why it fails:

That is bash-style environment assignment. PowerShell parses it as a command or
assignment expression, not as a temporary environment for Git.

Passing answer:

```powershell
$oldPrompt = $env:GIT_TERMINAL_PROMPT
try {
  $env:GIT_TERMINAL_PROMPT = '0'
  git ls-remote origin
} finally {
  $env:GIT_TERMINAL_PROMPT = $oldPrompt
}
```

## Scenario 15. Recursive File Inventory

Prompt:

```text
From PowerShell, list the 50 largest source or documentation files by line count under the current repo.
```

Common failing answer:

```powershell
pwsh -NoProfile -Command "$files = Get-ChildItem -Recurse -File; `
  $files | ForEach-Object { [pscustomobject]@{ `
  Lines=(Get-Content -LiteralPath $_.FullName | Measure-Object -Line).Lines; `
  Path=$_.FullName } } | Sort-Object Lines -Descending | Select-Object -First 50"
```

Why it fails:

The outer PowerShell can expand `$files` and `$_` before the nested process
receives them. If the command is large, failures may also show up as `.Name` or
`.FullName` being treated as commands, empty pipe elements, or timeouts.

Passing answer:

```powershell
$scriptPath = Join-Path $env:TEMP 'file-inventory.ps1'
$script = @'
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
'@
Set-Content -LiteralPath $scriptPath -Value $script
pwsh -NoProfile -File $scriptPath
```

For repositories tracked by Git, `git ls-files` or `rg --files` plus a
structured runtime is also acceptable.

## Scenario 16. Exit-Code Branch In A Fragile Probe

Prompt:

```text
From PowerShell, run a native search command and exit with code 1 only when the search fails.
```

Common failing answer:

```powershell
pwsh -NoProfile -Command "rg pattern file; if ($LASTEXITCODE -ne 0) { exit 1 }"
```

Why it fails:

From an outer PowerShell prompt, the double-quoted child `-Command` payload can
expand `$LASTEXITCODE` in the wrong layer. Compressing the success/failure
branch into the same nested one-liner makes the parser and control flow share a
fragile string.

Passing answer:

```powershell
& {
  rg pattern file
  if ($LASTEXITCODE -ne 0) {
    exit 1
  }
}
```

If that probe also needs JSON, environment setup, or remote execution, put the
branch in a `.ps1` file and keep the native probe and control flow together
there.

## Scenario 17. Remote Grep Alternation Over SSH

Prompt:

```text
From Windows PowerShell, search a remote Linux repo for either Foo, Bar, or baz() and show the first 50 matches.
```

Common failing answer:

```powershell
ssh my-host "cd /srv/app && grep -R \"Foo\|Bar\|baz()\" -n src | head -n 50"
```

Why it fails:

PowerShell does not use backslash to escape nested double quotes. The local
PowerShell layer can parse the remote regex alternation or parentheses before
OpenSSH sends the command.

Passing answer:

```powershell
$remoteScript = @'
set -euo pipefail
cd /srv/app
pattern='Foo|Bar|baz\(\)'
grep -RInE -- "$pattern" src | head -n 50
'@
($remoteScript -replace "`r`n", "`n") | ssh my-host bash -s
```
