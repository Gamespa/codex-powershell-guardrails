# PowerShell Guardrails

A focused Codex skill for fragile Windows PowerShell parser boundaries, native
arguments, encoding/redirection, exit status, and process cleanup. Execution
requires Windows and `pwsh` 7.6 or later. Routine commands without these risks and pure
Bash tasks should bypass the skill.

The runtime entrypoint is `powershell-guardrails/SKILL.md`. Conditional examples
are split by boundary under `powershell-guardrails/references/`. Maintenance
scenarios live in [tests/pressure-scenarios.md](tests/pressure-scenarios.md), outside
the installed skill. The guidance is model-independent: a newer
model does not change PowerShell syntax or process identity requirements.

Prefer an already installed `pwsh` 7.6 or later over Windows PowerShell 5.1.
Reviewing commands and proposing repairs do not require local runtime preparation.
Before executing repaired task commands, run `scripts/check-runtime.ps1` in the
actual execution session. Unsupported versions stop task execution with a diagnostic.
If no supported runtime exists, follow
[runtime preparation](powershell-guardrails/references/runtime.md), which centralizes
discovery, authorized installation, and rechecking. The runtime check only validates
and never installs software.
Child PowerShell commands use the checked installation's
`Join-Path $PSHOME 'pwsh.exe'`, rather than resolving a potentially different
installation through PATH. Recheck when changing execution environments.

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

## Repository Layout

```text
powershell-guardrails/
  SKILL.md                      Focused runtime constraints and reference routing
  agents/openai.yaml             Display metadata
  scripts/check-runtime.ps1      Windows and pwsh 7.6+ execution gate
  references/arguments-and-expansion.md  Native arguments, batch setup, expansion
  references/ssh-and-encoding.md         Remote payloads and Unicode transport
  references/execution-and-lifecycle.md  Status, secrets, jobs, Windows diagnostics
  references/runtime.md         Conditional runtime discovery and installation
scripts/
  verify.ps1                    Complete local validation entrypoint
  verify-skill.ps1               Required metadata, references, example/script syntax
  verify-pressure-scenarios.ps1  Model-case schema and negative-control checks
  verify-behavior.ps1            Executable local regressions
  evaluate-model.ps1             Optional no-skill/original/updated comparison
  read-skill-trace.ps1           Completed shell read evidence extraction
  validate-skill-yaml.py          Full YAML parsing and metadata validation
tests/model-cases.json          Model prompts and observable expected outcomes
tests/test_skill_yaml.py        Disposable YAML validation regressions
tests/pressure-scenarios.md     Outcome-based maintenance scenarios
artifacts/                       Ignored model-evaluation results and JSONL traces
```

## Local Verification

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

## Model Comparison

Requirements: Windows, `pwsh` 7.6 or later, authenticated Codex CLI with `exec --json`, `--ignore-user-config`,
`--ephemeral`, schema support, and access to the explicitly chosen model. This
optional command uses account quota; it is separate from the local verifier.

```powershell
pwsh -NoLogo -NoProfile -NonInteractive -File .\scripts\evaluate-model.ps1 -Model gpt-6.1-sol
```

The default baseline is commit `377c95576f9afff270ec59c65877f330e305d5d6`, the
pre-update revision reviewed for this migration. Use `-BaselineRef` to compare
another Git revision and `-Repeats` for repeated samples. Pin the baseline
instead of silently changing it to HEAD after this update is committed.
Use `-Variants` to select arms when an unchanged control need not be rerun.
The runner enumerates each revision's runtime references and bundled PowerShell
helpers, so comparisons also support the historical single-reference layout.
Maintenance scenarios are excluded from model input.

Runs use separate read-only workspaces, ignore user configuration, and disable
common personal copies of this skill without editing those copies. The default
`provided-content` mode supplies each candidate's entrypoint and technical
references and helper source directly in the prompt and requests no tools. This
tests command design with different instructions, not automatic discovery or progressive
reference loading. Commands are proposed, not executed.

Use `-Mode discovery` for candidates under `.agents/skills`, with Markdown and
helper-source reads permitted, but no script execution. Inspect traces for
successful loading. A policy-rejected candidate
read invalidates that arm even if the model subsequently answers from its
description. Do not reroute a denied read through another shell or API.

Each arm answers the same cases from `tests/model-cases.json`, including negative
controls. Outputs contain commands, routing self-reports, completeness/syntax checks, elapsed
time, and usage if exposed. Inspect `answers.json`, `trace.jsonl`, and
`results.json` under the printed artifact directory. Errors, timeouts, response
check failures, and detected discovery read rejections fail the command rather
than being recorded as passes. Artifact workspaces are retained for inspection
under the ignored output directory.

Self-reported per-case routing is not an actual invocation metric; grouped
cases share context. Syntax checks do not establish semantic correctness.
Review commands against `expectedOutcome` and test per-case discovery separately
before claiming trigger accuracy. One sample is diagnostic, not evidence of
consistent quality or speed improvements.

For independent activation checks, use `-Mode implicit`. Each case gets a fresh
process and workspace; the runner adds no candidate name, path, or instruction to
load it. Cases that mention the skill themselves are labeled `explicit` and must
be excluded from implicit-trigger accuracy. Candidate bundles include agent metadata.

```powershell
pwsh -NoLogo -NoProfile -NonInteractive -File .\scripts\evaluate-model.ps1 -Mode implicit -Variants updated -CaseIds nested_variables,ordinary_git
```

Use `-CaseIds` to select cases and `-Repeats` to repeat samples. `results.json`
records `skillRead`, `triggerCorrect`, `referenceReads`, and `unverifiedReads`.
Evidence requires a completed shell read with zero exit status and manifest or
reference content in its output. Failed or unverified attempted reads invalidate
the run. This extractor covers common shell reads, not all possible tool protocols;
inspect raw traces before interpreting a missing read as a missed trigger. Trigger
mismatches are recorded as false, rather than being hidden by run completion.
Command semantics still require review against `expectedOutcome`. Model evaluations
consume account quota and are separate from the local verification chain.

See [official skill evaluation guidance](https://developers.openai.com/blog/eval-skills).

## Maintenance

When changing a decision boundary, consult
[tests/pressure-scenarios.md](tests/pressure-scenarios.md). Run `scripts/verify.ps1`
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

## License

MIT. See `LICENSE`.
