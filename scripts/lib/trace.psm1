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
      [pscustomobject]@{ Path = $null; Unresolved = $true }
      $directory = $null
      continue
    }
    if ($statement.PipelineElements.Count -ne 1 -or $statement.Background) {
      [pscustomobject]@{ Path = $null; Unresolved = $true }
    }
    foreach ($node in $statement.PipelineElements) {
      if ($node -isnot [Management.Automation.Language.CommandAst]) {
        [pscustomobject]@{ Path = $null; Unresolved = $true }; continue
      }
      if ($node.Redirections.Count) { [pscustomobject]@{ Path = $null; Unresolved = $true } }
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
            if ($i + 2 -eq $elements.Count) { $payload = $elements[$i + 1].Value }; break
          }
          if ($elements[$i].Extent.Text -notin @('-NoLogo', '-NoProfile', '-NonInteractive')) { break }
        }
        if ($null -ne $payload) {
          Get-LiteralReadPaths -Command $payload -WorkingDirectory $directory -Depth ($Depth + 1)
        } else { [pscustomobject]@{ Path = $null; Unresolved = $true } }
        continue
      }
      $isLocation = $name -in @('Set-Location', 'cd', 'sl', 'chdir')
      $isRead = $name -in @('Get-Content', 'gc', 'cat', 'type', 'Microsoft.PowerShell.Management\Get-Content')
      if (-not $isRead -and -not $isLocation) {
        [pscustomobject]@{ Path = $null; Unresolved = $true }
        $directory = $null
        continue
      }
      $operands = [Collections.Generic.List[object]]::new()
      $literal = $false
      $unknown = $false
      $selection = 'all'
      $count = 0
      $raw = $false
      for ($i = 1; $i -lt $node.CommandElements.Count; $i++) {
        $element = $node.CommandElements[$i]
        if ($element -is [Management.Automation.Language.CommandParameterAst]) {
          $parameter = $element.ParameterName
          if ($parameter -in @('Raw', 'Force')) {
            if ($element.Argument -or $isLocation) { $unknown = $true }
            if ($parameter -eq 'Raw') { $raw = $true }
            continue
          }
          if ($parameter -in @('TotalCount', 'First', 'Head', 'Tail', 'Last', 'Encoding', 'ErrorAction', 'ea')) {
            $argument = $element.Argument
            if (-not $argument -and $i + 1 -lt $node.CommandElements.Count) { $i++; $argument = $node.CommandElements[$i] }
            if ($parameter -in @('TotalCount', 'First', 'Head', 'Tail', 'Last')) {
              if ($selection -ne 'all' -or $isLocation -or
                  $argument -isnot [Management.Automation.Language.ConstantExpressionAst] -or
                  $argument.Value -isnot [int] -or $argument.Value -lt 0) { $unknown = $true }
              else {
                $count = $argument.Value
                $selection = if ($parameter -in @('Tail', 'Last')) { 'tail' } else { 'head' }
              }
            } elseif ($argument -isnot [Management.Automation.Language.StringConstantExpressionAst]) { $unknown = $true }
            elseif ($parameter -eq 'Encoding' -and ($isLocation -or $argument.Value -notin @('utf8', 'utf8BOM', 'utf8NoBOM'))) { $unknown = $true }
            elseif ($parameter -ne 'Encoding' -and $argument.Value -notin @('Stop', 'Continue', 'SilentlyContinue', 'Ignore')) { $unknown = $true }
            continue
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
      if (-not $operands.Count -or $unknown -or ($raw -and $selection -ne 'all') -or ($isLocation -and $operands.Count -ne 1)) {
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
          [pscustomobject]@{ Path = $path; Unresolved = $null -eq $path; Selection = $selection; Count = $count }
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
  $unverified = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $rejected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $unresolved = [Collections.Generic.HashSet[string]]::new()
  $files = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
  if ($SkillRoot) {
    foreach ($file in Get-ChildItem -LiteralPath $SkillRoot -Recurse -File | Where-Object Extension -in @('.md', '.ps1', '.psm1', '.yaml', '.yml')) {
      # Normalize line endings only. Ignore terminal newlines added by shell output;
      # substantive whitespace and case remain significant.
      $lines = @([IO.File]::ReadAllLines($file.FullName))
      $bodyStart = 0
      if ($file.Name -eq 'SKILL.md' -and $lines.Count -gt 0 -and $lines[0] -ceq '---') {
        for ($i = 1; $i -lt $lines.Count; $i++) {
          if ($lines[$i] -ceq '---') { $bodyStart = $i + 1; break }
        }
      }
      $bodyIndices = @(for ($i = $bodyStart; $i -lt $lines.Count; $i++) {
        if (-not [string]::IsNullOrWhiteSpace($lines[$i])) { $i }
      })
      $files[[IO.Path]::GetFullPath($file.FullName)] = [pscustomobject]@{
        Relative = [IO.Path]::GetRelativePath($SkillRoot, $file.FullName).Replace('\', '/')
        Lines = $lines; BodyStart = $bodyStart; BodyIndices = $bodyIndices
        Covered = [Collections.Generic.HashSet[int]]::new()
        MetadataRead = $false; VerifiedRead = $false
        Attempts = [Collections.Generic.List[object]]::new()
      }
    }
  }
  $reader = if ($PSCmdlet.ParameterSetName -eq 'File') { [IO.File]::OpenText($TracePath) } else { [IO.StringReader]::new($Trace) }
  $usage = $null
  $eventLine = 0
  try {
    while ($null -ne ($line = $reader.ReadLine())) {
      $eventLine++
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
      $requests = @(Get-LiteralReadPaths -Command $item.command -WorkingDirectory $workingDirectory)
      foreach ($request in $requests) {
        if ($request.Unresolved) { $null = $unresolved.Add($item.command); continue }
        if (-not $files.ContainsKey($request.Path)) { continue }
        $file = $files[$request.Path]
        $output = $item['aggregated_output']
        $successful = $item['status'] -eq 'completed' -and
          ($item['exit_code'] -is [int] -or $item['exit_code'] -is [long]) -and $item['exit_code'] -eq 0
        if (-not $successful -and $output -is [string] -and $output -match '(?i)blocked by policy|rejected by policy|denied by policy') {
          $null = $rejected.Add($file.Relative)
        }
        $start = 0
        $end = $file.Lines.Count
        if ($request.Selection -eq 'head') { $end = [math]::Min($end, $request.Count) }
        elseif ($request.Selection -eq 'tail') { $start = [math]::Max(0, $end - $request.Count) }
        $indices = @(for ($i = $start; $i -lt $end; $i++) { $i })
        $expected = (@(foreach ($i in $indices) { $file.Lines[$i] }) -join "`n").TrimEnd([char]10)
        $reason = if (-not $successful) { 'command-failed' }
          elseif ($requests.Count -ne 1) { 'ambiguous-output' }
          elseif ($output -isnot [string] -or
              $output.Replace("`r`n", "`n").TrimEnd([char]10) -cne $expected) { 'output-mismatch' }
          elseif ([string]::IsNullOrWhiteSpace($expected)) { 'no-content' }
          else { $null }
        $file.Attempts.Add([pscustomobject]@{
          traceLine = $eventLine; command = $item.command
          startLine = if ($indices.Count) { $start + 1 } else { $null }
          endLine = if ($indices.Count) { $end } else { $null }
          verified = $null -eq $reason; reason = $reason
        })
        if (-not $reason) {
          $file.VerifiedRead = $true
          foreach ($i in $indices) {
            if ($i -in $file.BodyIndices) { $null = $file.Covered.Add($i) }
            elseif ($i -lt $file.BodyStart -and
                -not [string]::IsNullOrWhiteSpace($file.Lines[$i])) { $file.MetadataRead = $true }
          }
        } else {
          # A later success must not erase an earlier failed/rejected read.
          $null = $unverified.Add($file.Relative)
        }
      }
    }
  } finally { $reader.Dispose() }
  $fileReads = @(foreach ($file in $files.Values | Sort-Object Relative) {
    $level = if ($file.BodyIndices.Count -gt 0 -and $file.Covered.Count -eq $file.BodyIndices.Count) { 'full-body' }
      elseif ($file.Covered.Count) { 'partial-body' }
      elseif ($file.MetadataRead) { 'metadata-only' }
      elseif ($file.Attempts.Count) { 'unverified' }
      else { 'none' }
    [pscustomobject]@{
      path = $file.Relative; level = $level; verifiedRead = $file.VerifiedRead
      bodyCoverage = [pscustomobject]@{
        coveredLines = $file.Covered.Count; totalLines = $file.BodyIndices.Count
        fraction = if ($file.BodyIndices.Count) { $file.Covered.Count / $file.BodyIndices.Count } else { $null }
      }
      attempts = @($file.Attempts.ToArray())
    }
  })
  [pscustomobject]@{
    entrypoint = @($fileReads | Where-Object path -eq 'SKILL.md') | Select-Object -First 1
    fileReads = $fileReads
    unverifiedReads = @($unverified | Sort-Object)
    rejectedReads = @($rejected | Sort-Object)
    unresolvedReads = @($unresolved | Sort-Object)
    usage = $usage
  }
}

Export-ModuleMember -Function Get-SkillReadEvidence
