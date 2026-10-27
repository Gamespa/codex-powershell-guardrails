$searchPath = Write-Fixture 'search.txt' "alpha`nbeta"
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

$chainProbe = Write-Fixture 'native-chain.ps1' @'
param([string]$SearchTool, [string]$MissingPath, [string]$ExistingPath)
$PSNativeCommandUseErrorActionPreference = $false
$null = & $SearchTool -l -- 'alpha' $MissingPath 2>&1
$firstExit = $LASTEXITCODE
$null = & $SearchTool -l -- 'alpha' $ExistingPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
'later-command-succeeded'
exit $firstExit
'@
$chainOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File $chainProbe $searchTool (Join-Path $fixtureRoot 'missing.txt') $searchPath
$chainExit = $LASTEXITCODE
Assert-Behavior ($chainExit -eq 2 -and $chainOutput -contains 'later-command-succeeded') 'Later native success masked the earlier search failure.'

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
