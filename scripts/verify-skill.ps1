param([string]$RepositoryRoot = (Join-Path $PSScriptRoot '..'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$skillRoot = Join-Path $repoRoot 'powershell-guardrails'
# Public entrypoints and the installable package are contracts; internal layout is not.
$requiredFiles = @('README.md', 'LICENSE', '.gitattributes', 'powershell-guardrails/SKILL.md',
  'powershell-guardrails/agents/openai.yaml', 'powershell-guardrails/scripts/check-runtime.ps1',
  'scripts/verify.ps1', 'scripts/verify-skill.ps1', 'scripts/verify-pressure-scenarios.ps1',
  'scripts/verify-behavior.ps1', 'scripts/evaluate-model.ps1', 'scripts/validate-skill-yaml.py',
  'tests/model-cases.json')
foreach ($relativePath in $requiredFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath) -PathType Leaf)) {
    throw "Missing required file: $relativePath"
  }
}

$python = (Get-Command python -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
& $python (Join-Path $repoRoot 'scripts/validate-skill-yaml.py') $skillRoot
$yamlExit = $LASTEXITCODE
if ($yamlExit -ne 0) { throw 'Full YAML validation failed; Python and PyYAML are required.' }

$sourceRoots = @($skillRoot, (Join-Path $repoRoot 'scripts'), (Join-Path $repoRoot 'tests'), (Join-Path $repoRoot 'docs'))
$documents = @(Get-Item -LiteralPath (Join-Path $repoRoot 'README.md')) + @(
  foreach ($sourceRoot in $sourceRoots) {
    if (Test-Path -LiteralPath $sourceRoot) { Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Filter '*.md' }
  }
)
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
$scriptFiles = @(
  foreach ($sourceRoot in $sourceRoots) {
    if (Test-Path -LiteralPath $sourceRoot) {
      Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Where-Object Extension -in @('.ps1', '.psm1', '.psd1')
    }
  }
)
foreach ($scriptFile in $scriptFiles) {
  $parseTokens = $null
  $parseErrors = $null
  $null = [Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$parseTokens, [ref]$parseErrors)
  if ($parseErrors.Count -gt 0) { throw "Invalid script $($scriptFile.Name): $($parseErrors[0].Message)" }
}
Write-Host 'Skill metadata, local references, and PowerShell syntax checks passed.'
