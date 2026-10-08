# Exercise the actual entrypoint with disposable verifier stubs and a Git failure.
$stubRoot = Join-Path $fixtureRoot 'entrypoint'
$stubScripts = Join-Path $stubRoot 'scripts'
$null = New-Item -ItemType Directory -Path $stubScripts
$stubRuntime = Join-Path $stubRoot 'powershell-guardrails/scripts'
$null = New-Item -ItemType Directory -Path $stubRuntime
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'powershell-guardrails/scripts/check-runtime.ps1') -Destination $stubRuntime
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'scripts/verify.ps1') -Destination (Join-Path $stubScripts 'verify.ps1')
foreach ($stub in @('verify-skill.ps1', 'verify-pressure-scenarios.ps1', 'verify-behavior.ps1')) {
  [IO.File]::WriteAllText((Join-Path $stubScripts $stub), '# Disposable validation stub')
}
$entrypointProbe = Write-Fixture 'entrypoint-probe.ps1' @'
param([string]$Verifier)
function git { $global:LASTEXITCODE = 42 }
function python { $global:LASTEXITCODE = 0 }
& $Verifier
'@
$entrypointOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File $entrypointProbe (Join-Path $stubScripts 'verify.ps1') 2>&1
$entrypointExit = $LASTEXITCODE
Assert-Behavior ($entrypointExit -ne 0 -and ($entrypointOutput -join "`n") -match 'git diff --check failed' -and ($entrypointOutput -join "`n") -notmatch 'validation chain passed') 'Verifier falsely reported Git failure as success.'

$pythonProbe = Write-Fixture 'python-failure-probe.ps1' @'
param([string]$Verifier)
function git { throw 'Git should not run after Python failure.' }
function python { $global:LASTEXITCODE = 23 }
& $Verifier
'@
$pythonOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File $pythonProbe (Join-Path $stubScripts 'verify.ps1') 2>&1
$pythonExit = $LASTEXITCODE
Assert-Behavior ($pythonExit -ne 0 -and ($pythonOutput -join "`n") -match 'Python validator regression tests failed' -and ($pythonOutput -join "`n") -notmatch 'validation chain passed') 'Verifier hid Python failure.'

# Validate that metadata flexibility and broken-reference detection are real.
$metadataRoot = Join-Path $fixtureRoot 'metadata'
$null = New-Item -ItemType Directory -Path $metadataRoot
foreach ($entry in @('README.md', 'LICENSE', '.gitattributes', 'powershell-guardrails', 'scripts', 'tests', 'docs')) {
  Copy-Item -LiteralPath (Join-Path $repositoryRoot $entry) -Destination $metadataRoot -Recurse
}
$metadataSkill = Join-Path $metadataRoot 'powershell-guardrails/SKILL.md'
$metadataText = Get-Content -LiteralPath $metadataSkill -Raw -Encoding UTF8
$flexibleHeader = @'
---
metadata:
  short-description: "Boundary regression fixture"
description: >-
  Resolve a fragile PowerShell boundary.
  Skip ordinary commands.
name: 'powershell-guardrails'
---
'@
$flexibleSkill = [regex]::Replace($metadataText, '\A---\r?\n[\s\S]*?\r?\n---', $flexibleHeader.TrimEnd())
[IO.File]::WriteAllText($metadataSkill, $flexibleSkill, [Text.UTF8Encoding]::new($false))
$metadataOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File (Join-Path $repositoryRoot 'scripts/verify-skill.ps1') -RepositoryRoot $metadataRoot 2>&1
$metadataExit = $LASTEXITCODE
Assert-Behavior ($metadataExit -eq 0) "Reordered optional metadata and folded description were rejected: $($metadataOutput -join ' ')"
[IO.File]::AppendAllText($metadataSkill, "`n[broken](references/missing.md)`n")
$brokenOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File (Join-Path $repositoryRoot 'scripts/verify-skill.ps1') -RepositoryRoot $metadataRoot 2>&1
$brokenExit = $LASTEXITCODE
Assert-Behavior ($brokenExit -ne 0 -and ($brokenOutput -join "`n") -match 'Broken local reference') 'Broken reference was accepted.'

[IO.File]::WriteAllText($metadataSkill, $flexibleSkill, [Text.UTF8Encoding]::new($false))
# Exercise the total chain: failures must stop before recursive behavior tests.
$chain = Join-Path $metadataRoot 'scripts/verify.ps1'
foreach ($relative in @('scripts/lib/syntax-probe.psm1', 'tests/behavior/syntax-probe.ps1')) {
  $invalidScript = Join-Path $metadataRoot $relative
  [IO.File]::WriteAllText($invalidScript, 'function Broken {')
  $invalidOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File $chain 2>&1
  $invalidExit = $LASTEXITCODE
  Assert-Behavior ($invalidExit -ne 0 -and ($invalidOutput -join "`n") -match 'Invalid script syntax-probe' -and ($invalidOutput -join "`n") -notmatch 'validation chain passed') "Chain missed syntax error in $relative."
  [IO.File]::WriteAllText($invalidScript, '# Restored valid fixture')
}
[IO.File]::WriteAllText((Join-Path $metadataRoot 'docs/link-probe.md'), '[broken](missing.md)')
$linkOutput = & $childShell -NoLogo -NoProfile -NonInteractive -File $chain 2>&1
$linkExit = $LASTEXITCODE
Assert-Behavior ($linkExit -ne 0 -and ($linkOutput -join "`n") -match 'Broken local reference in link-probe.md' -and ($linkOutput -join "`n") -notmatch 'validation chain passed') 'Chain missed a broken repository documentation link.'
