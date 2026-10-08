# Refactor Migration

The published `powershell-guardrails/` package, its name, Windows/Core pwsh 7.6+
requirement, invocation policy, and trigger boundaries are unchanged. Personal
installed copies and user configuration are not updated by this refactor.

## Evaluation results

Model results now also contain `semantics.cases` and `semantics.summary`. The
existing run status still describes generation and response checks. Semantic
failures and infrastructure errors are separate and fail the CLI when requested.
`-SemanticImage` opts into isolated execution; the default is `not-evaluated`.
The new `scripts/evaluate-semantics.ps1` evaluates saved answers without a model
call. Five cases now append public execution contracts, so rerun all comparison
arms before comparing semantic rates. See [semantic evaluation](semantic-evaluation.md).

`results.json` is always a JSON array, including a single run. Consumers that
previously treated one run as an object must select its array element instead.
Read-evidence fields have a breaking change: `skillRead`, `referenceReads`, and
`triggerCorrect` are removed. Use `entrypoint` and `fileReads` for structured
per-file coverage and attempts, and `discoveryCorrect` for implicit discovery.
Metadata-only reads can establish discovery but cannot establish body loading;
check `entrypoint.level` for that. Explicit mentions are excluded from the
discovery metric. See [the evidence contract](evaluation.md) for levels and ranges.
Other diagnostic fields include:

- `responseErrors`: validation messages for malformed JSON, missing answers,
  or invalid answer fields.
- `processError`: process startup or stdin transport error, otherwise null.
- `rejectedReads`: candidate paths whose completed command events report a policy rejection.
- `unresolvedReads`: read commands whose paths or attribution cannot be verified.

Discovery now applies the same structured read-evidence checks as implicit mode.
Relative paths must resolve from the supplied workspace or event `cwd`; matching
a filename or prose mention is insufficient. Failed reads remain recorded even if
a later attempt succeeds. Invalid evidence leaves `discoveryCorrect` null. Callers
of `Get-SkillReadEvidence` should supply `-Workspace` for relative paths, or use
fully qualified paths. `-TracePath` supports reading complete JSONL logs from disk.

Malformed or missing answers now produce `response-check-failed` records. The
runner preserves raw answers, stdout JSONL, and stderr, saves each result, and
fails after the selected runs finish. A process failure or timeout remains
`unavailable`; trigger mismatches remain reported as false rather than failing
an otherwise valid run. These statuses do not establish command correctness.

Reusing an output directory containing `results.json` or a selected run directory
now fails before launching any model. Use a fresh directory to avoid overwriting
evidence or counting stale answers. Case IDs must be portable filename components
(letters, digits, underscores, and hyphens, beginning with a letter or digit), and
variant selections must be nonempty and distinct.

## Maintenance code

Existing command entrypoints and parameters under `scripts/` remain available.
Evaluation internals now live in `scripts/lib/`: cases, candidate bundles,
prompts, process lifecycle, trace evidence, result analysis, and orchestration.
Modules export functions and perform no evaluation or filesystem writes on import.
The orchestration module chooses artifact paths. The process module streams logs
to those paths; the artifact module owns output locks and atomic result replacement.
The internal process helper returns 64 KiB diagnostic previews and truncation flags;
consumers needing full output must use its `StdoutPath` and `StderrPath` files.
Injected test runners can accept these two extra positional arguments after timeout.
The public evaluation CLI parameters are unchanged.

Output directories now contain a persistent `.evaluation.lock` file whose OS
handle, rather than its existence, indicates ownership. A crash releases the lock.
Result snapshots are replaced atomically, preserving the previous file when a
replacement fails. See [artifact lifecycle](evaluation.md#process-and-artifact-lifecycle).

`scripts/read-skill-trace.ps1` remains a compatibility import shim. New code should
import `scripts/lib/trace.psm1`. Behavior suites moved to `tests/behavior/`, with
shared disposable fixture helpers in `tests/helpers.ps1`; run them through
`scripts/verify-behavior.ps1` or the full `scripts/verify.ps1` chain.

The Python validator retains its CLI and `validate(root)` entrypoint. Its
frontmatter, interface, policy, and dependency checks are now separate functions.

README evaluation and maintenance details moved to [evaluation](evaluation.md)
and [maintenance](maintenance.md). Update bookmarks to those documents. Historical
host observations remain in [maintenance scenarios](../tests/pressure-scenarios.md).
