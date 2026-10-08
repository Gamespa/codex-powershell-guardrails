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
