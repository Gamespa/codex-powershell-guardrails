function Assert-GuardrailsRuntime {
  param($Version, [string]$Edition, [PlatformID]$Platform)
  if ($Platform -ne [PlatformID]::Win32NT) {
    throw "PowerShell Guardrails requires Windows and pwsh 7.6 or later; detected $Edition $Version on $Platform. Installing or enabling this skill on Linux or macOS is prohibited. Stop; do not install or upgrade PowerShell for this skill on this platform."
  }
  if ($Edition -ne 'Core' -or
      $Version.Major -lt 7 -or ($Version.Major -eq 7 -and $Version.Minor -lt 6)) {
    throw "PowerShell Guardrails requires Windows and pwsh 7.6 or later; detected $Edition $Version on $Platform. Stop repaired task execution in this session. Use an installed supported pwsh or follow references/runtime.md for authorized preparation, then recheck in that runtime. Analysis and proposed repairs can continue without installation."
  }
}

Assert-GuardrailsRuntime -Version $PSVersionTable.PSVersion `
  -Edition $PSVersionTable.PSEdition -Platform ([Environment]::OSVersion.Platform)
