# Model Evaluation

Commands below run from the repository root. For offline validation use
`scripts/verify.ps1`; it never calls a model. See [migration notes](migration.md)
for the stable result array and stricter input/output-directory validation.

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
common personal copies of this skill without editing those copies. The
Windows backend is explicitly set to `windows.sandbox="elevated"`; it must already
be provisioned and permitted. Ignoring user config would otherwise lose its backend
selection. The evaluator retains read-only permissions and does not install a
backend or fall back to weaker permissions when setup or command execution fails.
The default `provided-content` mode supplies each candidate's entrypoint and technical
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
records `entrypoint`, `fileReads`, `discoveryCorrect`, `unverifiedReads`,
`rejectedReads`, and `unresolvedReads`. `entrypoint` is the SKILL.md evidence;
`fileReads` includes every candidate Markdown, helper, and YAML file. Each contains:

- `path` and `verifiedRead`: whether an attributable, successful read returned
  the expected nonempty content. This can be metadata alone.
- `level`: `none`, `metadata-only`, `partial-body`, `full-body`, or `unverified`.
- `bodyCoverage`: `coveredLines`, `totalLines`, and `fraction` (0 to 1, or null
  for an empty body). Coverage counts nonblank source lines, excluding SKILL.md
  frontmatter. Other candidate files treat all content as body.
- `attempts`: trace line, command, one-based inclusive source range, verification
  result, and failure reason. Unsupported commands also remain in `unresolvedReads`.

Evidence requires a completed shell read with zero exit status and an exact
output match against the actual candidate file's requested range. Only CRLF/LF
and terminal newlines are normalized; case and substantive whitespace matter.
The parser supports literal `Get-Content` reads (including aliases), `-Raw`,
literal `-TotalCount`/`-Head`/`-First` or `-Tail`/`-Last` counts, literal location
changes, and simple literal PowerShell `-Command` wrappers. Relative paths use
the workspace or event `cwd`. Verified ranges from separate events accumulate
without double-counting. Reading only the first two manifest lines yields
`metadata-only`; a truncated full-read output yields `unverified`, not full coverage.

Each command event must have a single attributable file read. Multiple files,
extra output-producing commands, pipelines, redirections, dynamic expressions,
unsupported options, and mismatched outputs do not establish coverage. A shared
heading cannot authenticate several files. Command text is parsed, never executed.

Both discovery and implicit runs reject failed or unverified candidate reads.
This includes candidate Markdown, PowerShell helpers, and YAML metadata; a helper
read alone does not count as discovering the skill entrypoint.
Structured command failures identify policy rejection; unattributed stderr is
reported as unresolved evidence. A later successful read does not erase an earlier
failure. Invalid evidence leaves `discoveryCorrect` null. A later full read may
raise the coverage level while the earlier failure remains recorded and invalidates
the run. `discoveryCorrect` compares entrypoint `verifiedRead` with `shouldTrigger`
only for implicit, non-explicit cases; it measures observed discovery, not complete
instruction loading. Consult `entrypoint.level` separately for body loading.
Do not require every supporting reference to be read in full: references are
loaded on demand. This extractor does not
cover every possible tool protocol;
inspect raw traces before interpreting a missing read as a missed trigger. Trigger
mismatches are recorded as false, rather than being hidden by run completion.
Command semantics still require review against `expectedOutcome`. Model evaluations
consume account quota and are separate from the local verification chain.

## Process and artifact lifecycle

Stdout and stderr stream to `trace.jsonl` and `stderr.txt` while the child runs.
The process helper retains at most 64 KiB per stream as an in-memory diagnostic
preview; result analysis reads complete log files one line at a time. Individual
JSONL events are still parsed in memory. A process timeout or parent exit starts
a bounded cleanup/drain period (two seconds by default). An inherited pipe cannot
make the evaluator wait indefinitely. Drain timeout retains partial logs and
invalidates the run. If the parent already exited, surviving descendants are
reported for inspection; the runner does not kill processes by a stale parent PID.

An OS-backed exclusive handle on `.evaluation.lock` protects each output directory
before checking or creating run artifacts. A competing evaluator fails before
launching its model. The lock file remains after release; the OS releases ownership
when its process exits, including a crash. Do not delete an active lock file.

`results.json` is flushed to a temporary sibling file and atomically replaced
after each run. A failed replacement preserves the previous snapshot. Concurrent
Windows readers should allow delete sharing so they can retain an old file handle
during replacement. Existing results and run directories still require a fresh
output directory; releasing a lock does not authorize overwriting prior evidence.

See [official skill evaluation guidance](https://developers.openai.com/blog/eval-skills).
