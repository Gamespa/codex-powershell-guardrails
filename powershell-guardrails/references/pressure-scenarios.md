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
