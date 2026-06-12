Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')
$scenarioPath = Join-Path $repoRoot 'powershell-guardrails/references/pressure-scenarios.md'
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
  param([string]$Message)
  $failures.Add($Message)
}

function Get-SectionText {
  param(
    [string]$Text,
    [string]$StartPattern,
    [string]$EndPattern,
    [string]$Description
  )

  $options = [System.Text.RegularExpressions.RegexOptions]::Singleline
  $match = [regex]::Match($Text, "$StartPattern(?<Body>.*?)$EndPattern", $options)
  if (-not $match.Success) {
    Add-Failure $Description
    return ''
  }

  return $match.Groups['Body'].Value
}

if (-not (Test-Path -LiteralPath $scenarioPath -PathType Leaf)) {
  Add-Failure 'Missing pressure-scenarios.md.'
} else {
  $text = Get-Content -LiteralPath $scenarioPath -Raw
  $headingPattern = '(?m)^## Scenario (?<Number>\d+)\. (?<Title>.+)$'
  $headingMatches = [regex]::Matches($text, $headingPattern)

  if ($headingMatches.Count -lt 17) {
    Add-Failure "Expected at least 17 pressure scenarios, found $($headingMatches.Count)."
  }

  for ($i = 0; $i -lt $headingMatches.Count; $i++) {
    $heading = $headingMatches[$i]
    $number = [int]$heading.Groups['Number'].Value
    $title = $heading.Groups['Title'].Value
    $expected = $i + 1

    if ($number -ne $expected) {
      Add-Failure "Scenario heading order mismatch: expected $expected, found $number."
    }

    $start = $heading.Index + $heading.Length
    $end = $text.Length
    if ($i -lt $headingMatches.Count - 1) {
      $end = $headingMatches[$i + 1].Index
    }
    $block = $text.Substring($start, $end - $start)
    $label = "Scenario $number ($title)"

    foreach ($requiredLabel in @('Prompt:', 'Common failing answer:', 'Passing answer:')) {
      if ($block -notmatch [regex]::Escape($requiredLabel)) {
        Add-Failure "$label is missing label: $requiredLabel"
      }
    }

    if ($block -notmatch 'Why it (fails|can fail|is risky|is incomplete):') {
      Add-Failure "$label is missing a why-it-fails explanation."
    }

    $prompt = Get-SectionText $block 'Prompt:\s*' 'Common failing answer:' "$label prompt must precede failing answer."
    $failing = Get-SectionText $block 'Common failing answer:\s*' 'Why it (?:fails|can fail|is risky|is incomplete):' "$label failing answer must precede explanation."
    $explanation = Get-SectionText $block 'Why it (?:fails|can fail|is risky|is incomplete):\s*' 'Passing answer:' "$label explanation must precede passing answer."
    $passing = Get-SectionText $block 'Passing answer:\s*' '\z' "$label passing answer is missing."

    if ($prompt -notmatch '```text\s+[\s\S]+?```') {
      Add-Failure "$label prompt must be a fenced text block."
    }
    if ($failing -notmatch '```(?:powershell|text)\s+[\s\S]+?```') {
      Add-Failure "$label failing answer must be a fenced powershell or text block."
    }
    if ($passing -notmatch '```(?:powershell|text)\s+[\s\S]+?```') {
      Add-Failure "$label passing answer must be a fenced powershell or text block."
    }
    if ($explanation.Trim().Length -lt 40) {
      Add-Failure "$label explanation is too short to teach the failure mode."
    }

    $scenarioScope = "$title`n$prompt"
    if ($scenarioScope -match '(?i)\b(ssh|OpenSSH|remote Linux|remote bash)\b' -and
        $passing -notmatch 'bash -s|ssh [^\r\n]+''') {
      Add-Failure "$label remote scenario should avoid fragile nested quoting."
    }
    if ($scenarioScope -match '(?i)\b(stop|remove|cleanup|clean it up|destructive)\b' -and
        $passing -notmatch 'Select-Object|verified|reviewing|compare') {
      Add-Failure "$label destructive scenario should include a read-only verification step."
    }
  }
}

if ($failures.Count -gt 0) {
  foreach ($failure in $failures) {
    Write-Error $failure -ErrorAction Continue
  }
  exit 1
}

Write-Host "Pressure scenario verification passed. Scenarios: $($headingMatches.Count)."
