param([string]$ModulePath, [string]$ModelWorker, [string]$OutputRoot)
$ErrorActionPreference = 'Stop'
Import-Module $ModulePath
$result = Invoke-EvaluationProcess -Executable (Join-Path $PSHOME 'pwsh.exe') -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $ModelWorker, '-Scenario', 'timeout') -Prompt '' -TimeoutSeconds 3 -StdoutPath (Join-Path $OutputRoot 'live.jsonl') -StderrPath (Join-Path $OutputRoot 'live.stderr')
[IO.File]::WriteAllText((Join-Path $OutputRoot 'process-result.json'), ($result | ConvertTo-Json))
