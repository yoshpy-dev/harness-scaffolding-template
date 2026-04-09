# Self-review report: Ralph Loop v2 — re-review after Codex fix pass (r2)

- Date: 2026-04-09
- Plan: docs/plans/active/2026-04-09-ralph-loop-v2.md
- Reviewer: reviewer subagent (claude-sonnet-4-6)
- Scope: Diff quality only. Focused on the 4 Codex-flagged fixes and regressions they may introduce. Pre-existing MEDIUM findings from the r1 review that were not in scope of the 4 fixes are noted as unchanged, not re-evaluated.

## Evidence reviewed

- `git diff main...feat/ralph-loop-v2` — 3461 insertions across 28 files (current HEAD)
- Previous self-review: `docs/reports/self-review-2026-04-09-ralph-loop-v2.md`
- Codex triage: `docs/reports/codex-triage-2026-04-09-ralph-loop-v2.md`
- `scripts/ralph` lines 119–134 (Fix 1: --resume flag logic)
- `scripts/ralph-pipeline.sh` lines 183–208 (Fix 2: stuck detection via HEAD hashes)
- `scripts/ralph-orchestrator.sh` lines 515–531 (Fix 3: locklist rebuild)
- `scripts/ralph-pipeline.sh` lines 374–394, 485–489 (Fix 4: COMPLETE signal gate)

---

## Fix verdict — the 4 Codex findings

### Fix 1: `--resume` flag logic (`scripts/ralph:119–134`)

**Status: PARTIAL — new HIGH defect introduced**

The guard logic at lines 120–131 is now correct:

```sh
_is_resume=0
echo "$_extra_args" | grep -q -- '--resume' && _is_resume=1 || true
if [ ! -f "${PIPELINE_DIR}/checkpoint.json" ] && [ "$_is_resume" -eq 0 ]; then
  # run init
fi
if [ "$_is_resume" -eq 1 ] && [ ! -f "${PIPELINE_DIR}/checkpoint.json" ]; then
  log_error "Cannot resume: no checkpoint found at ${PIPELINE_DIR}/checkpoint.json"
  exit 1
fi
```

Conditions are correct: init runs only when checkpoint is absent AND not resuming; a resume-without-checkpoint produces an error and exits.

**However**, `log_error` at line 129 is not defined anywhere in `scripts/ralph`. Only `log()` is defined at line 22. Under `set -eu`, calling an undefined function causes an immediate `command not found` error with no meaningful message — exactly the opposite of the intended diagnostic. The fix introduced this defect.

Secondary note: the `--resume` detection via `echo "$_extra_args" | grep -q -- '--resume'` is a substring match. A hypothetical future flag like `--resume-session` would produce a false positive. Currently no such flag exists, so this is LOW severity.

### Fix 2: Stuck detection uses HEAD commit hashes (`scripts/ralph-pipeline.sh:183–208`)

**Status: CORRECT**

```sh
check_stuck() {
  _head_after="$(git rev-parse HEAD 2>/dev/null || true)"
  _head_before="$(cat "${PIPELINE_DIR}/.head_before" 2>/dev/null || true)"
  if [ "$_head_before" = "$_head_after" ]; then
    _stuck_count=$((_stuck_count + 1))
  else
    _stuck_count=0
  fi
  ...
}

save_diff_before() {
  git rev-parse HEAD 2>/dev/null > "${PIPELINE_DIR}/.head_before" || true
}
```

`save_diff_before` is called at line 311 (before implementation) and `check_stuck` at line 391 (after implementation). Ordering is correct.

Edge cases verified:
- First iteration with no `.head_before` file: `_head_before=""` vs real SHA → not stuck (correct).
- Git unavailable: entire block is skipped, returns 1 (not stuck) — acceptable safe default.
- Git fails mid-run: `_head_after=""` vs old SHA → not stuck — false negative in degenerate case, acceptable.

No regression introduced.

### Fix 3: Locklist `.running_files` rebuilt from running slices (`scripts/ralph-orchestrator.sh:515–531`)

**Status: CORRECT**

```sh
# After trying to start slices (lines 466–513):
_completed=0
_failed=0
_running=0
: > "${ORCH_STATE}/.running_files"
while IFS='|' read -r _rf_s _rf_o _rf_d _rf_f; do
  _rf_status="$(check_slice_status "$_rf_s")"
  case "$_rf_status" in
    complete)                          _completed=$((_completed + 1)) ;;
    failed|stuck|repair_limit|aborted) _failed=$((_failed + 1)) ;;
    running)
      _running=$((_running + 1))
      echo "$_rf_f" | tr ',' '\n' >> "${ORCH_STATE}/.running_files"
      ;;
  esac
done < "$_slices_file"
```

The rebuild uses a file redirect (`< "$_slices_file"`), not a pipe, so variable updates to `_completed`, `_failed`, `_running` propagate correctly in POSIX sh. This is the correct fix pattern.

Counter-reset before rebuild is required to prevent double-counting — correctly done at lines 516–518.

Slices started in the current pass of the outer while loop have their status file written to "running" by `run_slice` (line 265) before the rebuild executes, so they are correctly included in the rebuilt `.running_files`.

