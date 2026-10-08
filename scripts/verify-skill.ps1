param([string]$RepositoryRoot = (Join-Path $PSScriptRoot '..'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$skillRoot = Join-Path $repoRoot 'powershell-guardrails'
$skillPath = Join-Path $skillRoot 'SKILL.md'
$requiredFiles = @('README.md', 'LICENSE', '.gitattributes', 'powershell-guardrails/SKILL.md',
  'powershell-guardrails/agents/openai.yaml',
  'powershell-guardrails/scripts/check-runtime.ps1',
  'powershell-guardrails/references/arguments-and-expansion.md',
  'powershell-guardrails/references/ssh-and-encoding.md',
  'powershell-guardrails/references/execution-and-lifecycle.md',
  'powershell-guardrails/references/runtime.md', 'scripts/validate-skill-yaml.py',
  'tests/pressure-scenarios.md', 'scripts/verify.ps1',
  'scripts/verify-skill.ps1', 'scripts/verify-pressure-scenarios.ps1',
  'scripts/verify-behavior.ps1', 'scripts/evaluate-model.ps1', 'tests/model-cases.json')
foreach ($relativePath in $requiredFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath) -PathType Leaf)) {
    throw "Missing required file: $relativePath"
  }
}

$text = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
$frontmatter = [regex]::Match($text, '\A---\r?\n(?<Body>[\s\S]*?)\r?\n---(?:\r?\n|\z)')
if (-not $frontmatter.Success) { throw 'SKILL.md needs delimited YAML frontmatter.' }

$python = (Get-Command python -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
& $python (Join-Path $repoRoot 'scripts/validate-skill-yaml.py') $skillRoot
$yamlExit = $LASTEXITCODE
if ($yamlExit -ne 0) { throw 'Full YAML validation failed; Python and PyYAML are required.' }

$documents = @(Get-ChildItem -LiteralPath $skillRoot -Recurse -File -Filter '*.md') +
  @(Get-Item -LiteralPath (Join-Path $repoRoot 'README.md'), (Join-Path $repoRoot 'tests/pressure-scenarios.md'))
foreach ($document in $documents) {
  $content = Get-Content -LiteralPath $document.FullName -Raw -Encoding UTF8
  if ($content -match '\[(?:TODO|TBD):') { throw "Unfinished scaffold: $($document.Name)" }
  foreach ($link in [regex]::Matches($content, '\[[^\]]+\]\((?<Target>[^\s)]+)\)')) {
    $target = $link.Groups['Target'].Value
    if ($target -match '^[a-z][a-z0-9+.-]*:|^#') { continue }
    $localPath = ($target -split '#', 2)[0]
    if ($localPath -and -not (Test-Path -LiteralPath (Join-Path $document.DirectoryName $localPath))) {
      throw "Broken local reference in $($document.Name): $target"
    }
  }
  $fences = [regex]::Matches($content, '(?m)^```[^\r\n]*$')
  if ($fences.Count % 2 -ne 0) { throw "Unclosed code fence: $($document.Name)" }
  foreach ($example in [regex]::Matches($content, '(?ms)^```powershell\r?\n(?<Code>.*?)^```\s*$')) {
    $parseTokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseInput($example.Groups['Code'].Value, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "Invalid PowerShell example in $($document.Name): $($parseErrors[0].Message)" }
  }
}
$scriptFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts') -Filter '*.ps1' -File) +
  @(Get-ChildItem -LiteralPath (Join-Path $skillRoot 'scripts') -Filter '*.ps1' -File)
foreach ($scriptFile in $scriptFiles) {
  $parseTokens = $null
  $parseErrors = $null
  $null = [Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$parseTokens, [ref]$parseErrors)
  if ($parseErrors.Count -gt 0) { throw "Invalid script $($scriptFile.Name): $($parseErrors[0].Message)" }
}
Write-Host 'Skill metadata, local references, and PowerShell syntax checks passed.'
