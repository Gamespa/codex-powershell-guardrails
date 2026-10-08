# Jobs and Cleanup

### Local sessions and detached services

Prefer the command runner's persistent session and polling if it supports the
needed lifetime. A yielded session is still running; poll its identifier
rather than launching a duplicate.

Use `Start-Process` when a service must outlive the tool session or the host
lacks persistent execution. Record PID, start time, executable, working
directory, and logs. Use unique state paths and `-WindowStyle Hidden` for
background services unless a visible window was requested. `-ArgumentList`
joins strings; it does not guarantee structured quote-preserving arguments.

Probe readiness with a bounded deadline/retry loop. Immediate connection
failure can be normal during startup. Correlate health, listener owner,
ancestry, and logs. A wrapper PID can differ from the listener's PID.

Before stopping, recheck identity. A stale PID can belong to another process
after reuse. Verify start time and executable as well as PID, inspect
descendants, and protect the current shell, agent, and ancestors. Stop only
the authorized root and verified descendants, not a broad name match.

For filesystem cleanup, resolve the intended root and inspect literal targets.
Verify containment with a directory-separator boundary; account for reparse
points when recursively traversing an untrusted tree. Use the inspected set
in the same shell. `New-Item` takes `-Path`, not `-LiteralPath`.

### Finite jobs, timeouts, and broken pipes

After timeout or `EPIPE`, inspect processes, logs, artifact timestamps, and
parsed outputs before retrying. Check whether the downstream tool accepts
stdin or exited early. A producer's broken pipe may be a secondary symptom.
A nonempty output file alone does not prove success.

Automated child PowerShell needs an explicit noninteractive script or command.
If a `.ps1` package wrapper shares generator stdin, use its `.cmd` entrypoint
when it fits the input contract. Validate child exit and artifacts.

### Remote jobs

Poll an attached SSH session when sufficient. To survive disconnect, use a
scheduler or detach stdin/stdout/stderr, retaining unique job identity, logs,
and final exit status. Inspect prior state before retrying; `kill -0` does not
prove ownership. Use a lock or scheduler when concurrent launch is possible.
