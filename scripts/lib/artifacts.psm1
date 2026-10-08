Set-StrictMode -Version Latest

function Open-EvaluationLock {
  param([string]$OutputRoot)
  $ErrorActionPreference = 'Stop'
  $path = Join-Path $OutputRoot '.evaluation.lock'
  try {
    # Keep the file after release. Deleting it would race a contender opening it.
    # The OS releases the exclusive handle if the owner process crashes.
    [IO.FileStream]::new($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  } catch [IO.IOException] {
    throw "Cannot acquire evaluation output lock: $OutputRoot. Another writer may be active. $($_.Exception.Message)"
  }
}

function Write-EvaluationSnapshot {
  param([string]$Path, [string]$Content)
  $ErrorActionPreference = 'Stop'
  $target = [IO.Path]::GetFullPath($Path)
  $temporary = Join-Path ([IO.Path]::GetDirectoryName($target)) ('.results-' + [guid]::NewGuid().ToString('N') + '.tmp')
  $stream = $null
  try {
    $stream = [IO.FileStream]::new($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
    $stream.Dispose()
    $stream = $null
    # Temporary and destination share a directory/filesystem. Readers see an
    # entire old or new snapshot; an interrupted writer cannot truncate the old one.
    if ([IO.File]::Exists($target)) { [IO.File]::Replace($temporary, $target, [NullString]::Value) }
    else { [IO.File]::Move($temporary, $target) }
  } finally {
    if ($stream) { $stream.Dispose() }
    if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
  }
}

Export-ModuleMember -Function Open-EvaluationLock, Write-EvaluationSnapshot
