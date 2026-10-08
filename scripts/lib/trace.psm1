Set-StrictMode -Version Latest

function Get-LiteralReadPaths {
  param([string]$Command, [string]$WorkingDirectory, [int]$Depth = 0)
  # Parse, never execute, command text. Ambiguous expressions stay unverified.
  $tokens = $null; $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseInput($Command, [ref]$tokens, [ref]$errors)
  if ($errors.Count -and $Command -match '^\s*"[^"\r\n]+(?:pwsh|powershell)\.exe"\s') {
    $ast = [Management.Automation.Language.Parser]::ParseInput("& $Command", [ref]$tokens, [ref]$errors)
  }
  if ($errors.Count -or $Depth -gt 3) {
    [pscustomobject]@{ Path = $null; Unresolved = $true }; return
  }
  if (-not $ast.EndBlock) { return }
  $directory = $WorkingDirectory
  foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -isnot [Management.Automation.Language.PipelineAst]) {
      if ($statement.Extent.Text -match '(?i)Get-Content|\bgc\b|\bcat\b|\btype\b|read_text|readFile|Set-Location|\bcd\b|Push-Location|Pop-Location') {
        [pscustomobject]@{ Path = $null; Unresolved = $true }
        $directory = $null
      }
      continue
    }
    foreach ($node in $statement.PipelineElements) {
      if ($node -isnot [Management.Automation.Language.CommandAst]) { continue }
      $name = $node.GetCommandName()
      if (-not $name) {
        [pscustomobject]@{ Path = $null; Unresolved = $true }; continue
      }
      $leaf = [IO.Path]::GetFileName($name)
      if ($leaf -match '^(pwsh|powershell)(\.exe)?$') {
        $elements = $node.CommandElements
        $payload = $null
        for ($i = 1; $i -lt $elements.Count - 1; $i++) {
          if ($elements[$i].Extent.Text -in @('-Command', '-c') -and
              $elements[$i + 1] -is [Management.Automation.Language.StringConstantExpressionAst]) {
            $payload = $elements[$i + 1].Value; break
          }
        }
        if ($null -ne $payload) {
          Get-LiteralReadPaths -Command $payload -WorkingDirectory $directory -Depth ($Depth + 1)
        } else { [pscustomobject]@{ Path = $null; Unresolved = $true } }
        continue
      }
      $isLocation = $name -in @('Set-Location', 'cd', 'sl', 'chdir')
      $isRead = $name -in @('Get-Content', 'gc', 'cat', 'type', 'Microsoft.PowerShell.Management\Get-Content')
      if (-not $isRead -and -not $isLocation) {
        if ($name -in @('Push-Location', 'Pop-Location', 'pushd', 'popd') -or
            $node.Extent.Text -match '(?i)read_text|readFile') {
          [pscustomobject]@{ Path = $null; Unresolved = $true }
          if ($name -match 'Location|pushd|popd') { $directory = $null }
        }
        continue
      }
      $operands = [Collections.Generic.List[object]]::new()
      $literal = $false
      $unknown = $false
      for ($i = 1; $i -lt $node.CommandElements.Count; $i++) {
        $element = $node.CommandElements[$i]
        if ($element -is [Management.Automation.Language.CommandParameterAst]) {
          $parameter = $element.ParameterName
          if ($parameter -in @('Raw', 'Force')) { continue }
          if ($parameter -in @('Encoding', 'TotalCount', 'First', 'Head', 'Tail', 'Last', 'ReadCount', 'Delimiter', 'ErrorAction', 'ea')) {
            if (-not $element.Argument) { $i++ }; continue
          }
          if ($parameter -notin @('LiteralPath', 'Path')) { $unknown = $true; continue }
          if ($parameter -eq 'LiteralPath') { $literal = $true }
          if ($element.Argument) { $operands.Add($element.Argument) }
          continue
        }
        if ($element -is [Management.Automation.Language.ArrayLiteralAst]) {
          foreach ($part in $element.Elements) { $operands.Add($part) }
        } else { $operands.Add($element) }
      }
      if (-not $operands.Count -or $unknown) {
        [pscustomobject]@{ Path = $null; Unresolved = $true }
        if ($isLocation) { $directory = $null }
        continue
      }
      foreach ($operand in $operands) {
        $value = $null
        if ($operand -is [Management.Automation.Language.StringConstantExpressionAst]) { $value = $operand.Value }
        if ($operand -is [Management.Automation.Language.ExpandableStringExpressionAst] -and $operand.NestedExpressions.Count -eq 0) { $value = $operand.Value }
        $path = $null
        try {
          if (-not $value -or (-not $literal -and [Management.Automation.WildcardPattern]::ContainsWildcardCharacters($value))) { throw 'Nonliteral path' }
          if ([IO.Path]::IsPathFullyQualified($value)) { $path = [IO.Path]::GetFullPath($value) }
          elseif ($directory) { $path = [IO.Path]::GetFullPath($value, $directory) }
        } catch { $path = $null }
        if ($isLocation) { $directory = $path } else {
          [pscustomobject]@{ Path = $path; Unresolved = $null -eq $path }
        }
      }
    }
  }
}

