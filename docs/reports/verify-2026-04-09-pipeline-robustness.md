# Verify report: Pipeline robustness improvements

- Date: 2026-04-09
- Plan: `docs/plans/active/2026-04-09-pipeline-robustness.md`
- Verifier: verifier subagent (Claude Sonnet 4.6)
- Scope: AC1-AC11 spec compliance, static analysis (sh -n), documentation drift
- Evidence: `docs/evidence/verify-2026-04-09-pipeline-robustness.log`

---

## Spec compliance

| Acceptance criterion | Status | Evidence |
|---|---|---|
| AC1: `run_claude()` uses `--output-format json`, saves JSON to `${_log_file}.json`, extracts `.result` via jq, raw fallback on parse failure | PASS | Lines 118-138 of `ralph-pipeline.sh`. JSON mode uses `claude -p --output-format json > ${_log_file}.json 2>${_log_file}.stderr`; `jq -e '.result'` guards extraction; `cp "${_log_file}.json" "$_log_file"` is the raw fallback; warning is logged. |
| AC2: Session ID extracted via `jq -r '.session_id // empty'` from `.json` file, no grep fallback | PASS (with note) | Lines 416-423. Code uses `jq -r '.session_id // empty'` only. On empty result, logs warning and moves on — no grep fallback exists. Note: the comment on line 415 says "or log grep (fallback)" but the implementation has no such fallback. Comment is misleading but the behavior itself matches AC2. |
| AC3: COMPLETE and ABORT detected via 2 layers — sidecar file `.agent-signal` (Layer 1) and `<promise>COMPLETE/ABORT</promise>` marker grep (Layer 2) | PASS | Lines 428-458. Both ABORT and COMPLETE follow: (1) read `.agent-signal` via `cat`, grep for signal string; (2) `elif grep -q '<promise>ABORT/COMPLETE</promise>' "$_impl_log"`. Both signals handled symmetrically. |
| AC4: Sidecar files (`.agent-signal`, `.pr-url`) cleared at each Inner Loop cycle start | PASS | Line 354: `rm -f "${PIPELINE_DIR}/.agent-signal" "${PIPELINE_DIR}/.pr-url"` runs at the top of `run_inner_loop()`, before any prompt execution. |
| AC5: PR URL detection: gh pr list (Layer 1) → sidecar `.pr-url` (Layer 2) → log grep (Layer 3) | PASS | Lines 670-696. Layer 1: `gh pr list --head "$_head_branch" --state open --json url --jq '.[0].url'`. Layer 2: `cat "${PIPELINE_DIR}/.pr-url"` with URL regex. Layer 3: `grep -oE 'https://github\.com/...' "$_pr_log"`. Correct priority ordering. |
| AC6: Preflight probe verifies `--output-format json` support; falls back to text mode on failure | PASS | Lines 293-313 (Probe 5). Sends a json probe; uses `jq -e '.result'` to validate; sets `JSON_OUTPUT_SUPPORTED=1` on success or `not_supported` + warning on failure. In dry-run, defaults to JSON_OUTPUT_SUPPORTED=1. |
| AC7: `ralph-pipeline.sh --help` exits 0 | PASS | Verified by running `./scripts/ralph-pipeline.sh --help` and `./scripts/ralph-pipeline.sh -h`. Both output usage text and exit 0. Line 39: `exit 0` in `usage()`. |
| AC8: `pipeline-review.md` report output paths use `.harness/state/pipeline/` | PASS | `pipeline-review.md` lines 25, 32, 38: findings to `.harness/state/pipeline/self-review.md`, results to `.harness/state/pipeline/verify.md` and `.harness/state/pipeline/test.md`. |
| AC9: `definition-of-done.md` clarifies pipeline mode report locations | PASS | Lines 37-39 of `definition-of-done.md`: "Report locations (pipeline mode): Inner Loop working reports: `.harness/state/pipeline/` ... Final artifacts for PR and archival: `docs/reports/`". |
| AC10: Dry-run tests pass (`--preflight --dry-run`, `--help`, `--dry-run --max-iterations 3`) | PASS | All three variants executed. `--preflight --dry-run` exits 0. `--help` exits 0. `--dry-run --max-iterations 3` runs through full Inner+Outer Loop in dry-run mode and exits 0 with `Status: complete`. |
| AC11: `sh -n` passes on all scripts | PASS | All 16 files in `scripts/` (including `ralph`, `ralph-pipeline.sh`, `ralph-orchestrator.sh`, and all helpers) pass `sh -n` with no syntax errors. |

---

## Static analysis

