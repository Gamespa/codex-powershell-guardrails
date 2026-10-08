foreach ($runtimeCase in @(
@{ Version = '7.6.0'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $true },
@{ Version = '7.6.1'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $true },
@{ Version = '7.6.99'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $true },
@{ Version = '7.5.9'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $false },
@{ Version = '7.7.0'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $true },
@{ Version = '8.0.0'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $true },
@{ Version = '6.9.0'; Edition = 'Core'; Platform = 'Win32NT'; Accepted = $false },
@{ Version = '5.1.0'; Edition = 'Desktop'; Platform = 'Win32NT'; Accepted = $false },
@{ Version = '7.6.1'; Edition = 'Core'; Platform = 'Unix'; Accepted = $false },
@{ Version = '7.6.1'; Edition = 'Desktop'; Platform = 'Win32NT'; Accepted = $false }
)) {
$accepted = $true
try {
  Assert-GuardrailsRuntime -Version ([version]$runtimeCase.Version) -Edition $runtimeCase.Edition -Platform $runtimeCase.Platform
} catch {
  if ($_.Exception.Message -notmatch 'requires Windows and pwsh 7\.6 or later') { throw }
  $accepted = $false
  if ($runtimeCase.Platform -ne 'Win32NT') {
    Assert-Behavior ($_.Exception.Message -match 'Installing or enabling this skill on Linux or macOS is prohibited' -and
      $_.Exception.Message -notmatch 'winget|https://') 'Unsupported platform diagnostic entered the Windows installation flow.'
  }
}
Assert-Behavior ($accepted -eq $runtimeCase.Accepted) "Runtime boundary failed for $($runtimeCase.Version)/$($runtimeCase.Edition)/$($runtimeCase.Platform)."
}
$childVersion = & $childShell -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'
$childVersionExit = $LASTEXITCODE
Assert-Behavior ($childVersionExit -eq 0 -and $childVersion -ceq $PSVersionTable.PSVersion.ToString()) 'Child PowerShell differs from the checked runtime.'

$legacyShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
if (Test-Path -LiteralPath $legacyShell) {
# This trusted local gate must load before its runtime rejection can be tested.
# Process-scoped Bypass does not change persistent or Group Policy settings.
$runtimeOutput = & $legacyShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repositoryRoot 'powershell-guardrails/scripts/check-runtime.ps1') 2>&1
$runtimeExit = $LASTEXITCODE
$runtimeText = ($runtimeOutput -join "`n") -replace '\s+', ' '
Assert-Behavior ($runtimeExit -ne 0 -and $runtimeText -match 'requires Windows and pwsh 7\.6 or later') 'Windows PowerShell did not produce the expected runtime rejection.'
Assert-Behavior ($runtimeText -match 'references/runtime.md' -and $runtimeText -match 'Analysis and proposed repairs can continue') 'Unsupported runtime diagnostic omitted preparation routing or analysis allowance.'
}