function Get-SkillReadEvidence {
  [CmdletBinding(DefaultParameterSetName = 'Text')]
  param(
    [Parameter(ParameterSetName = 'Text')][AllowEmptyString()][string]$Trace = '',
    [Parameter(Mandatory, ParameterSetName = 'File')][string]$TracePath,
    [string]$SkillRoot, [string]$Workspace
  )
  $reads = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $unverified = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $rejected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $unresolved = [Collections.Generic.HashSet[string]]::new()
  $files = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
  if ($SkillRoot) {
    foreach ($file in Get-ChildItem -LiteralPath $SkillRoot -Recurse -File | Where-Object Extension -in @('.md', '.ps1', '.psm1', '.yaml', '.yml')) {
      $files[[IO.Path]::GetFullPath($file.FullName)] = [pscustomobject]@{
        Relative = [IO.Path]::GetRelativePath($SkillRoot, $file.FullName).Replace('\', '/')
        Marker = if ($file.Name -eq 'SKILL.md') { 'name: powershell-guardrails' } else {
          ([string](Get-Content -LiteralPath $file.FullName -TotalCount 1)).Trim()
        }
      }
    }
  }
  $reader = if ($PSCmdlet.ParameterSetName -eq 'File') { [IO.File]::OpenText($TracePath) } else { [IO.StringReader]::new($Trace) }
  $usage = $null
  try {
    while ($null -ne ($line = $reader.ReadLine())) {
      try { $event = ConvertFrom-Json -InputObject $line -AsHashtable -NoEnumerate -ErrorAction Stop } catch { continue }
      if ($event -isnot [System.Collections.IDictionary]) { continue }
      if ($event['type'] -eq 'turn.completed' -and $event.Contains('usage')) { $usage = $event.usage }
      if (-not $SkillRoot -or $event['type'] -ne 'item.completed') { continue }
      $item = $event['item']
      if ($item -isnot [System.Collections.IDictionary] -or $item['type'] -ne 'command_execution' -or $item['command'] -isnot [string]) { continue }
      $workingDirectory = $Workspace
      if ($item['cwd'] -is [string]) {
        try {
          $workingDirectory = if ([IO.Path]::IsPathFullyQualified($item.cwd)) { [IO.Path]::GetFullPath($item.cwd) }
          elseif ($Workspace) { [IO.Path]::GetFullPath($item.cwd, $Workspace) } else { $null }
        } catch { $workingDirectory = $null }
      }
      foreach ($request in @(Get-LiteralReadPaths -Command $item.command -WorkingDirectory $workingDirectory)) {
        if ($request.Unresolved) { $null = $unresolved.Add($item.command); continue }
        if (-not $files.ContainsKey($request.Path)) { continue }
        $file = $files[$request.Path]
        $output = $item['aggregated_output']
        $successful = $item['status'] -eq 'completed' -and
          ($item['exit_code'] -is [int] -or $item['exit_code'] -is [long]) -and $item['exit_code'] -eq 0
        if (-not $successful -and $output -is [string] -and $output -match '(?i)blocked by policy|rejected by policy|denied by policy') {
          $null = $rejected.Add($file.Relative)
        }
        if ($successful -and $output -is [string] -and $file.Marker -and $output.Contains($file.Marker, [StringComparison]::OrdinalIgnoreCase)) {
          $null = $reads.Add($file.Relative)
        } else {
          # A later success must not erase an earlier failed/rejected read.
          $null = $unverified.Add($file.Relative)
        }
      }
    }
  } finally { $reader.Dispose() }
  [pscustomobject]@{
    skillRead = $reads.Contains('SKILL.md')
    referenceReads = @($reads | Where-Object { $_ -like 'references/*' } | Sort-Object)
    unverifiedReads = @($unverified | Sort-Object)
    rejectedReads = @($rejected | Sort-Object)
    unresolvedReads = @($unresolved | Sort-Object)
    usage = $usage
  }
}

Export-ModuleMember -Function Get-SkillReadEvidence
