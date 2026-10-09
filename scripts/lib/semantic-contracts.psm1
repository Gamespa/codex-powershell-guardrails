Set-StrictMode -Version Latest

function Get-SemanticContract {
  param([string]$Validator)
  switch ($Validator) {
    'native-arguments' { 'The harness supplies $nativeExecutable, $nativePrefix (an argument array), and $argumentValues. Invoke that native executable with the prefix followed by every argument value, preserving empty strings, quotes, spaces, Unicode and trailing backslashes. Emit its JSON response unchanged.' }
    'binary-output' { 'The harness supplies $exporter and $exporterArguments. Invoke that native exporter; save stdout to archive.bin and stderr to diagnostics.txt. Preserve exact bytes and fail on a nonzero exporter exit. Do not replace the provisioned exporter.' }
    'search-status' { 'Search ./fixtures for optional-feature with rg. Emit exactly one JSON object with status equal to matches or no-matches. On actual search failure, exit nonzero or throw. The caller has ErrorActionPreference=Stop and PSNativeCommandUseErrorActionPreference=true; preserve both preferences. No raw matching lines are required in stdout.' }
    'json-search' { 'Search marker in JSON files under ./data recursively. Emit matching lines with paths (rg -n output is acceptable), excluding other extensions. Preserve the matching text so callers can identify each hit.' }
    'json-array' { 'The harness supplies $reports, an array containing zero, one or several nested report objects. Serialize those objects to stdout as one JSON array, preserving all values and nested fields; do not replace the supplied data.' }
    default { throw "Unknown semantic validator: $Validator" }
  }
}

function Get-CaseSemanticContract {
  param($Case)
  if ($Case.PSObject.Properties['validator']) {
    Get-SemanticContract -Validator $Case.validator.id
  }
}

function Get-SemanticValidatorVersion {
  param([string]$Validator)
  $null = Get-SemanticContract $Validator
  if ($Validator -eq 'json-search') { 2 } else { 1 }
}

Export-ModuleMember -Function Get-SemanticContract, Get-CaseSemanticContract, Get-SemanticValidatorVersion
