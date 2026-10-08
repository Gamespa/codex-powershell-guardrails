param([string]$Scenario = 'success', [string]$AnswerPath)
$ErrorActionPreference = 'Stop'
if ($Scenario -eq 'blocked-input') { Start-Sleep -Seconds 30; exit }
$received = [Console]::In.ReadToEnd()
if ($Scenario -eq 'echo') { [Console]::Out.Write($received); exit }
if ($Scenario -eq 'streams') {
  [Console]::Out.Write(('o' * 131072))
  [Console]::Error.Write(('e' * 131072))
  exit
}
if ($Scenario -eq 'hold-pipes') {
  $info = [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', '[Console]::Out.WriteLine("inherited-output"); Start-Sleep -Seconds 30')) {
    $info.ArgumentList.Add($argument)
  }
  $child = [Diagnostics.Process]::Start($info)
  try {
    $identity = @{ Id = $child.Id; StartTime = $child.StartTime.ToUniversalTime().Ticks; Executable = $info.FileName } | ConvertTo-Json
    [IO.File]::WriteAllText($AnswerPath, $identity)
  } finally { $child.Dispose() }
  [Console]::Out.WriteLine('parent-exiting')
  exit
}
if ($Scenario -eq 'late-trace') { [Console]::Out.WriteLine(('x' * 131072)) }
[Console]::Out.WriteLine('{"type":"turn.completed","usage":{"input_tokens":12,"output_tokens":6}}')
[Console]::Error.WriteLine('fixture diagnostic')
if ($Scenario -eq 'timeout') { Start-Sleep -Seconds 30; exit }
if ($Scenario -eq 'failure') { exit 17 }
if ($Scenario -eq 'missing') { exit }
$answer = switch ($Scenario) {
  'malformed' { '{invalid' }
  'wrongtype' { '{"answers":[{"id":"ordinary_git","command":"git status","rationale":"test","use_skill":"false"}]}' }
  default { '{"answers":[{"id":"ordinary_git","command":"git status","rationale":"test","use_skill":false}]}' }
}
[IO.File]::WriteAllText($AnswerPath, $answer, [Text.UTF8Encoding]::new($false))
