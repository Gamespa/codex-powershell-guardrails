Set-StrictMode -Version Latest

function Get-CandidateBundle {
  param([string]$RepositoryRoot, [ValidateSet('none', 'original', 'updated')][string]$Variant, [string]$BaselineRef)
  if ($Variant -eq 'none') { return @() }
  # Keep expected native failure handling local to this function.
  $PSNativeCommandUseErrorActionPreference = $false
  $prefix = 'powershell-guardrails/'
  if ($Variant -eq 'original') {
    $commit = & git -C $RepositoryRoot rev-parse --verify --end-of-options "${BaselineRef}^{commit}" 2>&1
    $resolveExit = $LASTEXITCODE
    if ($resolveExit -ne 0) { throw "Cannot resolve baseline $BaselineRef." }
    $revision = [string]$commit
    $paths = & git -C $RepositoryRoot ls-tree -r --name-only $revision -- powershell-guardrails
    $treeExit = $LASTEXITCODE
    if ($treeExit -ne 0) { throw "Cannot enumerate baseline $BaselineRef." }
  } else {
    $skillRoot = Join-Path $RepositoryRoot 'powershell-guardrails'
    $paths = @(Get-ChildItem -LiteralPath $skillRoot -Recurse -File | ForEach-Object {
      $prefix + [IO.Path]::GetRelativePath($skillRoot, $_.FullName).Replace('\', '/')
    })
  }
  $selected = @($paths | Where-Object {
    $_ -eq "${prefix}SKILL.md" -or $_ -eq "${prefix}agents/openai.yaml" -or
    $_ -like "${prefix}scripts/*.ps1" -or
    ($_ -like "${prefix}references/*.md" -and $_ -notlike '*/pressure-scenarios.md')
  } | Sort-Object)
  if ("${prefix}SKILL.md" -notin $selected) { throw 'Candidate entrypoint is missing.' }
  foreach ($path in $selected) {
    $relative = $path.Substring($prefix.Length)
    if ($relative -split '/' -contains '..') { throw "Unsafe candidate path: $relative" }
    if ($Variant -eq 'original') {
      $lines = & git -C $RepositoryRoot show "${revision}:$path"
      $sourceExit = $LASTEXITCODE
      if ($sourceExit -ne 0) { throw "Cannot load baseline file: $relative" }
      $content = ($lines -join "`n") + "`n"
    } else {
      $content = [IO.File]::ReadAllText((Join-Path $RepositoryRoot $path))
    }
    [pscustomobject]@{ Path = $relative; Content = $content }
  }
}

Export-ModuleMember -Function Get-CandidateBundle
