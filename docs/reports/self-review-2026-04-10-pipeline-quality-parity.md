# Self-review report: pipeline-quality-parity

- Date: 2026-04-10
- Plan: pipeline-quality-parity (uncommitted working-tree changes)
- Reviewer: reviewer agent (autonomous)
- Scope: diff quality only

## Evidence reviewed

- `git diff HEAD` for all changed files (working tree)
- `git diff HEAD^ HEAD -- scripts/ralph-pipeline.sh` to compare old vs new Inner Loop phases
- `git show HEAD^:scripts/ralph-pipeline.sh` to confirm what the old verify/test phases looked like
- `git show f5c81df:scripts/ralph-loop-init.sh` to confirm --pipeline flag removal timeline
- `.claude/skills/loop/prompts/pipeline-self-review.md` (new)
- `.claude/skills/loop/prompts/pipeline-verify.md` (new)
- `.claude/skills/loop/prompts/pipeline-test.md` (new)
- `.claude/skills/loop/prompts/pipeline-outer.md` (modified)
- `scripts/ralph-pipeline.sh` (modified)
- `.claude/skills/loop/SKILL.md` (modified)
- `docs/quality/quality-gates.md` (modified)
- `docs/quality/definition-of-done.md` (modified)
- `docs/recipes/ralph-loop.md` (modified)
- `.claude/rules/post-implementation-pipeline.md` (modified)
- `.claude/agent-memory/doc-maintainer/MEMORY.md` (not modified — stale reference found)
- `docs/tech-debt/README.md`

## Findings

| Severity | Area | Finding | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| MEDIUM | maintainability | `doc-maintainer/MEMORY.md` line 31 still references the deleted `pipeline-review.md` as "self-review + verify + test agent". The file was split into `pipeline-self-review.md`, `pipeline-verify.md`, and `pipeline-test.md` by this diff, but the agent memory was not updated. Any doc-maintainer session started after this merge will have incorrect context about what prompt files exist. | `.claude/agent-memory/doc-maintainer/MEMORY.md:31` — `pipeline-review.md — self-review + verify + test agent`; new files at `.claude/skills/loop/prompts/pipeline-{self-review,verify,test}.md` | Update lines 31–32 of `doc-maintainer/MEMORY.md` to list the three new prompt files. Also update line 17: "supports `--pipeline` flag" is stale (see LOW finding below). |
| LOW | maintainability | `docs/quality/quality-gates.md` line 68 says `MAX_INNER_CYCLES (default 5)` but `scripts/ralph-pipeline.sh:15` sets `MAX_INNER_CYCLES=10`. This mismatch is pre-existing, but this diff modified the Inner Loop gates table in `quality-gates.md` (lines 51–60) without correcting the adjacent Outer Loop table entry. An opportunity to fix was missed. | `quality-gates.md:68` — `MAX_INNER_CYCLES (default 5)`; `ralph-pipeline.sh:15` — `MAX_INNER_CYCLES=10` | Change `quality-gates.md:68` to `(default 10)`. |
| LOW | maintainability | `doc-maintainer/MEMORY.md:17` says `ralph-loop-init.sh` "supports `--pipeline` flag", but that flag was removed in the `wip: checkpoint before context compaction` commit (b8bd602). `ralph-orchestrator.sh:341` still calls `ralph-loop-init.sh --pipeline general ...`, which now exits 1 (invalid task type) silently suppressed by `|| true`. The pipeline falls back to `.claude/skills/loop/prompts/pipeline-inner.md` in the worktree (path 2 of 3 fallbacks), so functionality is not broken — but the memory entry is misleading. | `ralph-loop-init.sh:27` — no `--pipeline` handling; `ralph-orchestrator.sh:341` — calls with `--pipeline`; `doc-maintainer/MEMORY.md:17` — claims flag is supported | Remove the "supports `--pipeline` flag" note from `doc-maintainer/MEMORY.md:17`. Document the silent failure + fallback path in `docs/tech-debt/README.md`. Note: this bug is pre-existing and not introduced by this diff. |
| LOW | maintainability | Inline fallback prompts for verify and test phases in `ralph-pipeline.sh` (lines 529–534, 563–568) instruct the agent to run `./scripts/run-static-verify.sh` / `./scripts/run-test.sh` but do not mention the `HARNESS_VERIFY_MODE=` fallback for when those wrapper scripts are absent. The full prompt files (`pipeline-verify.md`, `pipeline-test.md`) correctly include both options. The inline fallback is only reached when prompt files are entirely missing (rare), but it is slightly degraded compared to the dedicated prompts. This pattern was noted in `self-review-2026-04-09-pipeline-robustness-r2.md` for the old self-review fallback and persists in the new verify/test fallbacks. | `ralph-pipeline.sh:531` — `Run: ./scripts/run-static-verify.sh` (no HARNESS_VERIFY_MODE fallback); `pipeline-verify.md:29–31` — includes both `run-static-verify.sh` and `HARNESS_VERIFY_MODE=static ./scripts/run-verify.sh` | Add `(or: HARNESS_VERIFY_MODE=static ./scripts/run-verify.sh if run-static-verify.sh is absent)` to the inline verify fallback; similarly for the test fallback. Low priority given the 2-tier file lookup makes the inline fallback rare. |

