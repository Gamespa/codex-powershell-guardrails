# Windows Diagnostics

- **Resolution:** Use `Get-Command <tool> -All` and `where.exe <tool>` when
  aliases or packaged shims are suspect. Discover bundled runtime paths through
  the host's dependency tool rather than caching plugin paths.
- **Execution policy:** A local `PSSecurityException` differs from host denial.
  Process-scoped `-ExecutionPolicy Bypass` can address local policy for a trusted,
  authorized script; it cannot override Group Policy or host restrictions.
- **Host rejection:** `Remove-Item -Force` can trigger built-in dangerous-command
  checks before PowerShell starts; `approval_policy=never` may reject it even under
  Full Access with empty `matchedRules`. This is a possible cause, not proof of the
  exact check or a PowerShell/ACL error. Record command, policy, and backend version.
  Preserve rejected targets, report remaining work, and never retry by removing
  flags, changing shells/APIs, or weakening policy. Independent authorized work may
  continue. Before any rejection, use `-Force` only when needed; keep optional cleanup
  separate from installation/copying and skip deletion when no obsolete files exist.
- **curl / Schannel:** Use `curl.exe` when command resolution is ambiguous.
  Cross-check a Schannel failure with another client or
  logs before declaring an outage; retain native and HTTP status separately.

## Sources

- [PowerShell execution policies](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)
