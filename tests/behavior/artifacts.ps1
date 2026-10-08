Import-Module (Join-Path $repositoryRoot 'scripts/lib/artifacts.psm1') -Force
$modulePath = Join-Path $repositoryRoot 'scripts/lib/artifacts.psm1'
$workerPath = Join-Path $repositoryRoot 'tests/fixtures/artifact-worker.ps1'
$target = Join-Path $fixtureRoot 'results.json'
Write-EvaluationSnapshot $target '[{"sequence":0}]'
Write-EvaluationSnapshot $target '[{"sequence":1}]'
Assert-Behavior ((Get-Content -LiteralPath $target -Raw) -ceq '[{"sequence":1}]') 'Atomic snapshot replacement failed.'
$heldTarget = [IO.FileStream]::new($target, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
try { Assert-Throws { Write-EvaluationSnapshot $target '[{"sequence":2}]' } 'used by another process|being used|access|使用|访问' }
finally { $heldTarget.Dispose() }
Assert-Behavior ((Get-Content -LiteralPath $target -Raw) -ceq '[{"sequence":1}]') 'Failed replacement damaged the committed snapshot.'
Assert-Behavior (@(Get-ChildItem -LiteralPath $fixtureRoot -Filter '.results-*.tmp' -Force).Count -eq 0) 'Failed snapshot left a temporary file.'

foreach ($mode in @('lock', 'snapshots')) {
  $readyPath = Join-Path $fixtureRoot "$mode.ready"
  $info = [Diagnostics.ProcessStartInfo]::new($childShell)
  $info.UseShellExecute = $false; $info.CreateNoWindow = $true
  foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $workerPath, '-ModulePath', $modulePath, '-OutputRoot', $fixtureRoot, '-ReadyPath', $readyPath)) {
    $info.ArgumentList.Add($argument)
  }
  if ($mode -eq 'snapshots') { $info.ArgumentList.Add('-WriteSnapshots') }
  $worker = [Diagnostics.Process]::Start($info)
  try {
    $deadline = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $readyPath) -and -not $worker.HasExited -and $deadline.Elapsed.TotalSeconds -lt 5) { [Threading.Thread]::Sleep(10) }
    Assert-Behavior (Test-Path -LiteralPath $readyPath) 'Artifact fixture did not become ready.'
    if ($mode -eq 'lock') {
      Assert-Throws { Open-EvaluationLock $fixtureRoot } 'Cannot acquire evaluation output lock'
      # A crashed process must release the OS lock without deleting the lock file.
      $worker.Kill($true)
      Assert-Behavior ($worker.WaitForExit(3000)) 'Lock fixture did not stop.'
      $reacquired = Open-EvaluationLock $fixtureRoot
      $reacquired.Dispose()
      Assert-Behavior (Test-Path -LiteralPath (Join-Path $fixtureRoot '.evaluation.lock')) 'Lock path disappeared after ownership release.'
    } else {
      $observed = 0
      $invalidSnapshot = $false
      while (-not $worker.HasExited -and $deadline.Elapsed.TotalSeconds -lt 8) {
        # Readers allow atomic name replacement while reading the old file handle.
        $stream = [IO.FileStream]::new($target, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $reader = [IO.StreamReader]::new($stream)
        try { $snapshot = ConvertFrom-Json -InputObject $reader.ReadToEnd() -NoEnumerate }
        finally { $reader.Dispose() }
        if ($snapshot -isnot [array] -or $snapshot.Count -ne 1 -or $snapshot[0].sequence -lt 1) { $invalidSnapshot = $true }
        $observed++
        [Threading.Thread]::Sleep(10)
      }
      Assert-Behavior (-not $invalidSnapshot) 'Reader saw a partial snapshot.'
      Assert-Behavior ($worker.HasExited -and $worker.ExitCode -eq 0 -and $observed -gt 0) 'Concurrent snapshot writer failed or stalled.'
      $snapshot = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json -NoEnumerate
      Assert-Behavior ($snapshot[0].sequence -eq 40) 'Final snapshot was not committed.'
    }
  } finally {
    if (-not $worker.HasExited) { $worker.Kill($true); $null = $worker.WaitForExit(3000) }
    $worker.Dispose()
  }
}
