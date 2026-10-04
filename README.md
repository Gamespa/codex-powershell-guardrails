# PowerShell Guardrails

A focused Codex skill for fragile PowerShell parser boundaries, native argument
passing, command outcomes, Unicode transport, and uncertain job state.
Ordinary single-shell commands and pure Bash tasks should bypass the skill.

The runtime entrypoint is `powershell-guardrails/SKILL.md`. Conditional examples
live in `references/pitfalls.md`; maintenance scenarios live in
`references/pressure-scenarios.md`. The guidance is model-independent: a newer
model does not change PowerShell syntax or process identity requirements.

## Installation

Current local discovery uses `.agents/skills`. For a personal installation,
copy the contents into one skill directory:

```powershell
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
  references/pitfalls.md         Conditional technical examples
  references/pressure-scenarios.md  Outcome-based maintenance scenarios
scripts/
  verify.ps1                    Complete local validation entrypoint
  verify-skill.ps1               Required metadata, references, example/script syntax
  verify-pressure-scenarios.ps1  Model-case schema and negative-control checks
  verify-behavior.ps1            Executable local regressions
  evaluate-model.ps1             Optional no-skill/original/updated comparison
tests/model-cases.json          Model prompts and observable expected outcomes
artifacts/                       Ignored model-evaluation results and JSONL traces
```

## Local Verification

Requirements: PowerShell 7.3 or later, Git, and ripgrep on PATH. Runtime guidance
also covers Windows PowerShell 5.1; the local regression suite runs in PowerShell
7.3+ and does not claim full Windows PowerShell 5.1 coverage.

```powershell
pwsh -NoLogo -NoProfile -NonInteractive -File .\scripts\verify.ps1
```

The chain validates required metadata and local links, parses PowerShell
examples/scripts, validates the model-case schema, runs disposable local
behavior checks, and checks `git diff --check`. Native Git failures explicitly
fail the chain. No model calls, remote hosts, real tokens, or unrelated process
cleanup are involved.

The portable metadata check accepts required string fields in any order,
optional metadata, and multiline descriptions. It is not a full YAML parser.
For full YAML/skill-format validation, also use the installed skill-creator's
`quick_validate.py` with Python and PyYAML when available.

Use process-scoped `-ExecutionPolicy Bypass` only if a trusted, authorized script
is blocked by local PowerShell execution policy. It is not part of the default
command and cannot override host or Group Policy restrictions.

## Model Comparison

Requirements: PowerShell 7.3+, authenticated Codex CLI with `exec --json`, `--ignore-user-config`,
`--ephemeral`, schema support, and access to the explicitly chosen model. This
optional command uses account quota; it is separate from the local verifier.

```powershell
pwsh -NoLogo -NoProfile -NonInteractive -File .\scripts\evaluate-model.ps1 -Model gpt-6.1-sol
```

The default baseline is commit `377c95576f9afff270ec59c65877f330e305d5d6`, the
pre-update revision reviewed for this migration. Use `-BaselineRef` to compare
another Git revision and `-Repeats` for repeated samples. Pin the baseline
instead of silently changing it to HEAD after this update is committed.

Runs use separate read-only workspaces, ignore user configuration, and disable
common personal copies of this skill without editing those copies. The default
`provided-content` mode supplies each candidate's entrypoint and technical
reference directly in the prompt and requests no tools. This tests command
design with different instructions, not automatic discovery or progressive
reference loading. Commands are proposed, not executed.

Use `-Mode discovery` for candidates under `.agents/skills`, with Markdown reads
permitted. Inspect traces for successful loading. A policy-rejected candidate
read invalidates that arm even if the model subsequently answers from its
description. Do not reroute a denied read through another shell or API.

Each arm answers the same 12 cases, including four negative controls. Outputs
contain commands, routing self-reports, completeness/syntax checks, elapsed
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

See [official skill evaluation guidance](https://developers.openai.com/blog/eval-skills).

## Maintenance

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
