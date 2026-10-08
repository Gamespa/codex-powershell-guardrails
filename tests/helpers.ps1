function Assert-Behavior {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
  $script:checks++
}

function Write-Fixture {
  param([string]$Name, [string]$Content)
  $path = Join-Path $fixtureRoot $Name
  [IO.File]::WriteAllText($path, $Content, [Text.UTF8Encoding]::new($false))
  return $path
}

function Remove-TestFixture {
  param([string]$Path)
  $resolvedFixture = [IO.Path]::GetFullPath($Path)
  $tempBoundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  if (-not $resolvedFixture.StartsWith($tempBoundary, [StringComparison]::OrdinalIgnoreCase) -or
      [IO.Path]::GetFileName($resolvedFixture) -notlike 'powershell-guardrails-*') {
    throw 'Refusing cleanup outside the disposable fixture directory.'
  }
  Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}

function Assert-Throws {
  param([scriptblock]$Action, [string]$Pattern)
  $caught = $null
  try { & $Action } catch { $caught = $_ }
  $actual = if ($caught) { $caught.Exception.Message } else { 'no exception' }
  Assert-Behavior ($null -ne $caught -and $caught.Exception.Message -match $Pattern) "Expected failure: $Pattern; got: $actual"
}
