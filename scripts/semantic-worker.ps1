# Runs inside the isolated container. Never invoke this on model input on the host.
param([string]$BundleRoot = $PSScriptRoot, [string]$TemporaryRoot = [IO.Path]::GetTempPath())
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Import-Module (Join-Path $BundleRoot 'process.psm1')
try {
  & (Join-Path $BundleRoot 'check-runtime.ps1')
  $null = Get-Command rg -CommandType Application -ErrorAction Stop
  $request = Get-Content -LiteralPath (Join-Path $BundleRoot 'request.json') -Raw | ConvertFrom-Json -AsHashtable
  $work = Join-Path $TemporaryRoot ('semantic-' + [guid]::NewGuid().ToString('N'))
  $null = New-Item -ItemType Directory -Path $work
  foreach ($name in $request.payload.files.Keys) {
    $path = [IO.Path]::GetFullPath((Join-Path $work $name))
    if (-not $path.StartsWith($work + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture path escaped workspace.' }
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
    [IO.File]::WriteAllText($path, $request.payload.files[$name])
  }
  $taskPath = Join-Path $work 'task.ps1'
  $source = '$ErrorActionPreference = ''Stop''; [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)' + "`n" + $request.payload.setup + "`n" +
    [IO.File]::ReadAllText((Join-Path $BundleRoot 'command.ps1')) + "`n" + $request.payload['suffix']
  [IO.File]::WriteAllText($taskPath, $source)
  Set-Location -LiteralPath $work
  [Environment]::CurrentDirectory = $work
  $execution = Invoke-EvaluationProcess -Executable (Join-Path $PSHOME 'pwsh.exe') -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $taskPath) -Prompt '' -TimeoutSeconds $request.timeoutSeconds
  if ($null -eq $execution.ExitCode -and $execution.Error -and -not $execution.TimedOut) { throw "Unable to start semantic child: $($execution.Error)" }
  $artifacts = @{}
  foreach ($name in $request.payload.artifacts) {
    # Fixed names supplied by trusted validators, never by a model response.
    $path = Join-Path $work $name
    $artifacts[$name] = $null
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Item -LiteralPath $path).Length -le 65536) {
      $artifacts[$name] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
    }
  }
  @{ protocol = 1; infrastructureError = $null; runtime = $PSVersionTable.PSVersion.ToString()
    execution = $execution; artifacts = $artifacts } | ConvertTo-Json -Depth 12 -Compress -EscapeHandling EscapeNonAscii
} catch {
  @{ protocol = 1; infrastructureError = $_.Exception.Message } | ConvertTo-Json -Compress
  exit 1
}
