function Get-SkillReadEvidence {
  param([string]$Trace, [string]$SkillRoot)
  $reads = [Collections.Generic.HashSet[string]]::new()
  $attempts = [Collections.Generic.HashSet[string]]::new()
  foreach ($line in $Trace -split '\r?\n') {
    try { $event = $line | ConvertFrom-Json } catch { continue }
    if ($null -eq $event -or -not $event.PSObject.Properties['type'] -or $event.type -ne 'item.completed') { continue }
    $item = $event.item
    if ($null -eq $item -or -not $item.PSObject.Properties['type'] -or $item.type -ne 'command_execution') { continue }
    # Only completed shell reads with output evidence count. Mentions in prose,
    # attempted commands, and self-reports do not. Inspect traces for other tools.
    if ($item.command -notmatch '(?i)Get-Content|\bcat\b|\btype\b|read_text|readFile') { continue }
    foreach ($file in Get-ChildItem -LiteralPath $SkillRoot -Recurse -File -Filter '*.md') {
      $relative = [IO.Path]::GetRelativePath($SkillRoot, $file.FullName).Replace('\', '/')
      $portableCommand = $item.command.Replace('\', '/')
      if (-not $portableCommand.Contains($relative, [StringComparison]::OrdinalIgnoreCase)) { continue }
      $null = $attempts.Add($relative)
      $marker = if ($relative -eq 'SKILL.md') { 'name: powershell-guardrails' } else {
        (Get-Content -LiteralPath $file.FullName -TotalCount 1).Trim()
      }
      if ($item.status -eq 'completed' -and $item.exit_code -eq 0 -and
          $item.aggregated_output.Contains($marker, [StringComparison]::OrdinalIgnoreCase)) {
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
