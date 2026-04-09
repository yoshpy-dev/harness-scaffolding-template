# Test report: Ralph Loop v2 — Codex fix re-run

- Date: 2026-04-10
- Plan: docs/plans/archive/2026-04-09-ralph-loop-v2.md
- Tester: tester subagent (claude-sonnet-4-6)
- Scope: Re-run after two Codex finding fixes (commit 5f852b4). Covers dependency slug normalization (Fix 1), base branch fallback (Fix 2), and all prior tests from `test-2026-04-10-ralph-loop-v2.md`.
- Evidence: `docs/evidence/test-2026-04-10-ralph-loop-v2-codex-fixes.log`

## Test execution

| Suite / Command | Tests | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- |
| `./scripts/run-test.sh` (canonical) | 0 | 0 | 0 | 0 (scaffold-only) | < 1s |
| Fix 1: Dep slug normalization — `slice-1-foo` → `1-foo` | 1 | 1 | 0 | 0 | < 1s |
| Fix 1: Dep slug normalization — `slice 1` → `1` | 1 | 1 | 0 | 0 | < 1s |
| Fix 1: Dep slug normalization — `[slice 1]` → `1` | 1 | 1 | 0 | 0 | < 1s |
| Fix 1: Dep slug normalization — `Slice 2` → `2` | 1 | 1 | 0 | 0 | < 1s |
| Fix 1: Dep slug normalization — `slice-2-auth-api` → `2-auth-api` | 1 | 1 | 0 | 0 | < 1s |
| Fix 1: Dep slug normalization — `slice` → `""` (guard triggers) | 1 | 1 | 0 | 0 | < 1s |
| Fix 2: Base branch fallback — no upstream → `main` | 1 | 1 | 0 | 0 | < 1s |
| Fix 2: Base branch fallback — upstream set → keeps upstream | 1 | 1 | 0 | 0 | < 1s |
| Regression: `new-ralph-plan.sh` directory structure | 1 | 1 | 0 | 0 | < 1s |
| Regression: `ralph-orchestrator.sh --dry-run --plan <dir>` | 1 | 1 | 0 | 0 | < 1s |
| Regression: `archive-plan.sh <directory>` | 1 | 1 | 0 | 0 | < 1s |
| Regression: `ralph-loop-init.sh --pipeline <fullpath>` | 1 | 1 | 0 | 0 | < 1s |
| Regression: `ralph-pipeline.sh --dry-run --max-iterations 3` | 1 | 1 | 0 | 0 | ~2s |
| Regression: `ralph --help` exits 0 | 1 | 1 | 0 | 0 | < 1s |
| Regression: `ralph-pipeline.sh --help` exits 0 | 1 | 1 | 0 | 0 | < 1s |
| Edge: `ralph-loop-init.sh` empty plan slug | 1 | 1 | 0 | 0 | < 1s |
| Edge: `ralph-orchestrator.sh` with 0 slice-*.md files | 1 | 1 | 0 | 0 | < 1s |
| Edge: `ralph-orchestrator.sh --plan <single-file>` rejected | 1 | 1 | 0 | 0 | < 1s |
| `run-test.sh` canonical returns exit 0 | 1 | 1 | 0 | 0 | < 1s |
| **TOTAL** | **20** | **20** | **0** | **0** | **~5s** |

## Coverage

- Statement: N/A (shell scripts, no coverage tool)
- Branch: Fix 1 — all 6 normalization scenarios exercised. Fix 2 — both "no upstream" and "upstream set" paths tested.
- Function: All entry points tested: `new-ralph-plan.sh`, `ralph-orchestrator.sh`, `archive-plan.sh`, `ralph-loop-init.sh`, `ralph-pipeline.sh`, `ralph CLI`.
- Notes: Live `claude -p` paths remain untestable without API access.

## Fix 1 verification: Dependency slug normalization (ralph-orchestrator.sh:638)

**Change:** `sed 's/^slice //'` → `sed 's/^slice[- ]*//'`

**Root cause confirmed:** The `tr -d ' []'` applied before `sed` strips all spaces, so `"slice "` (with trailing space) could never match the old pattern. The fix adds `[- ]*` to match hyphens and handles all common user-facing formats.

**Test results:**

| Input dep field | After `tr -d ' []'` + `tr lower` | Old sed | New sed | Matches slug? |
|---|---|---|---|---|
| `"slice-1-foo"` | `"slice-1-foo"` | `"slice-1-foo"` (no match) | `"1-foo"` | YES — `slice-1-foo.md` → slug `"1-foo"` |
| `"slice 1"` | `"slice1"` | `"slice1"` (no match) | `"1"` | YES — `slice-1.md` → slug `"1"` |
| `"[slice 1]"` | `"slice1"` | `"slice1"` (no match) | `"1"` | YES |
| `"Slice 2"` | `"slice2"` | `"slice2"` (no match) | `"2"` | YES |
| `"slice-2-auth-api"` | `"slice-2-auth-api"` | `"slice-2-auth-api"` (no match) | `"2-auth-api"` | YES — `slice-2-auth-api.md` → slug `"2-auth-api"` |
| `"slice"` | `"slice"` | `"slice"` (no match) | `""` | YES — empty string triggers `continue` guard on line 639 |