## Positive notes

- **Clean separation of responsibilities**: Splitting the monolithic `pipeline-review.md` into three single-responsibility prompts (`pipeline-self-review.md`, `pipeline-verify.md`, `pipeline-test.md`) directly mirrors the standard-flow subagent pattern. Each prompt clearly states what it does NOT do, which is strong design.
- **3-layer detection for all three phases**: Self-review CRITICAL count, verify verdict, and test verdict all use the sidecar → JSON output → grep fallback chain. This robustness pattern is consistent and well-applied.
- **Sidecar clearing at cycle start** (`rm -f .self-review-result .verify-result .test-result` at `ralph-pipeline.sh:355`): The new line correctly clears stale sidecar files from previous cycles. This prevents a passing prior cycle's sidecar from masking a missing write in the current cycle — a real correctness issue that the old code did not have (because it didn't use sidecars).
- **Dry-run coverage**: All three new agent phases go through `run_claude()`, which handles `DRY_RUN` centrally. The old code had separate `if [ "$DRY_RUN" -eq 1 ]` branches for each phase; the new code is simpler.
- **pipeline-outer.md harness-internal checklist**: The 7-category checklist is specific and actionable. Items 1–7 cover exactly the failure modes seen in previous sync-docs gaps (skills renamed, scripts added, quality gates changed). This is a genuine improvement over the old vague "Update any documentation affected."
- **Documentation is thorough and consistent**: `quality-gates.md`, `definition-of-done.md`, `recipes/ralph-loop.md`, `post-implementation-pipeline.md`, and `SKILL.md` all received consistent updates that accurately describe the new agent-driven behavior. The parity note in `post-implementation-pipeline.md` ("not shell-direct execution") is precise and useful.
- **No secrets, no debug code, no injection risks** found in any of the changed files.

## Tech debt identified

| Debt item | Impact | Why deferred | Trigger to pay down | Related plan/report |
| --- | --- | --- | --- | --- |
| `doc-maintainer/MEMORY.md:31` references deleted `pipeline-review.md`. Agent memory entry is stale after pipeline-quality-parity merge. | LOW: misleading context for doc-maintainer sessions | This diff's scope was prompt files and ralph-pipeline.sh; agent memory was not in scope | Next harness feature that touches pipeline prompts, or any sync-docs cycle | self-review-2026-04-10-pipeline-quality-parity.md |
| `ralph-orchestrator.sh:341` calls `ralph-loop-init.sh --pipeline` which no longer exists. Fails silently (`|| true`), pipeline recovers via fallback path. | LOW: extra noise in slice logs, misleading `doc-maintainer/MEMORY.md:17` | Pre-existing regression from wip commit b8bd602; functional impact is nil due to fallback | Next refactor of `ralph-loop-init.sh` or `ralph-orchestrator.sh` | self-review-2026-04-10-pipeline-quality-parity.md |

_(Rows added above are also appended to `docs/tech-debt/README.md`.)_

## Recommendation

- Merge: **conditional** — the core changes (3-agent split, ralph-pipeline.sh Inner Loop conversion, doc updates) are correct and well-executed. Two LOW issues and one MEDIUM issue should be addressed before or immediately after merge.
- Follow-ups:
  1. **MEDIUM** — Update `doc-maintainer/MEMORY.md:31–32` to list the three new prompt files (`pipeline-self-review.md`, `pipeline-verify.md`, `pipeline-test.md`) instead of `pipeline-review.md`.
  2. **LOW** — Fix `quality-gates.md:68`: `MAX_INNER_CYCLES (default 5)` → `(default 10)`.
  3. **LOW** — Remove the stale `--pipeline` flag note from `doc-maintainer/MEMORY.md:17` and add a tech-debt entry for the `ralph-orchestrator.sh:341` silent failure.
  4. **LOW** (deferred) — Add `HARNESS_VERIFY_MODE=` fallback instructions to the inline verify and test fallback prompts in `ralph-pipeline.sh`.