No regression introduced.

### Fix 4: COMPLETE signal no longer bypasses verify/test (`scripts/ralph-pipeline.sh:374–382, 485–489`)

**Status: CORRECT**

```sh
_agent_complete=0
if grep -q '<promise>COMPLETE</promise>' "$_impl_log" 2>/dev/null; then
  log "Agent signalled COMPLETE — will still run verify/test before proceeding"
  _agent_complete=1
fi
# ... verify/test phases execute unconditionally ...
# Tests passed:
if [ "$_agent_complete" -eq 1 ]; then
  log "Agent COMPLETE confirmed — verify/test passed"
  ckpt_update '.status = "complete"'
fi
```

`COMPLETE` now only triggers `status = "complete"` in checkpoint after tests pass. The pipeline still proceeds through `run_outer_loop` (sync-docs, codex, PR) regardless.

`status = "complete"` in `checkpoint.json` has no effect on the main loop's control flow — the loop only exits when `run_outer_loop` returns 0. This is correct: it's metadata, not a control signal.

If `COMPLETE` fires but tests fail, the pipeline correctly retries the Inner Loop (the test-failure path at lines 463–478 does not inspect `_agent_complete`).

No regression introduced.

---

## Findings

| Severity | Area | Finding | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| HIGH | exception-handling | `log_error` is called at `scripts/ralph:129` but is never defined in that file. Only `log()` is defined (line 22). Under `set -eu`, this causes `command not found` at runtime — the error exit intended to diagnose a missing checkpoint produces an opaque shell error instead. | `scripts/ralph:22,129`; `grep -n "log_error" scripts/ralph` returns only the one usage | Add `log_error() { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; }` alongside `log()` at line 22–23 |
| LOW | null-safety | The `--resume` detection at `scripts/ralph:122` uses a substring grep on the concatenated `_extra_args` string. A future flag whose name contains `--resume` as a prefix (e.g., `--resume-session`) would falsely set `_is_resume=1`. Currently no such flag exists, so impact is low. | `scripts/ralph:122`: `echo "$_extra_args" \| grep -q -- '--resume'` | Use a word-boundary match: `case "$_extra_args" in *" --resume "*\|*"--resume ">* \| "--resume") ...` or parse the original positional arguments before building `_extra_args` |

---

## Pre-existing MEDIUM findings (unchanged, not re-evaluated)

The following findings from `self-review-2026-04-09-ralph-loop-v2.md` were not in scope for the 4 Codex fixes and remain unaddressed:

| Finding | Location | Status |
| --- | --- | --- |
| `ckpt_update ".phase = \"inner\""` runs before `ckpt_read 'phase'` for transition record — "from" field always shows "inner → inner" | `ralph-pipeline.sh:306–307` | Unchanged |
| `_total_iteration` is incremented twice per test-failure cycle | `ralph-pipeline.sh:679,693` | Unchanged |
| `run_hook_parity` naming inconsistency | `ralph-pipeline.sh:132` | Unchanged |
| Session ID grep pattern is fragile; no warning on empty result after cycle 1 | `ralph-pipeline.sh:369` | Unchanged |
| `ckpt_transition` builds JSON via string concatenation, not `jq --arg` | `ralph-pipeline.sh:85–95` | Unchanged |
| CRITICAL self-review findings are non-blocking (deliberate deviation from `AGENTS.md` contract) | `ralph-pipeline.sh:424–428` | Unchanged (documented in tech-debt) |

---

## Positive notes

- Fix 2 (stuck detection) correctly uses temp-file state to persist HEAD across the implement phase boundary, with no shell-scope issues.
- Fix 3 (locklist rebuild) replaces the previous accumulation-only approach with a clean snapshot-and-rebuild pattern each poll cycle. The `_rf_`-prefixed variable names in the rebuild loop avoid shadowing the outer loop variables (`s`, `o`, `d`, `f`), which is good defensive naming.
- Fix 4 preserves all existing behaviors (ABORT still short-circuits; hook parity still runs after completion marker is set) — no functional regression from introducing the `_agent_complete` flag.
- The `_deps_tmp` temp file in the dependency check loop is correctly cleaned up with `rm -f` after use (line 488).

---

## Tech debt identified

No new deferred items from this review. Existing tech-debt entries in `docs/tech-debt/README.md` remain accurate.

---

## Recommendation

- **Merge: NO** — One new HIGH finding introduced by the fix pass must be resolved first:
  - `scripts/ralph:129` calls `log_error` which is not defined. This breaks the `--resume` error path at runtime with `set -eu`. Fix: add `log_error()` definition alongside `log()` at line 22.

- **Fix 2, 3, 4 are merge-ready**: Stuck detection, locklist rebuild, and COMPLETE signal gate are all correct and introduce no regressions.

- **Follow-up (post-merge, non-blocking):**
  - Replace the `--resume` substring-grep detection with a word-boundary pattern or pre-parse the flag before building `_extra_args` (LOW severity).
  - Address the pre-existing MEDIUM findings before the first real autonomous pipeline run, particularly the `ckpt_transition` from-field bug and the double-increment of `_total_iteration`.
