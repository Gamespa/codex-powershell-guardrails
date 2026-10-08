Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'semantic-contracts.psm1')
Import-Module (Join-Path $PSScriptRoot 'semantic-fixtures.psm1')
Import-Module (Join-Path $PSScriptRoot 'semantic-backend.psm1')

function Invoke-SemanticEvaluation {
  param([object[]]$Cases, [object[]]$Answers, [string]$Image, [string]$OutputDirectory,
    [bool]$ResponseValid = $true,
    # Internal seam; offline tests supply repository-owned answers and observations only.
    [scriptblock]$Backend = { param($image, $bundle, $timeout)
      Invoke-SemanticContainer -Image $image -BundleDirectory $bundle -TimeoutSeconds $timeout
    })
  $ErrorActionPreference = 'Stop'
  $records = [Collections.Generic.List[object]]::new()
  if ($Image -and $ResponseValid) {
    if (-not $OutputDirectory -or (Test-Path -LiteralPath $OutputDirectory)) { throw 'Semantic artifacts require a fresh output directory.' }
    $null = New-Item -ItemType Directory -Path $OutputDirectory
  }
  foreach ($case in $Cases) {
    $validator = if ($case.PSObject.Properties['validator']) { $case.validator.id } else { $null }
    $record = [ordered]@{ id = $case.id; validator = $validator; validatorVersion = if ($validator) { 1 } else { $null }
      semanticStatus = 'not-evaluated'; reason = $null; trials = @() }
    if (-not $validator) { $record.reason = 'no-validator' }
    elseif (-not $ResponseValid) { $record.reason = 'invalid-model-response' }
    elseif (-not $Image) { $record.reason = 'isolated-backend-not-requested' }
    else {
      $null = Get-SemanticContract $validator
      $answer = @($Answers | Where-Object { $_.id -ceq $case.id })
      if ($answer.Count -ne 1 -or $answer[0].command -isnot [string] -or [string]::IsNullOrWhiteSpace($answer[0].command)) {
        $record.semanticStatus = 'failed'; $record.reason = 'missing-or-empty-command'
      } else {
        $tokens = $null; $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseInput($answer[0].command, [ref]$tokens, [ref]$errors)
        if ($errors.Count) {
          $record.semanticStatus = 'failed'; $record.reason = 'invalid-command-syntax'
        } else {
          foreach ($seed in @(1729, 7919)) {
            foreach ($scenario in @(New-SemanticScenarios -Validator $validator -Seed $seed)) {
              $trial = [ordered]@{ seed = $seed; scenario = $scenario.name; status = 'infrastructure-error'
                assertions = @(); diagnostic = $null; imageId = $null; runtime = $null; artifactsPath = $null }
              try {
                $trialRoot = Join-Path $OutputDirectory "$($case.id)/$seed-$($scenario.name)"
                $bundle = Join-Path $trialRoot 'bundle'
                $null = New-Item -ItemType Directory -Path $bundle -Force
                $trial.artifactsPath = [IO.Path]::GetFullPath($trialRoot)
                # Expected values stay on the host, outside the copied bundle.
                [IO.File]::WriteAllText((Join-Path $trialRoot 'expected.json'), (ConvertTo-Json -InputObject $scenario.expected -Depth 12))
                [IO.File]::WriteAllText((Join-Path $bundle 'request.json'), (ConvertTo-Json -InputObject @{ payload = $scenario.payload; timeoutSeconds = 20 } -Depth 12))
                [IO.File]::WriteAllText((Join-Path $bundle 'command.ps1'), $answer[0].command)
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../semantic-worker.ps1') -Destination $bundle
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'process.psm1') -Destination $bundle
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../powershell-guardrails/scripts/check-runtime.ps1') -Destination $bundle
                $result = & $Backend $Image $bundle 20
                [IO.File]::WriteAllText((Join-Path $trialRoot 'observation.json'), (ConvertTo-Json -InputObject $result -Depth 12))
                $trial.imageId = $result.imageId
                if ($result.infrastructureError) { $trial.diagnostic = $result.infrastructureError }
                else {
                  $trial.runtime = $result.observation.runtime
                  $trial.assertions = @(Test-SemanticObservation -Scenario $scenario -Observation $result.observation)
                  $trial.status = if (@($trial.assertions | Where-Object { -not $_.passed }).Count) { 'failed' } else { 'passed' }
                }
              } catch { $trial.diagnostic = $_.Exception.Message }
              $record.trials += [pscustomobject]$trial
            }
          }
          $record.semanticStatus = if (@($record.trials | Where-Object status -eq 'infrastructure-error').Count) { 'infrastructure-error' }
            elseif (@($record.trials | Where-Object status -eq 'failed').Count) { 'failed' }
            else { 'passed' }
        }
      }
    }
    $records.Add([pscustomobject]$record)
  }
  $configured = @($records | Where-Object validator).Count
  $passed = @($records | Where-Object semanticStatus -eq 'passed').Count
  $failed = @($records | Where-Object semanticStatus -eq 'failed').Count
  $evaluated = $passed + $failed
  [pscustomobject]@{
    cases = $records.ToArray()
    summary = [pscustomobject]@{
      total = $records.Count; configured = $configured; evaluated = $evaluated; passed = $passed; failed = $failed
      notEvaluated = @($records | Where-Object semanticStatus -eq 'not-evaluated').Count
      infrastructureErrors = @($records | Where-Object semanticStatus -eq 'infrastructure-error').Count
      configuredCoverage = if ($records.Count) { $configured / $records.Count } else { $null }
      evaluatedCoverage = if ($records.Count) { $evaluated / $records.Count } else { $null }
      passRate = if ($evaluated) { $passed / $evaluated } else { $null }
    }
  }
}

Export-ModuleMember -Function Invoke-SemanticEvaluation
