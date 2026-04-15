# Codex triage report: Ralph Pipeline Hardening

- Date: 2026-04-15
- Plan: feat/ralph-pipeline-hardening
- Base branch: main
- Triager: Claude Code (main context)
- Self-review cross-ref: yes
- Total Codex findings: 3
- After triage: ACTION_REQUIRED=2, WORTH_CONSIDERING=1, DISMISSED=0

## Triage context

- Active plan: docs/plans/active (archived — see eventual-toasting-kitten.md)
- Self-review report: docs/reports/self-review-2026-04-15-ralph-pipeline-hardening.md
- Verify report: docs/reports/verify-2026-04-15-ralph-pipeline-hardening.md
- Implementation context summary: Shared config module, hardcoded value elimination, signal handler addition, race condition fixes, numeric validation. Signal handlers are new code — not yet battle-tested in production. Exit code semantics in pipeline are pre-existing but extended by this PR.

## ACTION_REQUIRED

| # | Codex finding | Triage rationale | Affected file(s) |
|---|---------------|------------------|-------------------|
| 1 | [P1] INT/TERM trap does not call `exit` — orchestrator continues after cleanup | Real bug: `cleanup_on_exit` kills children and removes PID files but never exits. The main polling loop resumes and may restart slices. Signal handling is explicitly in scope (AC3). | `scripts/ralph-orchestrator.sh:89-119` |
| 2 | [P1] EXIT trap overwrites "partial" status with "interrupted" on non-zero exit | Real bug: `create_unified_pr()` writes `status = "partial"` then returns 1. The EXIT trap catches `$? != 0` and overwrites to "interrupted", losing the accurate failure state. Status accuracy is in scope (race condition fixes). | `scripts/ralph-orchestrator.sh:110-114`, `scripts/ralph-orchestrator.sh:934-942` |

## WORTH_CONSIDERING

| # | Codex finding | Triage rationale | Affected file(s) |
|---|---------------|------------------|-------------------|
| 3 | [P2] Missing `gh` returns exit code 1, misinterpreted as "codex ACTION_REQUIRED" by caller | Exit code collision: `run_outer_loop` returns 1 for both `gh_unavailable` and codex ACTION_REQUIRED. Preflight probe warns but doesn't block. Impact is wasted cycles until max_iterations, not data loss. | `scripts/ralph-pipeline.sh:775-778`, `scripts/ralph-pipeline.sh:975-986` |

## DISMISSED

| # | Codex finding | Dismissal reason | Category |
|---|---------------|------------------|----------|

(none)

Categories: false-positive, already-addressed, style-preference, out-of-scope, context-aware-safe
