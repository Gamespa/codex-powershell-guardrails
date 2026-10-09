Set-StrictMode -Version Latest

function New-SemanticScenarios {
  param([string]$Validator, [int]$Seed = 1729)
  $random = [Random]::new($Seed)
  $tag = $random.Next(100000, 999999).ToString()
  $unicode = [string][char]0x4F60 + [char]0x597D
  switch ($Validator) {
    'native-arguments' {
      foreach ($mode in @('Windows', 'Standard')) {
        $values = @('', 'a"b', "two words $tag", "tail$tag\", $unicode)
        [pscustomobject]@{ name = $mode; kind = $Validator; expected = $values
          payload = @{ setup = @"
`$PSNativeCommandArgumentPassing = '$mode'
`$nativeExecutable = Join-Path `$PSHOME 'pwsh.exe'
`$nativePrefix = @('-NoLogo','-NoProfile','-NonInteractive','-File','echo arguments.ps1')
`$argumentValues = Get-Content -LiteralPath values.json -Raw | ConvertFrom-Json -NoEnumerate
"@; files = @{ 'values.json' = ConvertTo-Json -InputObject $values -Compress
            'echo arguments.ps1' = 'ConvertTo-Json -InputObject @($args) -Compress -EscapeHandling EscapeNonAscii' }; artifacts = @() }
        }
      }
    }
    'binary-output' {
      foreach ($exitCode in @(0, 17)) {
        $bytes = [byte[]]::new(259)
        $random.NextBytes($bytes)
        $bytes[0] = 0; $bytes[1] = 255; $bytes[2] = 128
        $base64 = [Convert]::ToBase64String($bytes)
        [pscustomobject]@{ name = "exit-$exitCode"; kind = $Validator
          expected = @{ bytes = $base64; exitCode = $exitCode; diagnostic = "diagnostic-$tag" }
          payload = @{ setup = @'
$exporter = Join-Path $PSHOME 'pwsh.exe'
$exporterArguments = @('-NoLogo','-NoProfile','-NonInteractive','-File','export archive.ps1')
'@; files = @{ 'export archive.ps1' = @"
`$bytes = [Convert]::FromBase64String('$base64')
`$stream = [Console]::OpenStandardOutput()
`$stream.Write(`$bytes, 0, `$bytes.Length)
[Console]::Error.WriteLine('diagnostic-$tag')
exit $exitCode
"@ }; artifacts = @('archive.bin', 'diagnostics.txt') }
        }
      }
    }
    'search-status' {
      foreach ($state in @('matches', 'no-matches', 'error')) {
        $files = @{}
        if ($state -ne 'error') { $files["fixtures/input $tag.txt"] = if ($state -eq 'matches') { "optional-feature-$tag" } else { "unrelated-$tag" } }
        [pscustomobject]@{ name = $state; kind = $Validator; expected = $state
          payload = @{ setup = '$ErrorActionPreference = ''Stop''; $PSNativeCommandUseErrorActionPreference = $true'
            files = $files; artifacts = @('preferences.txt'); suffix = @'
if ($ErrorActionPreference -ne 'Stop' -or -not $PSNativeCommandUseErrorActionPreference) {
  throw 'Caller preferences were changed.'
}
[IO.File]::WriteAllText('preferences.txt', 'preserved')
'@ }
        }
      }
    }
    'json-search' {
      $first = "marker-first-$tag"; $second = "marker-nested-$tag"; $excluded = "marker-excluded-$tag"
      [pscustomobject]@{ name = 'recursive'; kind = $Validator
        expected = @{ first = $first; second = $second; excluded = $excluded }
        payload = @{ setup = ''; artifacts = @(); files = @{
          "data/first $tag.json" = $first; "data/nested dir/second $tag.json" = $second
          "data/ignored $tag.txt" = $excluded; "data/empty $tag.json" = '{}' } }
      }
    }
    'json-array' {
      foreach ($count in @(0, 1, 3)) {
        $reports = @(for ($i = 0; $i -lt $count; $i++) {
          @{ id = $i; name = "$unicode-$tag-$i"; detail = @{ child = @{ leaf = @{ value = $random.Next(); enabled = $true; nothing = $null; labels = @('a', 'b') } } } }
        })
        $json = ConvertTo-Json -InputObject $reports -Depth 12 -Compress
        [pscustomobject]@{ name = "count-$count"; kind = $Validator; expected = $json
          payload = @{ setup = '$reports = Get-Content -LiteralPath reports.json -Raw | ConvertFrom-Json -NoEnumerate'
            files = @{ 'reports.json' = $json }; artifacts = @() }
        }
      }
    }
    default { throw "Unknown semantic validator: $Validator" }
  }
}

function Test-JsonSemanticEqual {
  param($Actual, $Expected)
  if ($null -eq $Expected) { return $null -eq $Actual }
  if ($Expected -is [Collections.IDictionary]) {
    if ($Actual -isnot [Collections.IDictionary] -or $Actual.Count -ne $Expected.Count) { return $false }
    foreach ($key in $Expected.Keys) {
      if (-not $Actual.Contains($key) -or -not (Test-JsonSemanticEqual $Actual[$key] $Expected[$key])) { return $false }
    }
    return $true
  }
  if ($Expected -is [array]) {
    if ($Actual -isnot [array] -or $Actual.Count -ne $Expected.Count) { return $false }
    for ($i = 0; $i -lt $Expected.Count; $i++) {
      if (-not (Test-JsonSemanticEqual $Actual[$i] $Expected[$i])) { return $false }
    }
    return $true
  }
  return $Actual.GetType() -eq $Expected.GetType() -and $Actual -ceq $Expected
}

function Test-SemanticObservation {
  param($Scenario, $Observation)
  $checks = [Collections.Generic.List[object]]::new()
  $execution = $Observation.execution
  $checks.Add([pscustomobject]@{ name = 'finished-within-limits'; passed = -not $execution.TimedOut -and -not $execution.Error -and -not $execution.StdoutTruncated -and -not $execution.StderrTruncated })
  $expectFailure = ($Scenario.kind -eq 'binary-output' -and $Scenario.expected.exitCode -ne 0) -or
    ($Scenario.kind -eq 'search-status' -and $Scenario.expected -eq 'error')
  $checks.Add([pscustomobject]@{ name = 'exit-status'; passed = $null -ne $execution.ExitCode -and
    $(if ($expectFailure) { $execution.ExitCode -ne 0 } else { $execution.ExitCode -eq 0 }) })
  switch ($Scenario.kind) {
    { $_ -in 'native-arguments', 'json-array', 'search-status' } {
      if (-not $expectFailure) {
        $matches = $false
        try {
          $actual = ConvertFrom-Json -InputObject $execution.Stdout -AsHashtable -NoEnumerate -ErrorAction Stop
          $expected = switch ($Scenario.kind) {
            'native-arguments' { ConvertTo-Json -InputObject $Scenario.expected -Compress }
            'json-array' { $Scenario.expected }
            'search-status' { ConvertTo-Json -InputObject @{ status = $Scenario.expected } -Compress }
          }
          $matches = Test-JsonSemanticEqual $actual (ConvertFrom-Json -InputObject $expected -AsHashtable -NoEnumerate)
        } catch { $matches = $false }
        $checks.Add([pscustomobject]@{ name = 'exact-json-values-and-shape'; passed = $matches })
        if ($Scenario.kind -eq 'search-status') {
          $checks.Add([pscustomobject]@{ name = 'caller-preferences-preserved'; passed =
            $Observation.artifacts['preferences.txt'] -ceq [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('preserved')) })
        }
      }
    }
    'binary-output' {
      $archive = $Observation.artifacts['archive.bin']; $diagnostic = $Observation.artifacts['diagnostics.txt']
      $checks.Add([pscustomobject]@{ name = 'exact-archive-bytes'; passed = $null -ne $archive -and $archive -ceq $Scenario.expected.bytes })
      $text = if ($diagnostic) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($diagnostic)).TrimEnd([char[]]"`r`n") } else { '' }
      $checks.Add([pscustomobject]@{ name = 'separate-diagnostics'; passed = $text -ceq $Scenario.expected.diagnostic })
    }
    'json-search' {
      $lines = @($execution.Stdout -split '\r?\n' | Where-Object { $_.Length })
      # Compare path/content pairs rather than requiring rg's colon separator.
      # A drive-letter colon belongs to the path, not to the result delimiter.
      $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
      $valid = $lines.Count -eq 2
      foreach ($line in $lines) {
        $match = [regex]::Match($line, '^(?<path>.+?\.json)(?::(?:(?<number>[0-9]+):)?|\t(?:(?<number>[0-9]+)\t)?)(?<text>.*)$', 'IgnoreCase')
        if (-not $match.Success -or ($match.Groups['number'].Success -and $match.Groups['number'].Value -ne '1')) { $valid = $false; continue }
        $path = $match.Groups['path'].Value.Replace('\', '/') -replace '^(?:\./)+', ''
        $text = $match.Groups['text'].Value
        $hits = @($Scenario.payload.files.Keys | Where-Object {
          $expectedPath = $_.Replace('\', '/')
          ($path -ieq $expectedPath -or
            ($path -match '^(?:[a-zA-Z]:/|//)' -and $path -notmatch '/\.\.?/' -and
             $path.EndsWith('/' + $expectedPath, [StringComparison]::OrdinalIgnoreCase))) -and
          $Scenario.payload.files[$_] -ceq $text -and
          $text -cin @($Scenario.expected.first, $Scenario.expected.second)
        })
        if ($hits.Count -ne 1 -or -not $seen.Add($hits[0])) { $valid = $false }
      }
      $checks.Add([pscustomobject]@{ name = 'recursive-json-only'; passed = $valid -and $seen.Count -eq 2 })
    }
  }
  $checks.ToArray()
}

Export-ModuleMember -Function New-SemanticScenarios, Test-SemanticObservation
