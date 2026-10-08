Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'process.psm1')

function Invoke-SemanticContainer {
  param([string]$Image, [string]$BundleDirectory, [int]$TimeoutSeconds = 20,
    # Internal transport seam for offline lifecycle tests; public commands expose no override.
    [string]$DockerExecutable, [scriptblock]$DockerRunner = {
      param($exe, $arguments, $timeout)
      Invoke-EvaluationProcess -Executable $exe -Arguments $arguments -Prompt '' -TimeoutSeconds $timeout
    })
  $ErrorActionPreference = 'Stop'
  $name = 'guardrails-sem-' + [guid]::NewGuid().ToString('N')
  $created = $false
  $result = @{ infrastructureError = $null; observation = $null; imageId = $null; container = $name }
  try {
    if (-not $Image -or $Image.StartsWith('-')) { throw 'A trusted, pre-provisioned Windows container image is required.' }
    if (-not $DockerExecutable) { $DockerExecutable = (Get-Command docker -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
    $invoke = {
      param([string[]]$Arguments, [int]$Timeout = 30)
      $response = & $DockerRunner $DockerExecutable $Arguments $Timeout
      if ($response.ExitCode -ne 0 -or $response.TimedOut -or $response.Error -or $response.StdoutTruncated -or $response.StderrTruncated) {
        throw "Container operation failed ($($Arguments[0])): $($response.Error) $($response.Stderr) $($response.Stdout)"
      }
      $response.Stdout
    }
    $imageInfo = (& $invoke @('image', 'inspect', '--format', '{{json .}}', $Image)) | ConvertFrom-Json -AsHashtable
    if ($imageInfo.Os -ne 'windows' -or $imageInfo.Id -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Semantic execution requires a local Windows image with an immutable image ID.' }
    if ($imageInfo.Config['Volumes'] -and $imageInfo.Config.Volumes.Count) { throw 'Image-declared volumes are not allowed.' }
    $result.imageId = $imageInfo.Id
    $arguments = @('create', '--pull', 'never', '--name', $name, '--label', "guardrails.semantic=$name",
      '--isolation', 'hyperv', '--network', 'none', '--memory', '1g', '--cpu-count', '1',
      '--user', 'ContainerUser', '--entrypoint', 'pwsh.exe', $imageInfo.Id,
      '-NoLogo', '-NoProfile', '-NonInteractive', '-File', 'C:\guardrails\semantic-worker.ps1')
    # Set before create so an interrupted create is also checked for owned cleanup.
    $created = $true
    $null = & $invoke $arguments
    $configuration = (& $invoke @('inspect', '--format', '{{json .}}', $name)) | ConvertFrom-Json -AsHashtable
    if ($configuration.HostConfig.Isolation -ne 'hyperv' -or $configuration.HostConfig.NetworkMode -ne 'none' -or
        $configuration.Config.User -ne 'ContainerUser' -or $configuration.Mounts.Count -ne 0 -or
        $configuration.Config.Labels['guardrails.semantic'] -ne $name) { throw 'Container isolation contract was not applied.' }
    $null = & $invoke @('cp', $BundleDirectory, "${name}:C:\guardrails")
    $output = & $invoke @('start', '--attach', $name) ($TimeoutSeconds + 30)
    $observation = ConvertFrom-Json -InputObject $output -AsHashtable -NoEnumerate -ErrorAction Stop
    if ($observation -isnot [Collections.IDictionary] -or $observation['protocol'] -ne 1) { throw 'Invalid semantic worker protocol.' }
    if ($observation['infrastructureError']) { throw $observation.infrastructureError }
    if ($observation['execution'] -isnot [Collections.IDictionary] -or $observation['artifacts'] -isnot [Collections.IDictionary]) { throw 'Missing semantic observation.' }
    foreach ($field in @('ExitCode', 'TimedOut', 'Error', 'Stdout', 'Stderr', 'StdoutTruncated', 'StderrTruncated')) {
      if (-not $observation.execution.Contains($field)) { throw "Missing execution field: $field" }
    }
    foreach ($field in @('TimedOut', 'StdoutTruncated', 'StderrTruncated')) {
      if ($observation.execution[$field] -isnot [bool]) { throw "Invalid execution flag: $field" }
    }
    foreach ($field in @('Stdout', 'Stderr')) {
      if ($observation.execution[$field] -isnot [string]) { throw "Invalid execution stream: $field" }
    }
    if (($null -ne $observation.execution.ExitCode -and $observation.execution.ExitCode -isnot [long] -and $observation.execution.ExitCode -isnot [int]) -or
        $observation['runtime'] -isnot [string]) { throw 'Invalid worker exit code or runtime.' }
    $result.observation = $observation
  } catch { $result.infrastructureError = $_.Exception.Message }
  finally {
    if ($created) {
      try {
        # Do not remove an unrelated container after an ambiguous create result.
        $owner = & $DockerRunner $DockerExecutable @('inspect', '--format', '{{index .Config.Labels "guardrails.semantic"}}', $name) 30
        if ($owner.ExitCode -eq 0 -and $owner.Stdout.Trim() -ceq $name) {
          $removed = & $DockerRunner $DockerExecutable @('rm', '--force', $name) 30
          if ($removed.ExitCode -ne 0 -or $removed.TimedOut -or $removed.Error) { throw "Unable to remove owned container $name." }
        } else { throw "Unable to verify cleanup of $name; inspect this container before retrying." }
      } catch { $result.infrastructureError = (@($result.infrastructureError, $_.Exception.Message) | Where-Object { $_ }) -join ' | ' }
    }
  }
  [pscustomobject]$result
}

Export-ModuleMember -Function Invoke-SemanticContainer
