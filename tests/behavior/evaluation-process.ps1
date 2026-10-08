Import-Module (Join-Path $repositoryRoot 'scripts/lib/process.psm1') -Force
$worker = Join-Path $repositoryRoot 'tests/fixtures/model-worker.ps1'
$baseArguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $worker)
$unicodePrompt = 'input with spaces "quoted" ' + [char]0x4F60 + [char]0x597D
$result = Invoke-EvaluationProcess -Executable $childShell -Arguments ($baseArguments + @('-Scenario', 'echo')) -Prompt $unicodePrompt -TimeoutSeconds 10
Assert-Behavior ($result.ExitCode -eq 0 -and $result.Stdout -ceq ($unicodePrompt + [Environment]::NewLine) -and -not $result.Error) 'Process stdin text or Unicode changed.'
$result = Invoke-EvaluationProcess -Executable $childShell -Arguments ($baseArguments + @('-Scenario', 'streams')) -Prompt '' -TimeoutSeconds 10
Assert-Behavior ($result.ExitCode -eq 0 -and $result.Stdout.Length -eq 131072 -and $result.Stderr.Length -eq 131072) 'Concurrent output draining lost data or deadlocked.'
$result = Invoke-EvaluationProcess -Executable $childShell -Arguments ($baseArguments + @('-Scenario', 'failure')) -Prompt '' -TimeoutSeconds 10
Assert-Behavior ($result.ExitCode -eq 17 -and $result.Stderr.Contains('fixture diagnostic') -and $result.Stdout.Contains('turn.completed')) 'Nonzero exit lost diagnostics.'
$result = Invoke-EvaluationProcess -Executable $childShell -Arguments ($baseArguments + @('-Scenario', 'timeout')) -Prompt '' -TimeoutSeconds 2
Assert-Behavior ($result.TimedOut -and $result.ElapsedSeconds -lt 10 -and $result.Stderr.Contains('fixture diagnostic')) 'Timeout did not retain partial output or finish within its bound.'
$result = Invoke-EvaluationProcess -Executable $childShell -Arguments ($baseArguments + @('-Scenario', 'blocked-input')) -Prompt ('x' * 1048576) -TimeoutSeconds 2
Assert-Behavior ($result.TimedOut -and $result.ElapsedSeconds -lt 10) 'Stalled stdin ignored the process deadline.'
$result = Invoke-EvaluationProcess -Executable (Join-Path $fixtureRoot 'missing.exe') -Arguments @() -Prompt '' -TimeoutSeconds 1
Assert-Behavior ($null -eq $result.ExitCode -and $result.Error -and -not $result.TimedOut) 'Startup failure was not returned as diagnostic data.'
