Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repositoryRoot 'powershell-guardrails/scripts/check-runtime.ps1')
$childShell = Join-Path $PSHOME 'pwsh.exe'
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
  foreach ($runtimeCase in @(
    @{ Version = '7.6.0'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $true },
    @{ Version = '7.6.1'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $true },
    @{ Version = '7.6.99'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $true },
    @{ Version = '7.5.9'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $false },
    @{ Version = '7.7.0'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $false },
    @{ Version = '8.0.0'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $false },
    @{ Version = '5.1.0'; Edition = 'Desktop'; Platform = 'Win32NT'; Accepted = $false },
    @{ Version = '7.6.1'; Edition = 'Core'; Platform = 'Unix'; Accepted = $false },
    @{ Version = '7.6.1'; Edition = 'Desktop'; Platform = 'Win32NT'; Accepted = $false }
  )) {
    $accepted = $true
    try {
      Assert-GuardrailsRuntime -Version ([version]$runtimeCase.Version) -Edition $runtimeCase.Edition -Platform $runtimeCase.Platform
    } catch {
      if ($_.Exception.Message -notmatch 'requires Windows and pwsh 7\.6\.x') { throw }
      $accepted = $false
    }
    Assert-Behavior ($accepted -eq $runtimeCase.Accepted) "Runtime boundary failed for $($runtimeCase.Version)/$($runtimeCase.Edition)/$($runtimeCase.Platform)."
  }
  $childVersion = & $childShell -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'
  $childVersionExit = $LASTEXITCODE
  Assert-Behavior ($childVersionExit -eq 0 -and $childVersion -ceq $PSVersionTable.PSVersion.ToString()) 'Child PowerShell differs from the checked runtime.'

  $chainOutput = & $childShell -NoLogo -NoProfile -NonInteractive -Command 'Write-Output first && Write-Output second'
  $chainExit = $LASTEXITCODE
  Assert-Behavior ($chainExit -eq 0 -and ($chainOutput -join ',') -eq 'first,second') 'PowerShell 7 chains failed.'

  $echoPath = Write-Fixture 'echo-arguments.ps1' '[pscustomobject]@{ Arguments = @($args) } | ConvertTo-Json -Compress'
  $expectedArguments = @('', 'a"b', 'two words', 'tail\')
  $previousPassing = $PSNativeCommandArgumentPassing
  try {
    foreach ($passingMode in @('Standard', 'Windows')) {
      $PSNativeCommandArgumentPassing = $passingMode
      $argumentOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File $echoPath @expectedArguments
      $argumentExit = $LASTEXITCODE
      $actualArguments = ($argumentOutput | ConvertFrom-Json).Arguments
      Assert-Behavior ($argumentExit -eq 0 -and $actualArguments.Count -eq $expectedArguments.Count) "Native argument count changed in $passingMode mode."
      for ($index = 0; $index -lt $expectedArguments.Count; $index++) {
        Assert-Behavior ($actualArguments[$index] -ceq $expectedArguments[$index]) "Native argument $index changed in $passingMode mode."
      }
    }

    $PSNativeCommandArgumentPassing = 'Windows'
    $batchArgumentsProbe = Write-Fixture 'echo arguments with spaces.cmd' "@echo off`r`necho [%~1]`r`necho [%~2]`r`n"
    $batchArguments = @('two words', 'tail\')
    $batchOutput = & $batchArgumentsProbe @batchArguments
    $batchExit = $LASTEXITCODE
    Assert-Behavior ($batchExit -eq 0 -and ($batchOutput -join ',') -ceq '[two words],[tail\]') 'Windows-mode batch fallback changed trusted arguments.'

    $batchSetup = Write-Fixture 'setup environment with spaces.cmd' "@echo off`r`nset `"GUARDRAILS_TEST_BATCH_VALUE=child-ready`"`r`n"
    $batchBuild = Write-Fixture 'check environment with spaces.cmd' "@echo off`r`nif not defined GUARDRAILS_TEST_BATCH_VALUE exit /b 9`r`necho %GUARDRAILS_TEST_BATCH_VALUE%`r`n"
    $parentBatchValue = [Environment]::GetEnvironmentVariable('GUARDRAILS_TEST_BATCH_VALUE')
    $batchBuildOutput = cmd.exe /d /c "call ""$batchSetup"" && call ""$batchBuild"""
    $batchBuildExit = $LASTEXITCODE
    Assert-Behavior ($batchBuildExit -eq 0 -and $batchBuildOutput -ceq 'child-ready') 'Batch setup and dependent command did not share the child environment.'
    Assert-Behavior ([Environment]::GetEnvironmentVariable('GUARDRAILS_TEST_BATCH_VALUE') -ceq $parentBatchValue) 'Batch setup changed the parent environment.'
  } finally {
    $PSNativeCommandArgumentPassing = $previousPassing
  }

  $searchPath = Write-Fixture 'search.txt' "alpha`nbeta`n<div class=`"trace-step`">"
  $searchOutput = & $searchTool -n -- 'alpha|beta' $searchPath
  $searchExit = $LASTEXITCODE
  Assert-Behavior ($searchExit -eq 0 -and @($searchOutput).Count -eq 2) 'Single-layer regex alternation failed.'
  $quoteArguments = @('-F', '--', '<div class="trace-step">', $searchPath)
  $quoteOutput = & $searchTool @quoteArguments
  $quoteExit = $LASTEXITCODE
  Assert-Behavior ($quoteExit -eq 0 -and $quoteOutput -ceq '<div class="trace-step">') 'Embedded quotes changed.'

  $globRoot = Join-Path $fixtureRoot 'glob-data'
  $null = New-Item -ItemType Directory -Path (Join-Path $globRoot 'nested') -Force
  $firstJson = Write-Fixture 'glob-data/first.json' 'marker'
  $nestedJson = Write-Fixture 'glob-data/nested/second.json' 'marker'
  $null = Write-Fixture 'glob-data/ignored.txt' 'marker'
  $globOutput = & $searchTool -l -g '*.json' -- 'marker' $globRoot
  $globExit = $LASTEXITCODE
  $actualGlobPaths = @($globOutput | ForEach-Object { [IO.Path]::GetFullPath($_) } | Sort-Object)
  $expectedGlobPaths = @($firstJson, $nestedJson | Sort-Object)
  Assert-Behavior ($globExit -eq 0 -and $actualGlobPaths.Count -eq 2 -and
    $actualGlobPaths[0] -ceq $expectedGlobPaths[0] -and
    $actualGlobPaths[1] -ceq $expectedGlobPaths[1]) 'rg filename glob did not select only JSON files.'

  $name = 'request'
  $value = 'ok'
  Assert-Behavior ("${name}: $value" -ceq 'request: ok') 'Variable boundary formatting failed.'
  $sorted = & { foreach ($number in @(3, 1, 2)) { [pscustomobject]@{ Number = $number } } } | Sort-Object Number
  Assert-Behavior (($sorted.Number -join ',') -eq '1,2,3') 'Statement output pipeline failed.'

  foreach ($nativeErrors in @($false, $true)) {
    & {
      $PSNativeCommandUseErrorActionPreference = $nativeErrors
      $noMatchExit = & {
        $PSNativeCommandUseErrorActionPreference = $false
        $null = & $searchTool -l -- 'absent-marker' $searchPath
        $LASTEXITCODE
      }
      $failureExit = & {
        $PSNativeCommandUseErrorActionPreference = $false
        $null = & $searchTool -l -- 'alpha' (Join-Path $fixtureRoot 'missing.txt') 2>&1
        $LASTEXITCODE
      }
      Assert-Behavior ($noMatchExit -eq 1 -and $failureExit -eq 2) "Search status changed with native errors set to $nativeErrors."
      Assert-Behavior ($PSNativeCommandUseErrorActionPreference -eq $nativeErrors) 'Scoped native error preference leaked into its caller.'
    }
  }

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
  $expectedTextInput = [Text.Encoding]::UTF8.GetBytes($normalizedText + [Environment]::NewLine)
  Assert-Behavior ($stdinExit -eq 0 -and [Convert]::ToBase64String($stdinBytes) -ceq [Convert]::ToBase64String($expectedTextInput)) 'Native text stdin newline contract changed.'
  $exactBytes = [Text.Encoding]::UTF8.GetBytes($normalizedText)
  $encodedBytes = ,$exactBytes | & $childShell -NoLogo -NoProfile -NonInteractive -File $stdinProbe
  $byteInputExit = $LASTEXITCODE
  Assert-Behavior ($byteInputExit -eq 0 -and $encodedBytes -ceq [Convert]::ToBase64String($exactBytes)) 'Exact UTF-8 stdin bytes or LF changed.'
  $utf8Path = Join-Path $fixtureRoot 'unix-script.sh'
  Set-Content -LiteralPath $utf8Path -Value $normalizedText -Encoding utf8NoBOM -NoNewline
  $fileBytes = [IO.File]::ReadAllBytes($utf8Path)
  Assert-Behavior ($fileBytes[0] -ne 0xEF -and [Text.Encoding]::UTF8.GetString($fileBytes) -ceq $normalizedText) 'Unix file encoding or LF changed.'

  $binaryProbe = Write-Fixture 'write-bytes.ps1' @'
$bytes = [byte[]]@(0, 255, 13, 10, 128, 65)
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
'@
  $binaryPath = Join-Path $fixtureRoot 'native-output.bin'
  & $childShell -NoLogo -NoProfile -NonInteractive -File $binaryProbe > $binaryPath
  $binaryExit = $LASTEXITCODE
  Assert-Behavior ($binaryExit -eq 0 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($binaryPath)) -ceq [Convert]::ToBase64String([byte[]]@(0, 255, 13, 10, 128, 65))) 'Native stdout redirection changed binary bytes.'
  $pipedBinary = & $childShell -NoLogo -NoProfile -NonInteractive -File $binaryProbe | & $childShell -NoLogo -NoProfile -NonInteractive -File $stdinProbe
  $binaryPipeExit = $LASTEXITCODE
  Assert-Behavior ($binaryPipeExit -eq 0 -and $pipedBinary -ceq [Convert]::ToBase64String([byte[]]@(0, 255, 13, 10, 128, 65))) 'Native-to-native pipe changed binary bytes.'

  $literalPath = Write-Fixture 'report[1].txt' 'literal-file'
  Assert-Behavior ((Get-Content -LiteralPath $literalPath -Raw) -ceq 'literal-file') 'Literal bracket path did not identify the exact file.'
  Assert-Behavior ((Test-Path -LiteralPath $literalPath) -or (Test-Path -LiteralPath (Join-Path $fixtureRoot 'missing.txt'))) 'Grouped cmdlet logical expression failed.'
  foreach ($resultCount in @(0, 1, 2)) {
    $items = @(for ($itemIndex = 0; $itemIndex -lt $resultCount; $itemIndex++) {
      [pscustomobject]@{ Nested = [pscustomobject]@{ Child = [pscustomobject]@{ Value = $itemIndex } } }
    })
    $serialized = ConvertTo-Json -InputObject $items -Depth 4 -Compress
    $roundTrip = ConvertFrom-Json -InputObject $serialized -NoEnumerate
    Assert-Behavior ($roundTrip -is [array] -and $roundTrip.Count -eq $resultCount) "JSON array shape changed for $resultCount results."
    if ($resultCount -gt 0) {
      Assert-Behavior ($roundTrip[0].Nested.Child.Value -eq 0) 'Nested JSON data was lost.'
    }
  }
  $appendPath = Join-Path $fixtureRoot 'utf16-log.txt'
  Set-Content -LiteralPath $appendPath -Value $unicodeText -Encoding unicode -NoNewline
  Add-Content -LiteralPath $appendPath -Value $unicodeText -Encoding unicode -NoNewline
  Assert-Behavior ((Get-Content -LiteralPath $appendPath -Raw -Encoding unicode) -ceq ($unicodeText + $unicodeText)) 'Appending with the existing encoding corrupted text.'

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
  $stubRuntime = Join-Path $stubRoot 'powershell-guardrails/scripts'
  $null = New-Item -ItemType Directory -Path $stubRuntime
  Copy-Item -LiteralPath (Join-Path $repositoryRoot 'powershell-guardrails/scripts/check-runtime.ps1') -Destination $stubRuntime
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

  $legacyShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
  if (Test-Path -LiteralPath $legacyShell) {
    $runtimeOutput = & $legacyShell -NoLogo -NoProfile -NonInteractive -File (Join-Path $repositoryRoot 'powershell-guardrails/scripts/check-runtime.ps1') 2>&1
    $runtimeExit = $LASTEXITCODE
    Assert-Behavior ($runtimeExit -ne 0 -and ($runtimeOutput -join "`n") -match 'requires Windows and pwsh 7\.6\.x') 'Unsupported Windows PowerShell runtime was accepted.'
  }
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
