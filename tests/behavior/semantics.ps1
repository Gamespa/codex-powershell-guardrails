Import-Module (Join-Path $repositoryRoot 'scripts/lib/semantics.psm1') -Force
Import-Module (Join-Path $repositoryRoot 'scripts/lib/semantic-backend.psm1') -Force
Import-Module (Join-Path $repositoryRoot 'scripts/lib/process.psm1')
Import-Module (Join-Path $repositoryRoot 'scripts/lib/cases.psm1')
$allCases = @(Read-ModelCases (Join-Path $repositoryRoot 'tests/model-cases.json'))
$selected = @($allCases | Where-Object { $_.PSObject.Properties['validator'] -or $_.id -eq 'ordinary_git' })
$good = @{
  modern_native_quotes = @'
& $nativeExecutable @nativePrefix @argumentValues
if ($LASTEXITCODE -ne 0) { throw 'Native echo failed.' }
'@
  binary_redirection = @'
& $exporter @exporterArguments > archive.bin 2> diagnostics.txt
if ($LASTEXITCODE -ne 0) { throw 'Exporter failed.' }
'@
  search_status = @'
& {
  $PSNativeCommandUseErrorActionPreference = $false
  rg --quiet -- 'optional-feature' ./fixtures
  $code = $LASTEXITCODE
  switch ($code) {
    0 { @{ status = 'matches' } | ConvertTo-Json -Compress }
    1 { @{ status = 'no-matches' } | ConvertTo-Json -Compress }
    default { throw "Search failed: $code" }
  }
}
'@
  windows_rg_file_glob = "rg -n -g '*.json' -- marker ./data"
  structured_output = 'ConvertTo-Json -InputObject @($reports) -Depth 12 -Compress'
}
$bad = @{
  modern_native_quotes = '$nonempty = @($argumentValues | Where-Object { $_ -ne '''' }); & $nativeExecutable @nativePrefix @nonempty'
  binary_redirection = '& $exporter @exporterArguments 2> diagnostics.txt | Out-File archive.bin'
  search_status = 'rg --quiet -- optional-feature ./fixtures; @{ status = ''matches'' } | ConvertTo-Json -Compress'
  windows_rg_file_glob = 'rg -n -- marker ./data'
  structured_output = '$reports | ConvertTo-Json -Depth 2 -Compress'
}
$trustedSources = @($good.Values) + @($bad.Values)
$semanticShell = Join-Path $PSHOME 'pwsh.exe'
# This seam executes ONLY the fixed repository-owned commands above. Model answers
# never reach this host runner, and the public CLI does not expose this seam.
$trustedBackend = {
  param($image, $bundle, $timeout)
  $source = [IO.File]::ReadAllText((Join-Path $bundle 'command.ps1'))
  if ($source -cnotin $trustedSources) { throw 'Offline runner accepts only fixed regression sources.' }
  $execution = Invoke-EvaluationProcess -Executable $semanticShell -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-File',
    (Join-Path $bundle 'semantic-worker.ps1'), '-BundleRoot', $bundle, '-TemporaryRoot', $fixtureRoot) -Prompt '' -TimeoutSeconds 30
  if ($execution.Error -or $execution.TimedOut -or $execution.StdoutTruncated) { throw "Trusted worker failed: $($execution.Error) $($execution.Stderr)" }
  $observation = ConvertFrom-Json -InputObject $execution.Stdout -AsHashtable -NoEnumerate
  [pscustomobject]@{ imageId = 'offline-trusted-fixture'; infrastructureError = $observation['infrastructureError']; observation = $observation }
}.GetNewClosure()
$answers = @($good.Keys | ForEach-Object { [pscustomobject]@{ id = $_; command = $good[$_] } })
$disabled = Invoke-SemanticEvaluation -Cases $selected -Answers $answers
Assert-Behavior ($disabled.summary.configured -eq 5 -and $disabled.summary.evaluated -eq 0 -and $null -eq $disabled.summary.passRate) 'Skipped semantic checks were counted as passes.'
$verified = Invoke-SemanticEvaluation -Cases $selected -Answers $answers -Image offline -OutputDirectory (Join-Path $fixtureRoot 'good') -Backend $trustedBackend
Assert-Behavior ($verified.summary.passed -eq 5 -and $verified.summary.failed -eq 0 -and $verified.summary.infrastructureErrors -eq 0) "Correct fixtures failed: $($verified | ConvertTo-Json -Depth 12 -Compress)"
Assert-Behavior ($verified.summary.notEvaluated -eq 1 -and $verified.summary.evaluatedCoverage -eq (5 / 6) -and $verified.summary.passRate -eq 1) 'Coverage denominator or pass rate is incorrect.'
Assert-Behavior (@($verified.cases | Where-Object validator | ForEach-Object trials).Count -eq 22) 'Scenario/seed coverage changed unexpectedly.'
$answers = @($bad.Keys | ForEach-Object { [pscustomobject]@{ id = $_; command = $bad[$_] } })
$failed = Invoke-SemanticEvaluation -Cases $selected -Answers $answers -Image offline -OutputDirectory (Join-Path $fixtureRoot 'bad') -Backend $trustedBackend
Assert-Behavior ($failed.summary.failed -eq 5 -and $failed.summary.infrastructureErrors -eq 0 -and $failed.summary.passRate -eq 0) "Wrong commands escaped semantic checks: $($failed | ConvertTo-Json -Depth 12 -Compress)"
$infra = Invoke-SemanticEvaluation -Cases @($selected | Where-Object id -eq 'structured_output') -Answers $answers -Image offline -OutputDirectory (Join-Path $fixtureRoot 'infra') -Backend { throw 'offline backend unavailable' }
Assert-Behavior ($infra.summary.infrastructureErrors -eq 1 -and $infra.summary.failed -eq 0 -and $null -eq $infra.summary.passRate) 'Infrastructure failure counted as model failure or success.'
$invalid = Invoke-SemanticEvaluation -Cases $selected -Answers $answers -Image offline -ResponseValid $false -Backend { throw 'Must not execute invalid response.' }
Assert-Behavior ($invalid.summary.evaluated -eq 0 -and $invalid.summary.notEvaluated -eq 6) 'Invalid response reached semantic execution.'

# Mock transport checks the real container lifecycle, without a Docker installation.
$state = @{ name = ''; mode = 'success'; calls = [Collections.Generic.List[object]]::new() }
$docker = {
  param($exe, $arguments, $timeout)
  $state.calls.Add(@($arguments))
  $output = ''; $exitCode = 0; $timedOut = $false
  switch ($arguments[0]) {
    'image' { $output = @{ Os = 'windows'; Id = 'sha256:' + ('a' * 64); Config = @{ Volumes = $null } } | ConvertTo-Json -Depth 5 -Compress }
    'create' {
      $state.name = $arguments[[array]::IndexOf($arguments, '--name') + 1]
      $output = 'container-id'
    }
    'inspect' {
      if ($arguments[2] -match 'index') { $output = $state.name }
      else {
        $output = @{ HostConfig = @{ Isolation = if ($state.mode -eq 'unsafe') { 'process' } else { 'hyperv' }; NetworkMode = 'none' }
          Config = @{ User = 'ContainerUser'; Labels = @{ 'guardrails.semantic' = $state.name } }; Mounts = @() } | ConvertTo-Json -Depth 6 -Compress
      }
    }
    'start' {
      $timedOut = $state.mode -eq 'timeout'
      $output = @{ protocol = 1; infrastructureError = $null; runtime = '7.6.0'; artifacts = @{}
        execution = @{ ExitCode = 0; TimedOut = $false; Error = $null; Stdout = '[]'; Stderr = ''; StdoutTruncated = $false; StderrTruncated = $false } } | ConvertTo-Json -Depth 5 -Compress
    }
    'rm' { if ($state.mode -eq 'cleanup-failed') { $exitCode = 1 } }
  }
  [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $timedOut; Error = $null; Stdout = $output; Stderr = ''; StdoutTruncated = $false; StderrTruncated = $false }
}.GetNewClosure()
foreach ($mode in @('success', 'unsafe', 'timeout', 'cleanup-failed')) {
  $state.mode = $mode; $state.calls.Clear()
  $result = Invoke-SemanticContainer -Image fixture -BundleDirectory $fixtureRoot -DockerExecutable mock -DockerRunner $docker
  Assert-Behavior (($null -eq $result.infrastructureError) -eq ($mode -eq 'success')) "Container failure classification incorrect for $mode."
  $create = @($state.calls | Where-Object { $_[0] -eq 'create' })[0]
  Assert-Behavior ('hyperv' -in $create -and 'none' -in $create -and 'never' -in $create -and 'ContainerUser' -in $create -and '-v' -notin $create -and '--mount' -notin $create) 'Container security arguments changed.'
  Assert-Behavior (@($state.calls | Where-Object { $_[0] -eq 'rm' }).Count -eq 1) "Container was not cleaned up after $mode."
  if ($mode -eq 'unsafe') { Assert-Behavior (@($state.calls | Where-Object { $_[0] -eq 'start' }).Count -eq 0) 'Unsafe container was started.' }
}
$missing = Invoke-SemanticContainer -Image fixture -BundleDirectory $fixtureRoot -DockerExecutable (Join-Path $fixtureRoot 'missing-docker.exe')
Assert-Behavior ($missing.infrastructureError -and $null -eq $missing.observation) 'Missing backend executed locally or reported success.'

# Public CLI persists skipped results without requesting a container or model.
$savedAnswers = Join-Path $fixtureRoot 'saved-answers.json'
[IO.File]::WriteAllText($savedAnswers, '{"answers":[{"id":"ordinary_git","command":"git status"}]}')
$cliOutput = & $semanticShell -NoLogo -NoProfile -NonInteractive -File (Join-Path $repositoryRoot 'scripts/evaluate-semantics.ps1') -AnswersPath $savedAnswers -Image unused -OutputDirectory (Join-Path $fixtureRoot 'cli') -CaseIds ordinary_git 2>&1
$cliExit = $LASTEXITCODE
$savedResult = Get-Content -LiteralPath (Join-Path $fixtureRoot 'cli/semantics.json') -Raw | ConvertFrom-Json
Assert-Behavior ($cliExit -eq 0 -and $savedResult.summary.notEvaluated -eq 1 -and $null -eq $savedResult.summary.passRate) "Standalone result contract failed: $cliOutput"
