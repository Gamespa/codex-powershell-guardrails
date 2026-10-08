param([string]$ModulePath, [string]$OutputRoot, [string]$ReadyPath, [switch]$WriteSnapshots)
$ErrorActionPreference = 'Stop'
Import-Module $ModulePath
$lock = Open-EvaluationLock $OutputRoot
try {
  [IO.File]::WriteAllText($ReadyPath, 'ready')
  if ($WriteSnapshots) {
    foreach ($number in 1..40) {
      $text = ConvertTo-Json -InputObject @(@{ sequence = $number; payload = ('x' * 16384) }) -Compress
      Write-EvaluationSnapshot -Path (Join-Path $OutputRoot 'results.json') -Content $text
      Start-Sleep -Milliseconds 10
    }
  } else { Start-Sleep -Seconds 30 }
} finally { $lock.Dispose() }
