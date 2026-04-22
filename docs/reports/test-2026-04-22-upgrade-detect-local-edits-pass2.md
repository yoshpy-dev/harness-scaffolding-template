# Test report: upgrade detect local edits (pass 2)

- Date: 2026-04-22
- Plan: `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md`
- Branch: `feat/upgrade-detect-local-edits`
- Base commit under test: `a920352` ("fix(upgrade): honor --force and survive template removal for unmanaged entries")
- Tester: tester subagent (Claude Code)
- Scope: second pass after Codex review fixes. Verify the four newly added regression tests and re-run the full suite with `-count=1` (no cache). Focus: `--force` re-adoption of `Managed=false` entries, and `Managed=false` survival across template removal.
- Evidence: `docs/evidence/test-2026-04-22-upgrade-detect-local-edits-pass2.log`

## Test execution

| Suite / Command | Tests | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- |
| `./scripts/run-test.sh` (mojibake + gofmt + staticcheck + `go test ./...`) | — | pass | 0 | — | cached |
| `go test ./... -count=1` (no cache) | 10 pkgs | 10 ok | 0 | 2 (scaffold) | 4.27s longest pkg |
| `go test ./internal/upgrade/ ./internal/cli/ -run 'Unmanaged\|ForceReadopts\|SurvivesTemplateRemoval' -v -count=1` (focused) | 7 | 7 | 0 | 0 | 0.67s combined |
| `go test ./internal/upgrade/ -v -count=1` (full package) | 25 | 25 | 0 | 0 | 0.23s |
| `go test ./internal/cli/ -v -count=1` (full package) | 21 | 21 | 0 | 0 | 0.85s |

Full-suite package roll-up (`go test ./... -count=1`, all `ok`):

- `internal/action` 4.27s
- `internal/cli` 1.19s
- `internal/config` 1.02s
- `internal/scaffold` 1.39s (2 `SKIP`: `TestBaseFS_WithMockFS`, `TestAvailablePacks_WithMockFS` — pre-existing, `EmbeddedFS` not initialised outside `cmd/ralph/`)
- `internal/state` 2.10s
- `internal/ui` 2.78s
- `internal/ui/panes` 3.55s
- `internal/upgrade` 1.73s
- `internal/watcher` 4.13s
- Roots `./`, `cmd/ralph`, `cmd/ralph-tui` — `[no test files]` (expected)

### Focused run detail (all PASS)

- `upgrade.TestComputeDiffs_Unmanaged_IsSilentSkip`
- `upgrade.TestComputeDiffs_Unmanaged_SurvivesTemplateRemoval` (new in pass 2)
- `upgrade.TestComputeDiffs_Unmanaged_CarriesNewContentForForceReadoption` (new in pass 2)
- `upgrade.TestComputeDiffs_Unmanaged_SilentSkipWhenDiskMissing`
- `cli.TestRunUpgrade_InteractiveSkip_WritesUnmanaged`
- `cli.TestRunUpgrade_ForceReadoptsUnmanaged` (new in pass 2)
- `cli.TestRunUpgrade_UnmanagedSurvivesTemplateRemovalAcrossRuns` (new in pass 2)

## Coverage

Per-package coverage (`go test -coverprofile`):

| Package | Pass 1 | Pass 2 | Delta |
| --- | --- | --- | --- |
| `internal/upgrade` | 93.6% | 93.8% | +0.2 pp |
| `internal/cli` | 37.8% | 38.4% | +0.6 pp |
| `internal/scaffold` | 65.9% | (unchanged, not re-run; no code changes in this pass) | — |

Per-function highlights for code touched by this plan (pass 2):

| Function | Coverage | Notes |
| --- | --- | --- |
| `internal/upgrade/unified_diff.go:UnifiedDiff` | 100.0% | Unchanged vs pass 1. |
| `internal/upgrade/diff.go:ComputeDiffsWithManifest` | 92.3% | +0.6 pp vs pass 1 (91.7%). Covers template-removal survival and `NewContent` carry-through for `--force` re-adoption. |
| `internal/cli/upgrade.go:runUpgrade` | 100.0% | Entry wrapper. |
| `internal/cli/upgrade.go:runUpgradeIO` | 69.7% | +0.9 pp vs pass 1 (68.8%). Now covers `--force` path against `Managed=false` and multi-run survival of unmanaged entries. |
| `internal/cli/upgrade.go:resolveConflict` | 81.8% | Unchanged vs pass 1. |
| `internal/cli/upgrade.go:showDiff` | 91.7% | Unchanged. |

Zero-coverage functions (all pre-existing, out of scope for this plan):

- `internal/upgrade/diff.go:ComputeDiffsNoRemovals` (0.0%)
- `internal/cli/status.go` TUI-mode functions, `runPipeline`, `findScript`, `doctor.go:countFailed`, `doctor.go:checkEmbeddedPacks`, `init.go:runInitNonInteractive`, `pack.go:addPack`.

