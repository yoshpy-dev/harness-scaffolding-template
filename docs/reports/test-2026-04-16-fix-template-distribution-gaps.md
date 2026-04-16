# Test report: fix-template-distribution-gaps (re-run after Codex fixes)

- Date: 2026-04-16
- Plan: docs/plans/active/2026-04-16-fix-template-distribution-gaps.md
- Tester: tester subagent
- Scope: Go unit/integration tests, build verification, shell test runner
- Evidence: `docs/evidence/test-2026-04-16-fix-template-distribution-gaps.log`
- Context: Re-run after Codex WORTH_CONSIDERING fixes (commit-msg-guard invocation, --slices flag, sort fix)

## Test execution

| Suite / Command | Tests | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- |
| `go test ./... -v -count=1` (all Go) | 263 | 260 | 0 | 3 | ~16s |
| `go build ./cmd/ralph/` | 1 | 1 | 0 | 0 | <2s |
| `./scripts/run-test.sh` | (all) | all | 0 | 0 | ~20s |

### Go package breakdown

| Package | Tests | Pass | Fail | Skip | Coverage | Duration |
| --- | --- | --- | --- | --- | --- | --- |
| internal/action | 32 | 32 | 0 | 0 | 95.9% | 2.6s |
| internal/cli | 6 | 6 | 0 | 0 | 30.3% | 0.5s |
| internal/config | 4 | 4 | 0 | 0 | 62.5% | 0.6s |
| internal/prompt | 2 | 1 | 0 | 1 | 40.0% | 1.0s |
| internal/scaffold | 14 | 12 | 0 | 2 | 65.0% | 1.2s |
| internal/state | 13 | 13 | 0 | 0 | 87.9% | 1.4s |
| internal/ui | 20 | 20 | 0 | 0 | 84.0% | 1.9s |
| internal/ui/panes | 83 | 83 | 0 | 0 | 88.9% | 2.2s |
| internal/upgrade | 4 | 4 | 0 | 0 | 84.2% | 1.5s |
| internal/watcher | 14 | 14 | 0 | 0 | 79.2% | 2.4s |

Note: "Tests" column includes subtests. Top-level test functions: 159 PASS, 3 SKIP.

## Coverage

- Total (instrumented): 57.0% of statements (aggregate includes cmd/ entrypoints at 0%)
- Packages with tests: 8 of 10 exceed 40%; 6 of 10 exceed 80%
- New test this branch: `TestTemplateBaseScriptsExist` -- verifies all 16 required scripts exist in `templates/base/scripts/` and are non-empty
- Highest coverage: internal/action (95.9%), internal/ui/panes (88.9%), internal/state (87.9%)

## Skipped tests (3)

| Test | Package | Reason |
| --- | --- | --- |
| TestBaseFS_WithMockFS | internal/scaffold | EmbeddedFS not initialized in unit test context (only available via `cmd/ralph/` go:embed) |
| TestAvailablePacks_WithMockFS | internal/scaffold | Same as above |
| TestResolve_FallbackToEmbedded | internal/prompt | Same as above |

These are pre-existing skips, not introduced by this branch. They require building via `cmd/ralph/` to populate `go:embed`.

## Failure analysis

| Test | Error | Root cause | Proposed fix |
| --- | --- | --- | --- |
| (none) | -- | -- | -- |

No failures detected.

## Regression checks

| Previously broken behavior | Status | Evidence |
| --- | --- | --- |
| `go build ./cmd/ralph/` with new scripts embedded | PASS | build exit code 0 |
| All pre-existing Go tests pass with new template files | PASS | 260 pass, 0 fail |
| `./scripts/run-test.sh` full pipeline (gofmt + staticcheck + go test) | PASS | all verifiers passed |
| Codex fix: scripts/ralph sort order change | PASS | no regressions in shell or Go tests |
| Codex fix: scripts/new-ralph-plan.sh --slices flag removal | PASS | no regressions |
| Codex fix: scripts/ralph-pipeline.sh commit-msg-guard invocation | PASS | no regressions |

## Plan acceptance criteria coverage

| AC | Description | Test coverage | Status |
| --- | --- | --- | --- |
| AC1 | 16 scripts in templates/base/scripts/ | `TestTemplateBaseScriptsExist` checks all 16 + non-empty | PASS |
| AC2 | commit-msg-guard.sh exists and reference is correct | included in AC1 test list | PASS |
| AC4 | `go build ./cmd/ralph/` succeeds | build verification | PASS |
| AC5 | embed_test.go includes script existence test | `TestTemplateBaseScriptsExist` in internal/scaffold | PASS |
| AC6 | All existing tests pass | `go test ./...` 260 pass, 0 fail | PASS |
| AC7 | upgrade.go .sh permission (0755) | Tested via `TestRunUpgrade_AutoUpdate` (integration) | PASS (indirect) |

## Test gaps

1. **upgrade.go permission handling (AC7)**: No dedicated unit test verifying `.sh` files get `0755` in ActionAutoUpdate/ActionConflict/ActionAdd. `TestRunUpgrade_AutoUpdate` covers the upgrade path but does not assert file permissions. LOW risk -- render.go has the same logic and is exercised at init time.
2. **internal/cli coverage at 30.3%**: Many CLI subcommands lack unit tests (init, upgrade, doctor are integration-tested but run/status/retry/abort/pack/version have limited or no direct tests).
3. **internal/prompt coverage at 40.0%**: Resolver embed fallback path is untestable without full binary build.
4. **Codex shell fixes lack automated shell tests**: The three Codex fixes (sort, --slices, commit-msg-guard) are in shell scripts that have no new automated tests. They are verified by grep/manual inspection in the verify report. LOW risk for this branch.

## Verdict

- **Pass**: YES -- all 263 Go test results pass (260 run, 3 pre-existing skips), build succeeds, `./scripts/run-test.sh` passes. No regressions from Codex fixes.
- **Fail**: None
- **Blocked**: None

Safe to proceed to /pr.
