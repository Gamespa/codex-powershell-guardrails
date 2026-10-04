Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion -lt [version]'7.3') {
  throw 'Behavior verification requires PowerShell 7.3 or later.'
}
$childShell = (Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$searchTool = (Get-Command rg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('powershell-guardrails-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureRoot
$checks = 0

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

# Native nonzero exits are data in several regressions, not cmdlet errors.
$previousNativeErrors = $PSNativeCommandUseErrorActionPreference
$PSNativeCommandUseErrorActionPreference = $false
try {
  $chainOutput = & $childShell -NoLogo -NoProfile -NonInteractive -Command 'Write-Output first && Write-Output second'
  $chainExit = $LASTEXITCODE
  Assert-Behavior ($chainExit -eq 0 -and ($chainOutput -join ',') -eq 'first,second') 'PowerShell 7 chains failed.'

  $echoPath = Write-Fixture 'echo-arguments.ps1' '[pscustomobject]@{ Arguments = @($args) } | ConvertTo-Json -Compress'
  $expectedArguments = @('', 'a"b', 'two words', 'tail\')
  $previousPassing = $PSNativeCommandArgumentPassing
  try {
    $PSNativeCommandArgumentPassing = 'Standard'
    $argumentOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File $echoPath @expectedArguments
    $argumentExit = $LASTEXITCODE
  } finally {
    $PSNativeCommandArgumentPassing = $previousPassing
  }
  $actualArguments = ($argumentOutput | ConvertFrom-Json).Arguments
  Assert-Behavior ($argumentExit -eq 0 -and $actualArguments.Count -eq $expectedArguments.Count) 'Native argument count changed.'
  for ($index = 0; $index -lt $expectedArguments.Count; $index++) {
    Assert-Behavior ($actualArguments[$index] -ceq $expectedArguments[$index]) "Native argument $index changed."
  }

  $searchPath = Write-Fixture 'search.txt' "alpha`nbeta`n<div class=`"trace-step`">"
  $searchOutput = & $searchTool -n -- 'alpha|beta' $searchPath
  $searchExit = $LASTEXITCODE
  Assert-Behavior ($searchExit -eq 0 -and @($searchOutput).Count -eq 2) 'Single-layer regex alternation failed.'
  $quoteArguments = @('-F', '--', '<div class="trace-step">', $searchPath)
  $quoteOutput = & $searchTool @quoteArguments
  $quoteExit = $LASTEXITCODE
  Assert-Behavior ($quoteExit -eq 0 -and $quoteOutput -ceq '<div class="trace-step">') 'Embedded quotes changed.'

  $name = 'request'
  $value = 'ok'
  Assert-Behavior ("${name}: $value" -ceq 'request: ok') 'Variable boundary formatting failed.'
  $sorted = & { foreach ($number in @(3, 1, 2)) { [pscustomobject]@{ Number = $number } } } | Sort-Object Number
  Assert-Behavior (($sorted.Number -join ',') -eq '1,2,3') 'Statement output pipeline failed.'

  $null = & $searchTool -l -- 'absent-marker' $searchPath
  $noMatchExit = $LASTEXITCODE
  $null = & $searchTool -l -- 'alpha' (Join-Path $fixtureRoot 'missing.txt') 2>&1
  $failureExit = $LASTEXITCODE
  Assert-Behavior ($noMatchExit -eq 1 -and $failureExit -eq 2) 'Search no-match and failure were conflated.'

  $cmdletProbe = Write-Fixture 'missing-input.ps1' @'
param([string]$InputPath)
$ErrorActionPreference = 'Stop'
$null = Get-Content -LiteralPath $InputPath
'false-success'
'@
  $probeOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File $cmdletProbe (Join-Path $fixtureRoot 'missing.txt') 2>&1
  $probeExit = $LASTEXITCODE
  Assert-Behavior ($probeExit -ne 0 -and ($probeOutput -join "`n") -notmatch 'false-success') 'Cmdlet failure was hidden.'

  $stdinProbe = Write-Fixture 'read-stdin.ps1' @'
$stream = [Console]::OpenStandardInput()
$buffer = [IO.MemoryStream]::new()
$stream.CopyTo($buffer)
[Convert]::ToBase64String($buffer.ToArray())
'@
  $unicodeText = 'printf "' + [char]0x4F60 + [char]0x597D + '"' + "`r`n"
  $normalizedText = $unicodeText -replace "`r`n", "`n"
  $previousEncoding = $OutputEncoding
  try {
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
    $encodedInput = $normalizedText | & $childShell -NoLogo -NoProfile -NonInteractive -File $stdinProbe
    $stdinExit = $LASTEXITCODE
  } finally {
    $OutputEncoding = $previousEncoding
  }
  $stdinBytes = [Convert]::FromBase64String($encodedInput)
  $receivedText = [Text.Encoding]::UTF8.GetString($stdinBytes)
  Assert-Behavior ($stdinExit -eq 0 -and $receivedText.TrimEnd("`r", "`n") -ceq $normalizedText.TrimEnd("`n")) 'Unicode native stdin changed.'
  $utf8Path = Write-Fixture 'unix-script.sh' $normalizedText
  $fileBytes = [IO.File]::ReadAllBytes($utf8Path)
  Assert-Behavior ($fileBytes[0] -ne 0xEF -and [Text.Encoding]::UTF8.GetString($fileBytes) -ceq $normalizedText) 'Unix file encoding or LF changed.'

  $secretMarker = 'fixture-value-' + [guid]::NewGuid().ToString('N')
  $credentialPath = Write-Fixture 'credentials.txt' ('api_token=' + $secretMarker)
  $rawRecords = & $searchTool --json -- 'api_token' $credentialPath
  $credentialExit = $LASTEXITCODE
  $metadata = foreach ($record in $rawRecords) {
    $event = $record | ConvertFrom-Json
    if ($event.type -eq 'match') {
      [pscustomobject]@{ Path = $event.data.path.text; Line = $event.data.line_number; MatchType = 'credential-marker' }
    }
  }
  $sanitized = $metadata | ConvertTo-Json -Compress
  Assert-Behavior ($credentialExit -eq 0 -and $sanitized -notmatch [regex]::Escape($secretMarker)) 'Sensitive match leaked.'
  Assert-Behavior ($metadata.Line -eq 1 -and $metadata.Path -eq $credentialPath) 'Sanitized search lost metadata.'

  # Exercise the actual entrypoint with disposable verifier stubs and a Git failure.
  $stubRoot = Join-Path $fixtureRoot 'entrypoint'
  $stubScripts = Join-Path $stubRoot 'scripts'
  $null = New-Item -ItemType Directory -Path $stubScripts
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'verify.ps1') -Destination (Join-Path $stubScripts 'verify.ps1')
  foreach ($stub in @('verify-skill.ps1', 'verify-pressure-scenarios.ps1', 'verify-behavior.ps1')) {
    [IO.File]::WriteAllText((Join-Path $stubScripts $stub), '# Disposable validation stub')
  }
  $entrypointProbe = Write-Fixture 'entrypoint-probe.ps1' @'
param([string]$Verifier)
function git { $global:LASTEXITCODE = 42 }
& $Verifier
'@
  $entrypointOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File $entrypointProbe (Join-Path $stubScripts 'verify.ps1') 2>&1
  $entrypointExit = $LASTEXITCODE
  Assert-Behavior ($entrypointExit -ne 0 -and ($entrypointOutput -join "`n") -notmatch 'validation chain passed') 'Verifier falsely reported Git failure as success.'

  # Validate that metadata flexibility and broken-reference detection are real.
  $metadataRoot = Join-Path $fixtureRoot 'metadata'
  $null = New-Item -ItemType Directory -Path $metadataRoot
  $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
  foreach ($entry in @('README.md', 'LICENSE', '.gitattributes', 'powershell-guardrails', 'scripts', 'tests')) {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot $entry) -Destination $metadataRoot -Recurse
  }
  $metadataSkill = Join-Path $metadataRoot 'powershell-guardrails/SKILL.md'
  $metadataText = Get-Content -LiteralPath $metadataSkill -Raw -Encoding UTF8
  $flexibleHeader = @'
---
metadata:
  short-description: "Boundary regression fixture"
description: >-
  Resolve a fragile PowerShell boundary.
  Skip ordinary commands.
name: 'powershell-guardrails'
---
'@
  $flexibleSkill = [regex]::Replace($metadataText, '\A---\r?\n[\s\S]*?\r?\n---', $flexibleHeader.TrimEnd())
  [IO.File]::WriteAllText($metadataSkill, $flexibleSkill, [Text.UTF8Encoding]::new($false))
  $metadataOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'verify-skill.ps1') -RepositoryRoot $metadataRoot 2>&1
  $metadataExit = $LASTEXITCODE
  Assert-Behavior ($metadataExit -eq 0) 'Reordered optional metadata and folded description were rejected.'
  [IO.File]::AppendAllText($metadataSkill, "`n[broken](references/missing.md)`n")
  $brokenOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'verify-skill.ps1') -RepositoryRoot $metadataRoot 2>&1
  $brokenExit = $LASTEXITCODE
  Assert-Behavior ($brokenExit -ne 0 -and ($brokenOutput -join "`n") -match 'Broken local reference') 'Broken reference was accepted.'
} finally {
  $PSNativeCommandUseErrorActionPreference = $previousNativeErrors
  $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
  $tempBoundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  if (-not $resolvedFixture.StartsWith($tempBoundary, [StringComparison]::OrdinalIgnoreCase) -or
      [IO.Path]::GetFileName($resolvedFixture) -notlike 'powershell-guardrails-*') {
    throw 'Refusing cleanup outside the disposable fixture directory.'
  }
  Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
Write-Host "Executable behavior verification passed. Assertions: $checks."
