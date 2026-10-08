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

## Codex read-only commands rejected before startup

`blocked by policy` alone does not identify a dangerous command, an ACL failure,
or PowerShell execution policy. When an ordinary `Get-Content` is rejected before
startup in a Windows `codex exec` child, inspect that child's launch arguments,
effective permissions, approval policy, and backend selection; the parent app's
Full Access setting does not describe a separately configured child.

`--ignore-user-config` omits `$CODEX_HOME/config.toml`, including its
`[windows] sandbox = "elevated"` selection. A configured read-only permission
boundary and an enabled Windows sandbox backend are separate settings. In CLI
0.159.0, a disabled backend combined with managed filesystem restrictions and
`approval_policy=never` causes unmatched commands to be forbidden, even reads.
Check other config layers, requirements, and legacy feature selectors before
concluding that the backend is disabled; recheck behavior for other versions.

For an authorized repair of a confirmed missing selector, explicitly pass the
already provisioned, permitted backend, for example
`-c 'windows.sandbox="elevated"'`, while retaining `--ignore-user-config`,
`--sandbox read-only`, the existing approval policy, and applicable rules.
This restores enforcement of the intended boundary; it does not authorize
Full Access, broad allow rules, another-shell retries, or an automatic fallback
to a weaker backend. If setup is unavailable or rejection persists, preserve
the error and diagnose that failure before further execution.

Validate with a bounded authorized read under the intended sandbox and inspect
completed tool results and stderr/JSONL traces. CLI exit 0 and a plausible model
answer can coexist with rejected reads. Mark required-read evaluations invalid;
do not count them as successful Skill loading or as evidence of Skill quality.
Distinguish a proposed repair from a successfully tested repair.

## Sources

- [PowerShell execution policies](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)
- [Codex Windows sandbox configuration](https://learn.chatgpt.com/docs/windows/windows-sandbox)
- [Codex non-interactive configuration and traces](https://learn.chatgpt.com/docs/non-interactive-mode)
- [CLI 0.159.0 backend selection](https://github.com/openai/codex/blob/rust-v0.159.0/codex-rs/core/src/config/windows_sandbox_config.rs#L55-L85)
- [CLI 0.159.0 policy fallback](https://github.com/openai/codex/blob/rust-v0.159.0/codex-rs/core/src/exec_policy.rs#L746-L766)
