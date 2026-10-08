Set-StrictMode -Version Latest

function Invoke-EvaluationProcess {
  param([string]$Executable, [string[]]$Arguments, [string]$Prompt,
    [ValidateRange(1, 2147483)][int]$TimeoutSeconds,
    [string]$StdoutPath, [string]$StderrPath,
    [ValidateRange(1, 30)][int]$CleanupTimeoutSeconds = 2)
  $info = [Diagnostics.ProcessStartInfo]::new($Executable)
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardInput = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $cleanupWatch = $null
  $started = $false
  $channels = [Collections.Generic.List[object]]::new()
  $failures = [Collections.Generic.List[string]]::new()
  $result = [ordered]@{
    ExitCode = $null; TimedOut = $false; ElapsedSeconds = 0
    Stdout = ''; Stderr = ''; Error = $null
    StdoutTruncated = $false; StderrTruncated = $false
  }
  try {
    # Stream raw bytes to files while retaining only a bounded diagnostic preview.
    foreach ($entry in @(@{ Name = 'Stdout'; Path = $StdoutPath }, @{ Name = 'Stderr'; Path = $StderrPath })) {
      $channel = [pscustomobject]@{
        Name = $entry.Name; Source = $null; Sink = $null; Pending = $null
        Buffer = [byte[]]::new(16384); Preview = [IO.MemoryStream]::new()
        Bytes = 0L; Done = $false
      }
      $channels.Add($channel)
      if ($entry.Path) {
        $channel.Sink = [IO.FileStream]::new($entry.Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
      }
    }
    $started = $process.Start()
    $channels[0].Source = $process.StandardOutput.BaseStream
    $channels[1].Source = $process.StandardError.BaseStream
    $inputBytes = [Text.Encoding]::UTF8.GetBytes($Prompt + [Environment]::NewLine)
    $inputTask = $process.StandardInput.BaseStream.WriteAsync($inputBytes, 0, $inputBytes.Length)
    $inputDone = $false
    while ($true) {
      if (-not $inputDone -and $inputTask.IsCompleted) {
        try { $null = $inputTask.GetAwaiter().GetResult() } catch { $failures.Add($_.Exception.Message) }
        $inputDone = $true
        $process.StandardInput.Dispose()
      }
      foreach ($channel in $channels) {
        if ($channel.Done) { continue }
        try {
          if (-not $channel.Pending) {
            $channel.Pending = $channel.Source.ReadAsync($channel.Buffer, 0, $channel.Buffer.Length)
          }
          if (-not $channel.Pending.IsCompleted) { continue }
          $count = $channel.Pending.GetAwaiter().GetResult()
          $channel.Pending = $null
          if ($count -eq 0) { $channel.Done = $true; continue }
          if ($channel.Sink) {
            $channel.Sink.Write($channel.Buffer, 0, $count)
            $channel.Sink.Flush()
          }
          $previewCount = [math]::Min($count, 65536 - [int]$channel.Preview.Length)
          if ($previewCount -gt 0) { $channel.Preview.Write($channel.Buffer, 0, $previewCount) }
          $channel.Bytes += $count
        } catch {
          $failures.Add($_.Exception.Message)
          $channel.Done = $true
        }
      }
      $exited = $process.HasExited
      $drained = @($channels | Where-Object { -not $_.Done }).Count -eq 0
      if ($exited -and $drained -and $inputDone) { break }
      if (-not $cleanupWatch -and ($exited -or $failures.Count -or $watch.Elapsed.TotalSeconds -ge $TimeoutSeconds)) {
        $cleanupWatch = [Diagnostics.Stopwatch]::StartNew()
        if (-not $exited) {
          $result.TimedOut = $watch.Elapsed.TotalSeconds -ge $TimeoutSeconds
          try { $process.Kill($true) } catch { $failures.Add($_.Exception.Message) }
        }
      }
      if ($cleanupWatch -and $cleanupWatch.Elapsed.TotalSeconds -ge $CleanupTimeoutSeconds) {
        $result.TimedOut = $true
        $failures.Add('Process cleanup/output drain exceeded its deadline; inspect retained logs and any surviving descendants.')
        break
      }
      [Threading.Thread]::Sleep(10)
    }
    if ($process.HasExited) { $result.ExitCode = $process.ExitCode }
  } catch {
    $failures.Add($_.Exception.Message)
    if ($started -and -not $process.HasExited) {
      try { $process.Kill($true) } catch { $failures.Add($_.Exception.Message) }
    }
  } finally {
    # Closing the parent read handles cancels pending reads even if a descendant
    # inherited a pipe. Never wait indefinitely for EOF or re-resolve a stale PID.
    foreach ($channel in $channels) {
      $result[$channel.Name] = [Text.Encoding]::UTF8.GetString($channel.Preview.ToArray())
      $result[$channel.Name + 'Truncated'] = $channel.Bytes -gt $channel.Preview.Length
      foreach ($resource in @($channel.Source, $channel.Sink, $channel.Preview)) {
        if ($null -ne $resource) {
          try { $resource.Dispose() } catch { $failures.Add($_.Exception.Message) }
        }
      }
    }
    try { $process.Dispose() } catch { $failures.Add($_.Exception.Message) }
    $watch.Stop()
    $result.ElapsedSeconds = [math]::Round($watch.Elapsed.TotalSeconds, 1)
    if ($failures.Count) { $result.Error = $failures -join ' | ' }
  }
  [pscustomobject]$result
}

Export-ModuleMember -Function Invoke-EvaluationProcess
