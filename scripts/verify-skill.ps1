Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
  param([string]$Message)
  $failures.Add($Message)
}

function Require-File {
  param([string]$Path)
  $fullPath = Join-Path $repoRoot $Path
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    Add-Failure "Missing required file: $Path"
  }
}

function Require-Text {
  param(
    [string]$Path,
    [string]$Pattern,
    [string]$Description
  )
  $fullPath = Join-Path $repoRoot $Path
  if (-not (Select-String -LiteralPath $fullPath -Pattern $Pattern -Quiet)) {
    Add-Failure "$Path is missing: $Description"
  }
}

$requiredFiles = @(
  'README.md',
  'LICENSE',
  '.gitattributes',
  'powershell-guardrails/SKILL.md',
  'powershell-guardrails/agents/openai.yaml',
  'powershell-guardrails/references/pitfalls.md',
  'powershell-guardrails/references/pressure-scenarios.md',
  'scripts/verify.ps1',
  'scripts/verify-pressure-scenarios.ps1',
  'scripts/verify-skill.ps1'
)

foreach ($path in $requiredFiles) {
  Require-File $path
}

$skillPath = Join-Path $repoRoot 'powershell-guardrails/SKILL.md'
$skillLines = Get-Content -LiteralPath $skillPath

if ($skillLines.Count -lt 4 -or $skillLines[0] -ne '---' -or $skillLines[3] -ne '---') {
  Add-Failure 'SKILL.md frontmatter must occupy lines 1-4.'
}

$nameLine = $skillLines | Where-Object { $_ -like 'name:*' } | Select-Object -First 1
if ($nameLine -ne 'name: powershell-guardrails') {
  Add-Failure 'SKILL.md name must be powershell-guardrails.'
}

$descriptionLine = $skillLines | Where-Object { $_ -like 'description:*' } | Select-Object -First 1
if (-not $descriptionLine) {
  Add-Failure 'SKILL.md must have a description.'
} else {
  $description = $descriptionLine -replace '^description: ', ''
  if (-not $description.StartsWith('Use when')) {
    Add-Failure 'SKILL.md description must start with "Use when".'
  }
  if ($description.Length -gt 500) {
    Add-Failure "SKILL.md description is too long: $($description.Length) characters."
  }
  if ($description -match 'checklist|safe pattern|choose command shapes|identify which shell') {
    Add-Failure 'SKILL.md description should describe triggers, not workflow.'
  }
}

Require-Text 'powershell-guardrails/SKILL.md' '^## Fast Path$' 'Fast Path section'
Require-Text 'powershell-guardrails/SKILL.md' 'references/pressure-scenarios\.md' 'pressure scenario reference'
Require-Text 'powershell-guardrails/SKILL.md' 'read-only\s+command' 'destructive command read-only gate'
Require-Text 'powershell-guardrails/SKILL.md' '\$\{name\}' 'braced variable-boundary guidance'
Require-Text 'powershell-guardrails/SKILL.md' 'API headers, tokens, JSON bodies' 'structured API request guidance'
Require-Text 'powershell-guardrails/SKILL.md' 'file metrics, line counts, or inventory reports' 'complex local inventory guidance'
Require-Text 'powershell-guardrails/references/pitfalls.md' '& \$tool @args' 'argument-array safe pattern'
Require-Text 'powershell-guardrails/references/pitfalls.md' '^## 3d\. Member Access And Indexing In Nested Commands$' 'member/index nested command pitfall'
Require-Text 'powershell-guardrails/references/pitfalls.md' '^## 3e\. Complex Local Inventory One-Liners$' 'complex local inventory pitfall'
Require-Text 'powershell-guardrails/references/pitfalls.md' '^## 5a\. Native Batch Toolchain Boundaries$' 'cmd and batch toolchain boundary pitfall'
Require-Text 'powershell-guardrails/references/pitfalls.md' '^## 8a\. Variables Followed By Punctuation$' 'variable punctuation pitfall'
Require-Text 'powershell-guardrails/references/pressure-scenarios.md' '^## Scenario 11\. Variable Followed By Colon$' 'variable colon pressure scenario'
Require-Text 'powershell-guardrails/references/pressure-scenarios.md' '^## Scenario 12\. API Request With Token And JSON$' 'API request pressure scenario'
Require-Text 'powershell-guardrails/references/pressure-scenarios.md' '^## Scenario 13\. Native Batch Toolchain Setup$' 'native batch toolchain pressure scenario'
Require-Text 'powershell-guardrails/references/pressure-scenarios.md' '^## Scenario 15\. Recursive File Inventory$' 'recursive file inventory pressure scenario'
Require-Text 'README.md' 'scripts/verify-skill\.ps1' 'verification command'
Require-Text 'README.md' 'scripts/verify-pressure-scenarios\.ps1' 'pressure-scenario verification command'
Require-Text 'README.md' 'scripts/verify\.ps1' 'full verification command'
Require-Text 'scripts/verify-skill.ps1' 'verify-pressure-scenarios\.ps1' 'pressure scenario verifier invocation'
Require-Text 'scripts/verify-skill.ps1' 'verify\.ps1' 'full verification entrypoint reference'
Require-Text 'scripts/verify.ps1' 'git diff --check' 'diff hygiene check'

$scenarioPath = Join-Path $repoRoot 'powershell-guardrails/references/pressure-scenarios.md'
$scenarioCount = (Select-String -LiteralPath $scenarioPath -Pattern '^## Scenario ' | Measure-Object).Count
if ($scenarioCount -lt 8) {
  Add-Failure "Expected at least 8 pressure scenarios, found $scenarioCount."
}

$badContentPatterns = @(
  'TODO',
  'TBD',
  'FIXME',
  'producer-password',
  'producer\.\*password',
  'npm --prefix web',
  'src/App\.test\.tsx',
  'Gamespa',
  'Moos',
  'Modo',
  'home_dev',
  '\.ssh',
  'my-linux',
  'localhost',
  '127\.0\.0\.1',
  'D:\\',
  'C:\\Users'
)

$scanFiles = @(
  'README.md',
  'powershell-guardrails/SKILL.md',
  'powershell-guardrails/references/pitfalls.md',
  'powershell-guardrails/references/pressure-scenarios.md',
  'powershell-guardrails/agents/openai.yaml'
)

foreach ($path in $scanFiles) {
  $fullPath = Join-Path $repoRoot $path
  foreach ($pattern in $badContentPatterns) {
    if (Select-String -LiteralPath $fullPath -Pattern $pattern -Quiet) {
      Add-Failure "$path contains non-generic or stale pattern: $pattern"
    }
  }
}

foreach ($path in $scanFiles) {
  $fullPath = Join-Path $repoRoot $path
  $lineNumber = 0
  foreach ($line in Get-Content -LiteralPath $fullPath) {
    $lineNumber++
    if ($path -eq 'powershell-guardrails/SKILL.md' -and $lineNumber -eq 3) {
      continue
    }
    if ($line.Length -gt 160) {
      Add-Failure "$path line $lineNumber exceeds 160 characters."
    }
  }
}

if ($failures.Count -gt 0) {
  foreach ($failure in $failures) {
    Write-Error $failure -ErrorAction Continue
  }
  exit 1
}

$pressureVerifier = Join-Path $repoRoot 'scripts/verify-pressure-scenarios.ps1'
& $pressureVerifier

Write-Host 'PowerShell guardrails skill verification passed.'
