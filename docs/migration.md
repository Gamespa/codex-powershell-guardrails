# Refactor Migration

The published `powershell-guardrails/` package, its name, Windows/Core pwsh 7.6+
requirement, invocation policy, and trigger boundaries are unchanged. Personal
installed copies and user configuration are not updated by this refactor.

## Evaluation results

`results.json` is always a JSON array, including a single run. Consumers that
previously treated one run as an object must select its array element instead.
Existing fields and statuses remain. Two diagnostic fields are added:

- `responseErrors`: validation messages for malformed JSON, missing answers,
  or invalid answer fields.
- `processError`: process startup or stdin transport error, otherwise null.

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
The orchestration module owns artifact writes; other modules return data.

`scripts/read-skill-trace.ps1` remains a compatibility import shim. New code should
import `scripts/lib/trace.psm1`. Behavior suites moved to `tests/behavior/`, with
shared disposable fixture helpers in `tests/helpers.ps1`; run them through
`scripts/verify-behavior.ps1` or the full `scripts/verify.ps1` chain.

The Python validator retains its CLI and `validate(root)` entrypoint. Its
frontmatter, interface, policy, and dependency checks are now separate functions.

README evaluation and maintenance details moved to [evaluation](evaluation.md)
and [maintenance](maintenance.md). Update bookmarks to those documents. Historical
host observations remain in [maintenance scenarios](../tests/pressure-scenarios.md).
