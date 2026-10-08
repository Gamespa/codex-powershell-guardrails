# PowerShell Guardrails

A focused Codex skill for fragile Windows PowerShell parser boundaries, native
arguments, encoding, exit status, and cleanup. Routine commands without these
risks and pure Bash tasks should bypass it.

The published package remains `powershell-guardrails/`. Its
[entrypoint](powershell-guardrails/SKILL.md) routes to focused references.
Executing repaired commands requires Windows and Core `pwsh` 7.6 or later;
reviewing commands does not require runtime preparation. Run the bundled runtime
check in the actual execution session before executing repairs. See
[runtime preparation](powershell-guardrails/references/runtime.md) if needed.

## Installation


Install and enable this skill only on Windows. Installation on Linux or macOS
is prohibited, even if `pwsh` is available. Check the target OS before copying
the skill, including when using a repository installer. An invocation from a
non-Windows environment must stop without installing or upgrading PowerShell.

Current local discovery uses `.agents/skills`. For a personal installation,
copy the contents into one skill directory:

```powershell
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw 'PowerShell Guardrails can only be installed on Windows; Linux and macOS are unsupported.'
}
$skillDestination = Join-Path $env:USERPROFILE '.agents\skills\powershell-guardrails'
$null = New-Item -ItemType Directory -Force -Path $skillDestination
Copy-Item -Path .\powershell-guardrails\* -Destination $skillDestination -Recurse -Force
```

For repository-scoped use, put the directory under `.agents/skills` in the
consumer repository instead. Keep this repository's published skill directory
at its existing path for repository installers.

Older Codex versions and some installers use `.codex/skills`, and existing
installations can remain discoverable there. Check the active client's skill
list before migrating. Avoid installing the same name in both locations:
Codex does not merge duplicate skills. This repository update does not alter
user-level copies or settings.

Invoke explicitly with `Use $powershell-guardrails`, or allow normal automatic
selection when the request matches the narrowed description. UI metadata is in
`powershell-guardrails/agents/openai.yaml`; automatic invocation remains enabled.

See [official local skill discovery](https://learn.chatgpt.com/docs/build-skills).

## Quick verification

Requirements: Windows, `pwsh` 7.6+, Git, ripgrep, and Python with PyYAML on PATH.

```powershell
pwsh -NoLogo -NoProfile -NonInteractive -File .\scripts\verify.ps1
```

This checks metadata, local links, PowerShell syntax, evaluation cases, offline
regressions, and Git whitespace errors. It does not call models or remote hosts.

## Documentation

- [Maintenance and verification](docs/maintenance.md): implementation boundaries,
  dependencies, and regression coverage.
- [Model evaluation](docs/evaluation.md): optional quota-consuming comparisons,
  discovery modes, artifacts, and interpretation limits.
- [Semantic evaluation](docs/semantic-evaluation.md): isolated execution, five
  behavior validators, coverage and pass-rate reporting; requires a provisioned
  Windows Hyper-V container backend only when executing model answers.
- [Migration notes](docs/migration.md): result format and internal file changes.
- [Maintenance scenarios](tests/pressure-scenarios.md): observable outcomes and
  version-specific historical evidence.

Only `powershell-guardrails/` is installed. Repository tooling is in `scripts/`,
internal modules in `scripts/lib/`, and offline suites in `tests/`.

## License

MIT. See [LICENSE](LICENSE).
