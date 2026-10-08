function Assert-GuardrailsRuntime {
  param($Version, [string]$Edition, [PlatformID]$Platform)
  if ($Platform -ne [PlatformID]::Win32NT) {
    throw "PowerShell Guardrails requires Windows and pwsh 7.6 or later; detected $Edition $Version on $Platform. Installing or enabling this skill on Linux or macOS is prohibited. Stop; do not install or upgrade PowerShell for this skill on this platform."
  }
  if ($Edition -ne 'Core' -or
      $Version.Major -lt 7 -or ($Version.Major -eq 7 -and $Version.Minor -lt 6)) {
    throw "PowerShell Guardrails requires Windows and pwsh 7.6 or later; detected $Edition $Version on $Platform. Stop repaired task execution in this session. Use an already installed supported pwsh; if none is available on Windows, automatically install PowerShell 7.6 or later when user authorization exists, otherwise request authorization first. Installation guide: https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows (with WinGet: winget install --id Microsoft.PowerShell --source winget; use winget upgrade for an older managed installation). Check installation success, resolve the installed pwsh path, and rerun this check in that runtime before resuming."
  }
}

Assert-GuardrailsRuntime -Version $PSVersionTable.PSVersion `
  -Edition $PSVersionTable.PSEdition -Platform ([Environment]::OSVersion.Platform)
