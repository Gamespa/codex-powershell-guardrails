param(
  [string]$Model = 'gpt-6.1-sol',
  [string]$BaselineRef = '377c95576f9afff270ec59c65877f330e305d5d6',
  [ValidateSet('provided-content', 'discovery', 'implicit')]
  [string]$Mode = 'provided-content',
  [ValidateSet('none', 'original', 'updated')]
  [string[]]$Variants = @('none', 'original', 'updated'),
  [int]$Repeats = 1,
  [int]$TimeoutSeconds = 240,
  [string[]]$CaseIds,
  [string]$OutputDirectory,
  [string]$SemanticImage
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
& (Join-Path $repoRoot 'powershell-guardrails/scripts/check-runtime.ps1')
Import-Module (Join-Path $PSScriptRoot 'lib/evaluation.psm1')
$options = @{
  RepositoryRoot = $repoRoot; Model = $Model; BaselineRef = $BaselineRef
  Mode = $Mode; Variants = $Variants; Repeats = $Repeats; TimeoutSeconds = $TimeoutSeconds
  CaseIds = $CaseIds; OutputDirectory = $OutputDirectory; UserProfile = $env:USERPROFILE
  SemanticImage = $SemanticImage
}
Invoke-ModelEvaluation @options
