Import-Module (Join-Path $repositoryRoot 'scripts/lib/semantic-fixtures.psm1') -Force
foreach ($seed in @(1729, 7919)) {
  $scenario = @(New-SemanticScenarios -Validator json-search -Seed $seed)[0]
  $firstPath = @($scenario.payload.files.Keys | Where-Object { $scenario.payload.files[$_] -ceq $scenario.expected.first })[0]
  $secondPath = @($scenario.payload.files.Keys | Where-Object { $scenario.payload.files[$_] -ceq $scenario.expected.second })[0]
  $first = $scenario.expected.first; $second = $scenario.expected.second
  $observation = @{ execution = @{ ExitCode = 0; TimedOut = $false; Error = $null
      StdoutTruncated = $false; StderrTruncated = $false; Stdout = ''; Stderr = '' }; artifacts = @{} }
  foreach ($output in @(
      "${firstPath}:1:$first`n${secondPath}:1:$second",
      "${firstPath}:$first`n${secondPath}:$second",
      "$firstPath`t$first`n$secondPath`t$second",
      "$firstPath`t1`t$first`n$secondPath`t1`t$second",
      "./$secondPath`t$second`r`n./$firstPath`t$first`r`n",
      "C:\work\$($firstPath.Replace('/', '\')):1:$first`nC:\work\$($secondPath.Replace('/', '\'))`t$second",
      "\\server\work\$($firstPath.Replace('/', '\'))`t$first`n\\server\work\$($secondPath.Replace('/', '\'))`t$second"
  )) {
    $observation.execution.Stdout = $output
    $checksResult = @(Test-SemanticObservation $scenario $observation)
    Assert-Behavior (@($checksResult | Where-Object { -not $_.passed }).Count -eq 0) "Valid search output rejected: $output"
  }
  foreach ($output in @(
      "$firstPath`t$first",
      "$firstPath`t$first`n$firstPath`t$first",
      "$firstPath`t$second`n$secondPath`t$first",
      "$firstPath`t${first}-extra`n$secondPath`t$second",
      "$firstPath`t$first`n$secondPath`t$second`nignored.txt`t$($scenario.expected.excluded)",
      "$firstPath.txt`t$first`n$secondPath`t$second",
      "wrong.json`t$first`n$secondPath`t$second",
      "$first`n$second",
      "${firstPath}:2:$first`n${secondPath}:1:$second",
      "C:/work/../$firstPath`t$first`n$secondPath`t$second"
  )) {
    $observation.execution.Stdout = $output
    $checksResult = @(Test-SemanticObservation $scenario $observation)
    Assert-Behavior (@($checksResult | Where-Object { -not $_.passed }).Count -gt 0) "Invalid search output accepted: $output"
  }
}
