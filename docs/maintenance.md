# Maintenance

## Implementation boundaries

The installable skill is self-contained under `powershell-guardrails/`; it does
not depend on repository tooling. Keep its entrypoint focused on essential
constraints and reference selection.

Repository command entrypoints delegate to internal modules in `scripts/lib/`.
Cases and candidate bundles are validated before model execution. Prompt and
result functions transform explicit inputs; the process helper manages a single
child and streams its logs. Evaluation orchestration owns artifact paths and
progress reporting; the artifact module handles locks and atomic result snapshots.
Importing modules does not launch a model or create files.

Offline PowerShell suites live in `tests/behavior/`. Each suite gets an isolated
scope and temporary directory through the common runner. Local process fixtures
exercise transport, timeout, and failure behavior without authentication or model
calls. Fixtures cover inherited pipes, bounded previews, and logs visible before
process completion. Fixed JSONL fixtures cover exact-path read evidence, while
injected local runners exercise evaluation artifact handling. Read-evidence tests
distinguish metadata from body, accumulate exact head/tail ranges, and reject
truncated, altered, or ambiguously attributed output. Separate processes
test lock contention, crash release, and concurrent snapshot readers. Python
unittest covers YAML contracts.
No additional test framework is required.

When changing a decision boundary, consult
[tests/pressure-scenarios.md](../tests/pressure-scenarios.md). Run `scripts/verify.ps1`
for structural checks and executable regressions. A repository verification
pass does not establish model behavior; comparisons remain a separate check.

Keep only constraints that affect decisions in the entrypoint; route conditional
detail to the relevant reference. Do not lock verification to exact headings,
line positions, wording, or arbitrary scenario counts. Maintain outcomes and
negative controls when changing trigger scope.

Run affected checks when behavior, scripts, examples, or links change. A
wording-only edit does not automatically require a model comparison. Honor
existing user authorization and host restrictions without inventing additional
approval steps.

## Local verification

Requirements: Windows, `pwsh` 7.6 or later, Git, ripgrep, and Python with PyYAML on PATH. The local suite
uses the same runtime gate as the installed skill. When Windows PowerShell 5.1
is present, it is invoked only to verify that the gate rejects it.
The runtime's production matching function is also exercised with version,
edition, and platform boundary inputs; this does not install or run those other
versions or operating systems. Native argument checks cover Standard and Windows
modes, including batch paths with spaces and child-only environment setup.

```powershell
pwsh -NoLogo -NoProfile -NonInteractive -File .\scripts\verify.ps1
```

The chain validates required metadata and local links, parses PowerShell
examples/scripts, validates the model-case schema, runs disposable local
behavior checks, and checks `git diff --check`. Native Git failures explicitly
fail the chain. No model calls, remote hosts, real tokens, or unrelated process
cleanup are involved.

The metadata check uses PyYAML to parse frontmatter and `agents/openai.yaml`,
accepting reordered fields and multiline descriptions. It rejects malformed YAML,
duplicate keys, empty instructions, and invalid UI, policy, and dependency types.
It also validates referenced icons. If PyYAML is absent, verification fails with a
dependency diagnostic; it does not silently fall back to regex parsing or install
dependencies. The installed skill-creator's `quick_validate.py` is an additional check.

Use process-scoped `-ExecutionPolicy Bypass` only if a trusted, authorized script
is blocked by local PowerShell execution policy. It is not part of the default
command and cannot override host or Group Policy restrictions.
