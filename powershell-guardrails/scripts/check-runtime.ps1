function Assert-GuardrailsRuntime {
  param($Version, [string]$Edition, [PlatformID]$Platform)
  if ($Platform -ne [PlatformID]::Win32NT -or $Edition -ne 'Core' -or
      $Version.Major -ne 7 -or $Version.Minor -ne 6) {
    throw "PowerShell Guardrails requires Windows and pwsh 7.6.x; detected $Edition $Version on $Platform. Use an already available supported runtime; this skill does not install or upgrade PowerShell."
  }
}

Assert-GuardrailsRuntime -Version $PSVersionTable.PSVersion `
  -Edition $PSVersionTable.PSEdition -Platform ([Environment]::OSVersion.Platform)