Notes:
- Coverage delta is small because the four new tests exercise branches that were already partially covered. Their value is regression-safety against the specific Codex-flagged bugs (`--force` not re-adopting unmanaged entries, and unmanaged entries being dropped when removed from templates), not statement-level new coverage.

## Failure analysis

| Test | Error | Root cause | Proposed fix |
| --- | --- | --- | --- |
| — | None | — | — |

No failing tests.

## Regression checks

Regression suites from the plan's test plan all pass:

| Previously broken behavior | Status |
| --- | --- |
| `TestComputeDiffs_Skip_PreservesHash` | PASS |
| `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate` | PASS |
| `TestComputeDiffs_EmptyHashConflictsWhenDiskDiffers` | PASS |
| `TestComputeDiffs_AddBecomesConflictWhenDiskDiffers` | PASS |
| `TestComputeDiffsWithManifest_PackPrefixedSubset` | PASS |
| `TestComputeDiffs_AddStaysAddWhenDiskMatchesTemplate` | PASS |
| `TestRunUpgrade_HealsCorruptedManifest` | PASS |
| `TestRunUpgrade_DropsPacksRemovedFromTemplates` | PASS |
| `TestRunUpgrade_ReportsDeletedPackFileOnceThenDrops` | PASS |
| `TestRunUpgrade_SurvivesAvailablePacksFailure` | PASS |
| `TestRunUpgrade_SameVersionIsIdempotent` | PASS |

### Pass 2 new tests (Codex-driven)

| Test | Purpose | Status |
| --- | --- | --- |
| `TestComputeDiffs_Unmanaged_SurvivesTemplateRemoval` | `Managed=false` entry removed from templates → `ActionSkip` (not `ActionRemove`); manifest retains the unmanaged entry across template churn. | PASS |
| `TestComputeDiffs_Unmanaged_CarriesNewContentForForceReadoption` | When the template still ships the file and the entry is `Managed=false`, the returned `FileDiff` carries `NewContent` so `--force` has bytes to write back on re-adoption. | PASS |
| `TestRunUpgrade_ForceReadoptsUnmanaged` | CLI-level `--force` flips a `Managed=false` entry back to `{Hash: newHash, Managed: true}`, writing template bytes to disk. | PASS |
| `TestRunUpgrade_UnmanagedSurvivesTemplateRemovalAcrossRuns` | Running `ralph upgrade` repeatedly after a template removes a `Managed=false` file leaves the local file and manifest entry intact (user-owned contract survives template changes). | PASS |

### Acceptance-criteria mapping (plan AC9–AC11 plus new AC)

- AC9 (`Managed=false` silent skip): `TestComputeDiffs_Unmanaged_IsSilentSkip` + `TestRunUpgrade_NextRunAfterSkip_IsSilent` — unchanged from pass 1, still PASS.
- AC10 (`--force` overwrites local edit): `TestRunUpgrade_ForceOverwritesLocalEdit` — PASS.
- New AC: `--force` re-adopts `Managed=false` entries → `TestRunUpgrade_ForceReadoptsUnmanaged` — PASS. (Codex-raised gap closed in commit `a920352`.)
- New AC: `Managed=false` entries survive template removal → `TestComputeDiffs_Unmanaged_SurvivesTemplateRemoval` + `TestRunUpgrade_UnmanagedSurvivesTemplateRemovalAcrossRuns` — PASS.
- AC11 (`run-verify.sh` + `go test ./...` green): captured above.

Skipped tests (unchanged, pre-existing):

- `TestBaseFS_WithMockFS`, `TestAvailablePacks_WithMockFS` in `internal/scaffold` — skip with reason "EmbeddedFS not initialized (only available when built from cmd/ralph/)". Environment-conditional, not regressions.

## Test gaps

Unchanged from pass 1. Still minor and non-blocking:

1. `SetFileUnmanaged` shows 0.0% in `internal/scaffold`'s local coverage profile because no unit test inside `internal/scaffold/` calls it directly. Exercised end-to-end via `internal/upgrade/diff_test.go` and `internal/cli` interactive tests. A 5-line scaffold-package unit test would lift the local number without adding behavioral coverage. Not required by the plan.
2. CRLF / BOM input for `UnifiedDiff` is treated as opaque bytes (plan's Windows risk section accepts this). No dedicated CRLF-hunk rendering test; relied on byte-faithful passthrough.
3. `ComputeDiffsNoRemovals` remains at 0.0% — pre-existing, not touched by this plan.

No new gaps introduced in pass 2.

## Flakes

None observed across the pass 2 runs (cached `run-test.sh`, uncached `go test ./... -count=1`, and the focused subset). The one timing-sensitive suite tracked in tester memory (`test-ralph-signals.sh::test_loop_sigint`) is not in scope for this plan and was not exercised.

## Verdict

- Pass: yes
- Fail: no
- Blocked: no

Tests pass the gate. Codex-driven fixes for `--force` re-adoption and unmanaged-entry survival are covered by new regression tests. Safe to proceed to `/sync-docs` → `/codex-review` → `/pr`.
