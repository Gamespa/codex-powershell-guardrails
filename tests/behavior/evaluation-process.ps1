Import-Module (Join-Path $repositoryRoot 'scripts/lib/process.psm1') -Force
$worker = Join-Path $repositoryRoot 'tests/fixtures/model-worker.ps1'
$baseArguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $worker)
$unicodePrompt = 'input with spaces "quoted" ' + [char]0x4F60 + [char]0x597D
$result = Invoke-EvaluationProcess -Executable $childShell -Arguments ($baseArguments + @('-Scenario', 'echo')) -Prompt $unicodePrompt -TimeoutSeconds 10
Assert-Behavior ($result.ExitCode -eq 0 -and $result.Stdout -ceq ($unicodePrompt + [Environment]::NewLine) -and -not $result.Error) 'Process stdin text or Unicode changed.'
$stdoutPath = Join-Path $fixtureRoot 'stdout.log'
$stderrPath = Join-Path $fixtureRoot 'stderr.log'
$result = Invoke-EvaluationProcess -Executable $childShell -Arguments ($baseArguments + @('-Scenario', 'streams')) -Prompt '' -TimeoutSeconds 10 -StdoutPath $stdoutPath -StderrPath $stderrPath
Assert-Behavior ($result.ExitCode -eq 0 -and (Get-Item -LiteralPath $stdoutPath).Length -eq 131072 -and (Get-Item -LiteralPath $stderrPath).Length -eq 131072) 'Concurrent output draining lost data or deadlocked.'
Assert-Behavior ($result.Stdout.Length -eq 65536 -and $result.Stderr.Length -eq 65536 -and $result.StdoutTruncated -and $result.StderrTruncated) 'Diagnostic previews are not bounded.'
$result = Invoke-EvaluationProcess -Executable $childShell -Arguments ($baseArguments + @('-Scenario', 'failure')) -Prompt '' -TimeoutSeconds 10
Assert-Behavior ($result.ExitCode -eq 17 -and $result.Stderr.Contains('fixture diagnostic') -and $result.Stdout.Contains('turn.completed')) 'Nonzero exit lost diagnostics.'
$result = Invoke-EvaluationProcess -Executable $childShell -Arguments ($baseArguments + @('-Scenario', 'timeout')) -Prompt '' -TimeoutSeconds 2
Assert-Behavior ($result.TimedOut -and $result.ElapsedSeconds -lt 10 -and $result.Stderr.Contains('fixture diagnostic')) 'Timeout did not retain partial output or finish within its bound.'
$result = Invoke-EvaluationProcess -Executable $childShell -Arguments ($baseArguments + @('-Scenario', 'blocked-input')) -Prompt ('x' * 1048576) -TimeoutSeconds 2
Assert-Behavior ($result.TimedOut -and $result.ElapsedSeconds -lt 10) 'Stalled stdin ignored the process deadline.'
$result = Invoke-EvaluationProcess -Executable (Join-Path $fixtureRoot 'missing.exe') -Arguments @() -Prompt '' -TimeoutSeconds 1
Assert-Behavior ($null -eq $result.ExitCode -and $result.Error -and -not $result.TimedOut) 'Startup failure was not returned as diagnostic data.'

$liveInfo = [Diagnostics.ProcessStartInfo]::new($childShell)
$liveInfo.UseShellExecute = $false; $liveInfo.CreateNoWindow = $true
foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', (Join-Path $repositoryRoot 'tests/fixtures/process-worker.ps1'), '-ModulePath', (Join-Path $repositoryRoot 'scripts/lib/process.psm1'), '-ModelWorker', $worker, '-OutputRoot', $fixtureRoot)) {
  $liveInfo.ArgumentList.Add($argument)
}
$liveWorker = [Diagnostics.Process]::Start($liveInfo)
try {
  $livePath = Join-Path $fixtureRoot 'live.jsonl'
  $deadline = [Diagnostics.Stopwatch]::StartNew()
  $sawLiveOutput = $false
  while (-not $liveWorker.HasExited -and $deadline.Elapsed.TotalSeconds -lt 6) {
    if ((Test-Path -LiteralPath $livePath) -and (Get-Item -LiteralPath $livePath).Length -gt 0) { $sawLiveOutput = $true; break }
    [Threading.Thread]::Sleep(10)
  }
  Assert-Behavior ($sawLiveOutput -and -not $liveWorker.HasExited) 'Logs were buffered until process completion.'
  Assert-Behavior ($liveWorker.WaitForExit(6000) -and $liveWorker.ExitCode -eq 0) 'Streaming fixture did not finish.'
  $liveResult = Get-Content -LiteralPath (Join-Path $fixtureRoot 'process-result.json') -Raw | ConvertFrom-Json
  Assert-Behavior ($liveResult.TimedOut -and (Get-Content -LiteralPath $livePath -Raw).Contains('turn.completed')) 'Timeout failed to retain streamed logs.'
} finally {
  if (-not $liveWorker.HasExited) { $liveWorker.Kill($true); $null = $liveWorker.WaitForExit(3000) }
  $liveWorker.Dispose()
}

$identityPath = Join-Path $fixtureRoot 'pipe-child.json'
try {
  $result = Invoke-EvaluationProcess -Executable $childShell -Arguments ($baseArguments + @('-Scenario', 'hold-pipes', '-AnswerPath', $identityPath)) -Prompt '' -TimeoutSeconds 10 -CleanupTimeoutSeconds 1
  Assert-Behavior ($result.ExitCode -eq 0 -and $result.TimedOut -and $result.Error -match 'output drain' -and $result.ElapsedSeconds -lt 8) 'An inherited pipe bypassed the cleanup deadline.'
  Assert-Behavior ($result.Stdout.Contains('parent-exiting')) 'Cleanup deadline lost partial output.'
} finally {
  if (Test-Path -LiteralPath $identityPath) {
    $identity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
    $ownedChild = $null
    try { $ownedChild = [Diagnostics.Process]::GetProcessById($identity.Id) } catch [ArgumentException] { }
    if ($ownedChild) {
      try {
        if (-not $ownedChild.HasExited -and $ownedChild.StartTime.ToUniversalTime().Ticks -eq $identity.StartTime -and
            $ownedChild.MainModule.FileName -eq $identity.Executable) {
          $ownedChild.Kill($true)
          if (-not $ownedChild.WaitForExit(3000)) { throw 'Owned pipe fixture did not stop.' }
        }
      } finally { $ownedChild.Dispose() }
    }
  }
}