All 6 normalization scenarios pass. Fix is correct.

**Additional observation (non-blocking, pre-existing):** If a user writes `"slice-1"` as a dependency shorthand for a slice file `slice-1-<longname>.md`, the normalized value `"1"` will not match slug `"1-<longname>"`. This is a design convention gap (not a regression introduced by the fix). The fix document in the verify report correctly demonstrates this works for `"slice-1-foo"` → `"1-foo"` (full slug match). Users should write the full slice name (e.g., `"slice-1-auth-api"`) in dependency fields, not abbreviated `"slice-N"` shorthand when slices have descriptive names.

## Fix 2 verification: Base branch fallback (ralph-pipeline.sh:621-622)

**Change:**
```sh
# Old (broken):
_base="$(git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null | sed 's|origin/||' || echo main)"

# New (correct):
_base="$(git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null | sed 's|origin/||')"
_base="${_base:-main}"
```

**Root cause confirmed:** `sed` exits 0 even on empty stdin. When no upstream is configured, `git rev-parse` exits non-zero (suppressed by `2>/dev/null`), `sed` receives empty pipe and exits 0, so `|| echo main` never fires. Result: `_base=""`.

**Test results (branch feat/ralph-loop-v2, no upstream pushed):**

| Scenario | Old pattern result | New pattern result |
|---|---|---|
| No upstream configured | `""` (broken) | `"main"` (correct) |
| Upstream set (origin/feat/ralph-loop-v2) | `"feat/ralph-loop-v2"` | `"feat/ralph-loop-v2"` |

Both scenarios pass. Fix is correct.

## Regression checks

| Previously broken behavior | Status | Evidence |
| --- | --- | --- |
| `ralph --help` exits 0 (fixed 2026-04-09) | PASS | exit code 0 observed |
| `ralph-pipeline.sh --help` exits 0 (fixed in pipeline-robustness) | PASS | exit code 0 observed |
| `ralph-pipeline.sh --dry-run --max-iterations 3` completes exit 0 | PASS | exit code 0, status: complete, PR detected |
| `archive-plan.sh` accepts directory plans | PASS | directory moved from active/ to archive/ |
| `ralph-orchestrator.sh --dry-run` rejects single-file plans | PASS | exit 1 with descriptive error |
| `ralph-loop-init.sh --pipeline` sets plan to fullpath | PASS | task.json plan field = `/tmp/test-ralph-loop-init-plan.md` |

## Failure analysis

| Test | Error | Root cause | Proposed fix |
| --- | --- | --- | --- |
| — | — | — | — |

No failures. All 20 tests passed.

## Test gaps

1. **Live API paths**: `ralph-pipeline.sh` Inner Loop and Outer Loop with real `claude -p` calls — untestable without API access. Covered by prior integration evidence.
2. **Multi-worktree execution**: `ralph-orchestrator.sh` actual worktree creation and parallel execution — dry-run validates plan parsing; live execution requires non-trivial git state.
3. **Dependency-ordered slice execution at runtime**: Sequential execution for slices with `dependencies:` is not exercised by dry-run. The normalization fix (Fix 1) is correct, but end-to-end dependency sequencing requires live API.
4. **`"slice-N"` shorthand dep names**: If users write `"slice-1"` as a dep for a file `slice-1-<longname>.md`, the normalized slug `"1"` won't match `"1-<longname>"`. Pre-existing design convention issue. Not a regression from Fix 1.

## Observations

- Test cleanup: `ralph-orchestrator.sh --dry-run` creates integration branches as a side effect (before the dry-run guard). Cleaned up after each test with `git branch -d`.
- `run-test.sh` canonical runner returns exit 0 with "No language verifier ran" — expected behavior for shell-script scaffold.
- The `hook-parity-checklist.json` and `preflight-probe.json` in `docs/evidence/` were updated by the dry-run test (expected, pre-existing behavior noted in MEMORY.md).

## Verdict

- Pass: 20 / 20
- Fail: 0 / 20
- Blocked: 0 / 20

**PASS — all 20 tests passed. Both Codex fixes (Fix 1: dependency slug normalization, Fix 2: base branch fallback) verified correct. All prior regression tests continue to pass. Branch feat/ralph-loop-v2 is clear for PR creation.**
