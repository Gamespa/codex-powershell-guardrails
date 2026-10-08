Set-StrictMode -Version Latest

function Invoke-EvaluationProcess {
  param([string]$Executable, [string[]]$Arguments, [string]$Prompt,
    [ValidateRange(1, 2147483)][int]$TimeoutSeconds)
  $info = [Diagnostics.ProcessStartInfo]::new($Executable)
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardInput = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
  $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
  foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $started = $false
  $stdoutTask = $null
  $stderrTask = $null
  $result = [ordered]@{ ExitCode = $null; TimedOut = $false; ElapsedSeconds = 0; Stdout = ''; Stderr = ''; Error = $null }
  try {
    $started = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    # Include stdin delivery in the deadline: a child may never consume its input.
    $writeTask = $process.StandardInput.WriteLineAsync($Prompt)
    $remaining = [math]::Max(0, $TimeoutSeconds * 1000 - [int]$watch.ElapsedMilliseconds)
    if (-not $writeTask.Wait($remaining)) { $result.TimedOut = $true }
    if (-not $result.TimedOut) {
      $process.StandardInput.Close()
      $remaining = [math]::Max(0, $TimeoutSeconds * 1000 - [int]$watch.ElapsedMilliseconds)
      $result.TimedOut = -not $process.WaitForExit($remaining)
    }
  } catch {
    $result.Error = $_.Exception.Message
  } finally {
    try {
      if ($started) {
        if (-not $process.HasExited) { $process.Kill($true) }
        $process.WaitForExit()
        $result.ExitCode = $process.ExitCode
        if ($null -ne $stdoutTask) { $result.Stdout = $stdoutTask.GetAwaiter().GetResult() }
        if ($null -ne $stderrTask) { $result.Stderr = $stderrTask.GetAwaiter().GetResult() }
      }
    } finally {
      $process.Dispose()
      $watch.Stop()
      $result.ElapsedSeconds = [math]::Round($watch.Elapsed.TotalSeconds, 1)
    }
  }
  [pscustomobject]$result
}

Export-ModuleMember -Function Invoke-EvaluationProcess
