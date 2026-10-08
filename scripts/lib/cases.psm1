Set-StrictMode -Version Latest

function Read-ModelCases {
  param([string]$Path, [string[]]$CaseIds)
  $cases = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -NoEnumerate
  if ($cases -isnot [array] -or $cases.Count -eq 0) { throw 'Model evaluation needs a nonempty case array.' }
  $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($case in $cases) {
    foreach ($field in @('id', 'prompt', 'expectedOutcome', 'shouldTrigger', 'language')) {
      if ($null -eq $case -or -not $case.PSObject.Properties[$field]) { throw "Case needs field: $field" }
    }
    if ($case.id -isnot [string] -or $case.id -notmatch '\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z') {
      throw 'Case ID must be a nonempty portable filename component.'
    }
    if (-not $ids.Add($case.id)) { throw "Duplicate case ID: $($case.id)" }
    foreach ($field in @('prompt', 'expectedOutcome')) {
      if ($case.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($case.$field)) {
        throw "Case $($case.id) needs a nonempty $field."
      }
    }
    if ($case.shouldTrigger -isnot [bool]) { throw "Case $($case.id) needs a boolean shouldTrigger." }
    if ($case.language -notin @('powershell', 'bash', 'none')) { throw "Invalid language for $($case.id)." }
  }
  if (@($cases | Where-Object shouldTrigger).Count -eq 0 -or
      @($cases | Where-Object { -not $_.shouldTrigger }).Count -eq 0) {
    throw 'Include both fragile-boundary cases and negative trigger controls.'
  }
  if ($CaseIds) {
    foreach ($id in $CaseIds) { if (-not $ids.Contains($id)) { throw "Unknown case ID: $id" } }
    $cases = @($cases | Where-Object { $_.id -in $CaseIds })
  }
  return $cases
}

function Get-EvaluationRuns {
  param([object[]]$Cases, [string]$Mode, [string[]]$Variants, [int]$Repeats)
  foreach ($repeat in 1..$Repeats) {
    foreach ($variant in $Variants) {
      if ($Mode -eq 'implicit') {
        foreach ($case in $Cases) {
          [pscustomobject]@{ Name = "$variant-$repeat-$($case.id)"; Variant = $variant; Repeat = $repeat; Cases = @($case) }
        }
      } else {
        [pscustomobject]@{ Name = "$variant-$repeat"; Variant = $variant; Repeat = $repeat; Cases = $Cases }
      }
    }
  }
}

Export-ModuleMember -Function Read-ModelCases, Get-EvaluationRuns
