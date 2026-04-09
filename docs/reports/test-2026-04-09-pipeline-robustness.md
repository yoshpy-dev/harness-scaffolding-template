# Test report: Pipeline robustness improvements

- Date: 2026-04-09
- Plan: docs/plans/active/2026-04-09-pipeline-robustness.md
- Branch: feat/ralph-loop-v2
- Tester: tester subagent (Claude Sonnet 4.6)
- Scope: Unit tests, regression tests, and static-analysis edge case checks for `ralph-pipeline.sh` robustness improvements (AC1-AC11)
- Evidence: `docs/evidence/test-2026-04-09-pipeline-robustness.log`

## Test execution

| Suite / Command | Tests | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- |
| Unit: `--preflight --dry-run` | 1 | 1 | 0 | 0 | ~1s |
| Unit: `--help` (AC7) | 1 | 1 | 0 | 0 | <1s |
| Unit: `--dry-run --max-iterations 3` | 1 | 1 | 0 | 0 | ~2s |
| Regression: `ralph --help` | 1 | 1 | 0 | 0 | <1s |
| Regression: `ralph status` | 1 | 1 | 0 | 0 | <1s |
| Regression: `sh -n ralph-pipeline.sh` | 1 | 1 | 0 | 0 | <1s |
| Regression: `sh -n ralph` | 1 | 1 | 0 | 0 | <1s |
| Regression: `sh -n ralph-orchestrator.sh` | 1 | 1 | 0 | 0 | <1s |
| Edge case: `run_claude()` raw fallback (static) | 1 | 1 | 0 | 0 | — |
| Edge case: `.agent-signal` Layer 2 fallback (static) | 1 | 1 | 0 | 0 | — |
| Edge case: `gh pr list` empty → sidecar → log (static) | 1 | 1 | 0 | 0 | — |
| Edge case: sidecar cleanup at cycle start (static) | 1 | 1 | 0 | 0 | — |
| **Total** | **12** | **12** | **0** | **0** | **~5s** |

## Coverage

- Statement: Shell scripts — all new code paths in `run_claude()`, signal detection, PR URL detection, and sidecar lifecycle are exercised by dry-run or verified via static analysis.
- Branch: All multi-layer fallback branches (jq fail, file-absent, empty gh output) confirmed present in code.
- Function: All new/modified functions covered: `run_claude()`, `run_inner_loop()` (sidecar clear, COMPLETE/ABORT detection), `run_outer_loop()` (PR URL 3-layer), `run_preflight()` (Probe 5: JSON output format).
- Notes: Live `claude -p` execution paths (JSON mode, text fallback) cannot be unit-tested without API access. Dry-run covers the control flow; the JSON/raw distinction is verified statically.

## Failure analysis

| Test | Error | Root cause | Proposed fix |
| --- | --- | --- | --- |
| (none) | — | — | — |

## Regression checks

| Previously broken behavior | Status | Evidence |
| --- | --- | --- |
| `ralph-pipeline.sh --help` exited 1 (pre-fix) | FIXED | Test 2 exits 0 — `usage()` now calls `exit 0` |
| `ralph --help` exited 1 (r2 fix applied) | STILL FIXED | Test 4 exits 0 |
| `ralph status` failed without checkpoint | STILL FIXED | Test 5 reads `.harness/state/pipeline/checkpoint.json` correctly |
| Hook parity "uncommitted changes" warning in dry-run | EXPECTED (known behavior) | Warning appears in Test 3 output; not a regression |

## Notes on individual acceptance criteria

| AC | Status | Evidence |
| --- | --- | --- |
| AC1: `run_claude()` uses `--output-format json`; raw fallback on jq fail | PASS | Lines 118-137: JSON path + fallback `cp` at line 127 |
| AC2: Session ID from JSON `.session_id` (no grep) | PASS | Line 418: `jq -r '.session_id // empty'` |
| AC3: COMPLETE and ABORT 2-layer detection (sidecar + marker) | PASS | Lines 431-458: Layer 1 via `_agent_signal`, Layer 2 via `grep '<promise>*</promise>'` |
| AC4: Sidecar files cleared at Inner Loop cycle start | PASS | Line 354: `rm -f .agent-signal .pr-url` |
| AC5: PR URL 3-layer: `gh pr list` → sidecar → log grep | PASS | Lines 670-696: confirmed 3-layer ordering |
| AC6: Preflight Probe 5 for JSON output format support | PASS | Lines 294-313: dry-run sets `JSON_OUTPUT_SUPPORTED=1`; live path validates via jq |
| AC7: `ralph-pipeline.sh --help` exits 0 | PASS | Test 2: exit 0 confirmed |
| AC8: `pipeline-review.md` report path unified | NOT TESTED here (doc change, verified in /verify) | — |
| AC9: `definition-of-done.md` clarifies report paths | NOT TESTED here (doc change, verified in /verify) | — |
| AC10: Existing dry-run tests still PASS | PASS | Tests 1 and 3 both pass |
| AC11: `sh -n` syntax checks pass for all scripts | PASS | Tests 6, 7, 8 all exit 0 |

## Test gaps

- **Live JSON parsing path**: The `JSON_OUTPUT_SUPPORTED=1` code path in `run_claude()` requires a real `claude -p --output-format json` call. Cannot be exercised without API access in this environment. The code structure (stdout/stderr separation, jq extract, fallback) is verified statically.
- **jq-failure raw fallback at runtime**: Triggering the `else` branch of the jq parse in `run_claude()` requires injecting malformed JSON into the `.json` file during a live run. Verified by code inspection only.
- **Multi-layer PR URL at runtime**: `gh pr list` returning an empty array falls through to Layer 2/3 — exercised statically. Would require a branch with no open PR to test dynamically.
- **Stuck detection 3-cycle threshold**: Requires 3 consecutive dry-run cycles with no new commits. Known gap from previous sessions; not in scope for this test plan.
- **Failure triage retry cycle**: Requires `run-test.sh` to fail, which cannot occur in dry-run mode.

## Verdict

- Pass: 12
- Fail: 0
- Blocked: 0

**Overall verdict: PASS**

All 12 tests passed. AC1-AC7, AC10, AC11 verified via runtime or static analysis. AC8-AC9 are documentation changes verified in `/verify`. No test failures. Safe to proceed to `/pr`.
