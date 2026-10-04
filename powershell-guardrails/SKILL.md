---
name: powershell-guardrails
description: Fix PowerShell commands crossing parser boundaries or mispassing native arguments. Use for related quoting, encoding, exit-code, or job-state failures.
---

# PowerShell Guardrails

Skip ordinary single-shell commands and pure Bash without a PowerShell layer.
Explicit user requirements override workflow preferences; existing authorization
still applies.

## Boundary Constraints

- **Expansion:** Keep child and remote variables in their owning parser.
  Prefer literal payloads or script files over nested escaping, and avoid
  introducing a child shell when the current shell can do the work.
- **Version:** PowerShell 7 supports `&&` and `||`; Windows PowerShell 5.1 does
  not. Native quoting depends on version, target executable, and
  `$PSNativeCommandArgumentPassing`, not just argument arrays.
- **Status:** Unexpected cmdlet errors must terminate validation. Capture
  `$LASTEXITCODE` immediately for native tools; `rg` uses 0 for matches,
  1 for no matches, and 2 for errors.
- **Encoding:** Unix-bound text needs LF and UTF-8 without BOM. Native stdin
  uses `$OutputEncoding`; writing a UTF-8 file is a separate operation.
- **Secrets:** Keep values out of argv and raw tool output. Filter sensitive
  matches inside the producing process; `rg --json` includes matching text.
- **Targets:** Inspect exact destructive targets and verify containment.
  Keep enumeration and action in one shell with literal paths where supported.
  Verify process identity beyond PID, and protect the shell, agent, and ancestors.
- **Jobs:** Poll an existing host session when its lifetime is sufficient.
  After timeout or broken pipe, inspect the prior job and its outputs before
  relaunching; cleanup targets only verified processes.
- **Policy:** Do not retry a host-rejected operation through equivalent
  syntax, another shell, or another API.

## References

Read only the reference for the affected boundary:

- [Arguments and expansion](references/arguments-and-expansion.md): native
  argument modes, batch environments, nested variables, interpolation, and
  statement pipelines.
- [SSH and encoding](references/ssh-and-encoding.md): remote expansion,
  Unicode stdin, LF/BOM, uploaded scripts, and shared-stdin pitfalls.
- [Execution and lifecycle](references/execution-and-lifecycle.md): exit
  status, credential metadata, API tokens, sessions, process identity,
  cleanup, and Windows-specific diagnostics.