| Command | Result | Notes |
|---|---|---|
| `sh -n scripts/ralph-pipeline.sh` | PASS | No syntax errors |
| `sh -n scripts/ralph` | PASS | No syntax errors |
| `sh -n scripts/ralph-orchestrator.sh` | PASS | No syntax errors |
| `sh -n scripts/ralph-loop.sh` | PASS | No syntax errors |
| `sh -n scripts/ralph-loop-init.sh` | PASS | No syntax errors |
| `sh -n scripts/run-static-verify.sh` | PASS | No syntax errors |
| `sh -n scripts/run-verify.sh` | PASS | No syntax errors |
| `sh -n scripts/run-test.sh` | PASS | No syntax errors |
| `sh -n scripts/commit-msg-guard.sh` | PASS | No syntax errors |
| `sh -n scripts/bootstrap.sh` | PASS | No syntax errors |
| `sh -n scripts/check-template.sh` | PASS | No syntax errors |
| `sh -n scripts/archive-plan.sh` | PASS | No syntax errors |
| `sh -n scripts/codex-check.sh` | PASS | No syntax errors |
| `sh -n scripts/detect-languages.sh` | PASS | No syntax errors |
| `sh -n scripts/new-feature-plan.sh` | PASS | No syntax errors |
| `sh -n scripts/new-language-pack.sh` | PASS | No syntax errors |
| `shellcheck` | NOT RUN | shellcheck not installed in this environment — recurring gap |

---

## Documentation drift

| Doc / contract | In sync? | Notes |
|---|---|---|
| `pipeline-inner.md` — sidecar signal instructions | IN SYNC | Lines 57-72: both COMPLETE and ABORT use `echo COMPLETE/ABORT > .harness/state/pipeline/.agent-signal` plus `<promise>...</promise>` marker. Matches 2-layer detection in code. |
| `pipeline-outer.md` — PR URL sidecar instruction | IN SYNC | Lines 53-55: instructs agent to `echo "https://..." > .harness/state/pipeline/.pr-url` after PR creation. Matches Layer 2 detection in code. |
| `pipeline-review.md` — report output paths | IN SYNC | All three output paths (`self-review.md`, `verify.md`, `test.md`) correctly point to `.harness/state/pipeline/`. |
| `definition-of-done.md` — pipeline report location | IN SYNC | Section "Report locations (pipeline mode)" added, correctly distinguishes Inner Loop working logs from final `docs/reports/` artifacts. |
| `ralph-pipeline.sh` — `run_claude()` comment on line 415 | MINOR DRIFT | Comment reads "primary) or log grep (fallback)" but no grep fallback for session_id exists in the code. Comment is misleading but does not affect behavior. Recommend correcting comment to "primary only; warning logged if absent". |

---

## Observational checks

- `--dry-run --max-iterations 3` run completed with `Status: complete` in one Inner+Outer cycle, confirming full pipeline flow executes correctly in dry-run mode.
- `preflight-probe.json` written to `docs/evidence/` as expected after `--preflight --dry-run`.
- In dry-run mode, `JSON_OUTPUT_SUPPORTED` is set to 1 automatically (line 297), so the dry-run path correctly exercises the JSON extraction branch in `run_claude()`.
- PR URL Layer 1 (`gh pr list`) correctly picks up the existing open PR (#5) during dry-run, confirming that layer is functional.
- Hook parity check emits a `WARNING` in dry-run (uncommitted changes in working tree) but does not block the pipeline — correct behavior.

---

## Coverage gaps

1. **shellcheck not installed** (INFO): `sh -n` catches syntax errors but not semantic/portability issues (e.g., unquoted variables, `local` in POSIX sh). This is a recurring environment constraint.
2. **AC6 runtime**: The JSON output probe (Probe 5) was verified as `skip_dry_run` in the dry-run run. The actual `claude -p --output-format json` probe cannot be evaluated without a live `claude` session. Behavior is verified by code inspection only.
3. **AC3 agent-side**: Whether the agent will actually write to `.agent-signal` depends on prompt compliance. The orchestrator-side detection logic is correct; agent-side behavior is unverified without a real execution.
4. **AC2 comment drift**: Line 415 comment "or log grep (fallback)" is inaccurate. Low severity but should be corrected to avoid future confusion.
5. **Stale `.pr-url` cleared by AC4**: The clear at cycle start removes `.pr-url` too. However `.pr-url` is written in the Outer Loop, not the Inner Loop — so clearing it at Inner Loop cycle start could prematurely remove a valid URL if the Outer Loop re-enters the Inner Loop due to ACTION_REQUIRED. This is an edge case; in practice `.pr-url` only matters after Outer Loop PR creation succeeds, at which point the pipeline is done.

---

## Verdict

- **Verified**: AC1, AC2 (code behavior), AC3, AC4, AC5, AC6 (code path), AC7, AC8, AC9, AC10, AC11
- **Partially verified**: AC2 comment (misleading but harmless); AC6 runtime probe (dry-run only); AC3 agent-side compliance (prompt only, not executed)
- **Not verified**: None (all ACs have code-level evidence or dry-run confirmation)

**Overall verdict: PASS**

All 11 acceptance criteria are met. One minor documentation drift (misleading comment on line 415) is noted but does not affect behavior. No blocking issues found.
