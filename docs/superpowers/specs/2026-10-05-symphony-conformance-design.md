# Symphony Conformance Design

## Purpose

Bring the existing Elixir/OTP Symphony implementation into conformance with the repository's
language-agnostic `SPEC.md`. The implementation remains the product baseline: this work does not
replace its tracker adapters, scheduler, worker model, dashboard, or optional SSH extension.

The immediate success criterion is a deterministic, platform-safe implementation that satisfies
the specification's required behavior and the project's conformance suite. The current Windows
test failures demonstrate that the filesystem and command boundaries do not consistently preserve
absolute paths or execute test-provided command shims.

## Scope

The work covers the required layers from `SPEC.md`:

- workflow loading, typed configuration, validation, and last-known-good reload behavior;
- tracker normalization, candidate selection, reconciliation, claims, concurrency, and retries;
- collision-safe workspace creation, hooks, cleanup, and path containment;
- Codex app-server startup, streamed turn processing, timeouts, approvals, and dynamic tools;
- structured runtime state and the existing status/API projections; and
- deterministic tests for core behavior and platform-specific boundary handling.

Existing optional features, including provider-native tools, LiveView/API status, and SSH workers,
remain supported and are verified as extensions. This work does not redesign the user interface,
introduce a persistent scheduler database, or make tracker mutations from the orchestrator.

## Architecture

The current dependency direction remains intact:

```text
WORKFLOW.md -> WorkflowStore -> Config -> Tracker / Workspace / AppServer
                                        \-> Orchestrator -> Status surfaces
```

`Orchestrator` remains the only authority for claims, active tasks, retry queue entries, and
aggregate metrics. Tracker adapters own provider API differences and produce normalized `Issue`
records. `Workspace` owns workspace-key generation, containment validation, hooks, and removal.
`AgentRunner` composes one worker attempt; `Codex.AppServer` owns the JSONL protocol and emits
timestamped events upward. The dashboard and JSON API read a snapshot of orchestrator state only.

## Runtime Flow

1. Startup loads and validates `WORKFLOW.md`, resolves the configured workspace root, validates
   the tracker configuration, then schedules terminal-workspace cleanup and the first poll.
2. Each poll reloads dynamic configuration, reads active candidates, normalizes state and labels,
   reconciles currently claimed work, and selects dispatchable issues in priority order subject to
   global and per-state concurrency limits.
3. Before creating a task, the orchestrator claims the opaque issue ID. A worker then creates or
   reuses the deterministic workspace, runs `after_create` only for a newly created directory,
   runs `before_run`, renders the strict prompt, and starts Codex in that workspace.
4. Agent updates are folded into the owning running entry and aggregate token/rate-limit state.
   A normal turn checks the tracker before continuing; an issue that stays active may continue up
   to `agent.max_turns`.
5. A normal worker exit schedules a short reconciliation continuation. Operational failures
   schedule capped exponential backoff. Terminal or no-longer-routable issues stop active work,
   cancel retries, release claims, and remove their workspaces only after the worker has stopped.

## Platform Boundary Contract

Filesystem and command execution are explicit adapters rather than incidental string handling.

- A configured absolute path stays absolute on the host OS. Windows drive and UNC paths are never
  re-expanded relative to the workflow directory or accidentally interpreted as YAML escapes.
- Workspace containment compares canonical host paths, rejects the root itself, traversal, and
  symlink escapes, and never removes a path outside the configured root.
- Local hooks and app-server commands use the correct host command mechanism. POSIX shell use is
  retained only where the configuration explicitly requests a shell command; test doubles and
  executable lookup remain observable across Windows and POSIX.
- Remote execution remains explicitly POSIX-over-SSH and continues to quote remote shell paths
  independently of the local host's path rules.
- Text-rendered status snapshots normalize line endings at the assertion boundary, preserving
  human-visible content while avoiding host-only failures.

## Error Handling and Safety

Configuration parse or validation failures prevent initial startup. Failed later reloads preserve
the last valid settings and are logged. Workspace preparation and `before_run` failures fail the
current attempt; `after_run` and `before_remove` failures are logged without preventing cleanup.

App-server response, stream, stall, protocol, input-required, approval, and tool errors are
mapped into explicit worker outcomes so the orchestrator can either block or retry according to
the configured policy. Secrets stay host-side: declared tracker token environment variables are
removed from local and remote Codex child environments, while provider-native tools execute with
the session-bound host credential.

## Verification Strategy

Tests are organized around `SPEC.md` sections 17 and 18:

- configuration/workflow tests cover front matter, defaults, environment and path resolution,
  validation, strict templates, and reload behavior;
- workspace tests cover key collisions, lifecycle hooks, cleanup ordering, path containment, and
  Windows absolute paths;
- tracker tests cover every supported adapter's normalization, paging, provider validation, and
  host-side dynamic tools;
- orchestrator tests cover claims, sorting, concurrency, reconciliation, retry backoff, terminal
  cancellation, restart recovery, and runtime snapshot data; and
- app-server tests cover startup payloads, line buffering, timeouts, event propagation,
  approvals, input blockers, tool calls, and credential scrubbing.

Run focused regression tests while repairing each boundary, then the full deterministic suite,
format/lint checks, and the spec-check task. Live tracker/Codex tests remain opt-in and are not
required for the deterministic conformance result.
