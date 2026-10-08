Set-StrictMode -Version Latest
function Get-SkillReadEvidence {
  param([string]$Trace, [string]$SkillRoot)
  $reads = [Collections.Generic.HashSet[string]]::new()
  $attempts = [Collections.Generic.HashSet[string]]::new()
  $files = @(Get-ChildItem -LiteralPath $SkillRoot -Recurse -File -Filter '*.md' | ForEach-Object {
    [pscustomobject]@{
      Relative = [IO.Path]::GetRelativePath($SkillRoot, $_.FullName).Replace('\', '/')
      Marker = if ($_.Name -eq 'SKILL.md') { 'name: powershell-guardrails' } else {
        ([string](Get-Content -LiteralPath $_.FullName -TotalCount 1)).Trim()
      }
    }
  })
  foreach ($line in $Trace -split '\r?\n') {
    try { $event = $line | ConvertFrom-Json -AsHashtable -NoEnumerate } catch { continue }
    if ($event -isnot [System.Collections.IDictionary] -or -not $event.Contains('type') -or $event.type -ne 'item.completed') { continue }
    if (-not $event.Contains('item')) { continue }
    $item = $event.item
    if ($item -isnot [System.Collections.IDictionary] -or -not $item.Contains('type') -or $item.type -ne 'command_execution') { continue }
    if ($item['command'] -isnot [string]) { continue }
    # Only completed shell reads with output evidence count. Mentions in prose,
    # attempted commands, and self-reports do not. Inspect traces for other tools.
    if ($item.command -notmatch '(?i)Get-Content|\bcat\b|\btype\b|read_text|readFile') { continue }
    foreach ($file in $files) {
      $relative = $file.Relative
      $portableCommand = $item.command.Replace('\', '/')
      if (-not $portableCommand.Contains($relative, [StringComparison]::OrdinalIgnoreCase)) { continue }
      $null = $attempts.Add($relative)
      $marker = $file.Marker
      if ($item['status'] -eq 'completed' -and ($item['exit_code'] -is [int] -or $item['exit_code'] -is [long]) -and $item['exit_code'] -eq 0 -and
          $item['aggregated_output'] -is [string] -and $marker -and $item.aggregated_output.Contains($marker, [StringComparison]::OrdinalIgnoreCase)) {
        $null = $reads.Add($relative)
      }
    }
  }
  [pscustomobject]@{
    skillRead = $reads.Contains('SKILL.md')
    referenceReads = @($reads | Where-Object { $_ -like 'references/*' } | Sort-Object)
    unverifiedReads = @($attempts | Where-Object { -not $reads.Contains($_) } | Sort-Object)
  }
}

Export-ModuleMember -Function Get-SkillReadEvidence
