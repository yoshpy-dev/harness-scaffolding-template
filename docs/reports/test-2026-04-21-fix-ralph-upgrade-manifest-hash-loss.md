# Test report: fix-ralph-upgrade-manifest-hash-loss

- Date: 2026-04-21
- Plan: `docs/plans/active/2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md`
- Tester: tester subagent (Claude)
- Scope: Behavioral tests only (unit + integration + regression) for the upgrade manifest hash heal / pack namespacing fix. Static analysis and verify handled upstream by `/verify`.
- Evidence: `docs/evidence/test-2026-04-21-fix-ralph-upgrade-manifest-hash-loss.log`
- Branch: `fix/ralph-upgrade-manifest-hash-loss`

## Test execution

| Suite / Command | Tests | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- |
| `go test ./... -count=1` (full repo) | 167 | 165 | 0 | 2 | ~22s wall (parallel packages) |
| `go test -v -run 'TestComputeDiffs_.*' ./internal/upgrade/...` (targeted) | 8 | 8 | 0 | 0 | 0.226s |
| `go test -v -run 'TestRunUpgrade_.*' ./internal/cli/...` (targeted) | 4 | 4 | 0 | 0 | 0.369s |

### Package breakdown (from `go test ./... -count=1`)

| Package | Result | Duration |
| --- | --- | --- |
| `internal/action` | ok | 3.855s |
| `internal/cli` | ok | 0.813s |
| `internal/config` | ok | 2.840s |
| `internal/scaffold` | ok | 0.966s |
| `internal/state` | ok | 1.319s |
| `internal/ui` | ok | 2.237s |
| `internal/ui/panes` | ok | 3.268s |
| `internal/upgrade` | ok | 1.474s |
| `internal/watcher` | ok | 4.121s |
| root, `cmd/ralph`, `cmd/ralph-tui` | no test files | — |

### Plan-targeted tests (all PASS)

| Test | Package | Status |
| --- | --- | --- |
| `TestComputeDiffs_Skip_PreservesHash` | `internal/upgrade` | PASS |
| `TestComputeDiffsWithManifest_PackPrefixedSubset` | `internal/upgrade` | PASS |
| `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate` | `internal/upgrade` | PASS |
| `TestComputeDiffs_EmptyHashConflictsWhenDiskDiffers` | `internal/upgrade` | PASS |
| `TestRunUpgrade_SameVersionIsIdempotent` | `internal/cli` | PASS |
| `TestRunUpgrade_HealsCorruptedManifest` | `internal/cli` | PASS |
| `TestRunUpgrade_PreservesOldPackEntriesOnDiffFailure` | `internal/cli` | PASS |

### Regression tests (pre-existing)

| Test | Package | Status |
| --- | --- | --- |
| `TestComputeDiffs_AutoUpdate` | `internal/upgrade` | PASS |
| `TestComputeDiffs_Conflict` | `internal/upgrade` | PASS |
| `TestComputeDiffs_AddNewFile` | `internal/upgrade` | PASS |
| `TestComputeDiffs_RemoveFile` | `internal/upgrade` | PASS |
| `TestRunUpgrade_AutoUpdate` | `internal/cli` | PASS |

## Coverage

- Statement (internal/upgrade): **80.9%**
- Statement (internal/cli): **31.1%**
- Branch: Not measured (Go tooling default does not report branch coverage).
- Function: Not measured separately (statement coverage is the proxy).
- Notes:
  - `internal/upgrade` is the main surface of this change and is well-covered at 80.9%. The four new diff tests exercise the three new/changed branches (ActionSkip with NewHash, empty-hash heal → skip, empty-hash conflict) plus pack-prefixed subset processing.
  - `internal/cli` reports 31.1%; this package is a CLI orchestration layer dominated by cobra wiring, stdout/stderr formatting, and interactive prompts. The new integration tests cover the targeted `runUpgrade` paths (idempotency, corrupted-manifest heal, pack diff failure preservation). Overall package coverage is limited by untested non-upgrade subcommands rather than gaps in this change.

## Failure analysis

| Test | Error | Root cause | Proposed fix |
| --- | --- | --- | --- |
| — | — | — | — |

No failures.

## Regression checks

| Previously broken behavior | Status | Evidence |
| --- | --- | --- |
| Same-version `ralph upgrade` marking untouched base files as `modified locally` on the 2nd run (missing `NewHash` on `ActionSkip`) | Fixed | `TestRunUpgrade_SameVersionIsIdempotent` asserts no empty-hash entries remain in manifest after two upgrades; `TestComputeDiffs_Skip_PreservesHash` asserts `NewHash` is populated on skip |
| Pack files appearing simultaneously as `removed from template` and `new file` (monolithic `ComputeDiffs` saw pack-prefixed manifest keys vs. root-relative pack FS) | Fixed | `TestComputeDiffsWithManifest_PackPrefixedSubset` (no double-classification with subset manifest + pack FS) |
| Already-corrupted manifests (`hash = ""`) needing forced overwrite to recover | Fixed | `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate` + `TestRunUpgrade_HealsCorruptedManifest` (heals in a single same-version upgrade, no write) |
| User-edited files with corrupted hash wrongly auto-healed | Preserved safety | `TestComputeDiffs_EmptyHashConflictsWhenDiskDiffers` keeps them as conflict (no silent overwrite) |
| Pack FS / diff failure wiping old manifest pack entries | Fixed | `TestRunUpgrade_PreservesOldPackEntriesOnDiffFailure` (unknown pack triggers warning but old entries persist) |

## Acceptance criteria → test mapping

| AC | Covering test(s) | Status |
| --- | --- | --- |
| AC1: Same-version upgrade ×2 shows no modified/removed/new-file entries | `TestRunUpgrade_SameVersionIsIdempotent` | PASS |
| AC2: Manifest base entries never carry empty hash after upgrade | `TestRunUpgrade_SameVersionIsIdempotent`, `TestComputeDiffs_Skip_PreservesHash` | PASS |
| AC3: `hash = ''` + disk==template heals to ActionSkip without forced overwrite | `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate`, `TestRunUpgrade_HealsCorruptedManifest` | PASS |
| AC4: Pack file not classified as both `removed` and `new file` | `TestComputeDiffsWithManifest_PackPrefixedSubset` | PASS |
| AC5: Failed pack FS/diff preserves old manifest entries | `TestRunUpgrade_PreservesOldPackEntriesOnDiffFailure` | PASS |
| AC6: Existing `TestComputeDiffs_AutoUpdate/_Conflict/_AddNewFile/_RemoveFile` still green | All four pass | PASS |
| AC7 (a): ActionSkip has non-empty `NewHash` | `TestComputeDiffs_Skip_PreservesHash` | PASS |
| AC7 (b): Namespaced manifest + pack FS → pack files not double-classified | `TestComputeDiffsWithManifest_PackPrefixedSubset` | PASS |
| AC7 (c): Empty-hash + disk match → ActionSkip with heal | `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate` | PASS |
| AC7 (d): Pack diff failure → old entry preserved | `TestRunUpgrade_PreservesOldPackEntriesOnDiffFailure` | PASS |
| AC8: `go test ./...` green (verify handles `run-verify.sh`) | Full `go test ./... -count=1` green | PASS |

Every acceptance criterion maps to at least one passing test.

## Skipped tests

| Test | Reason (from source) | Assessment |
| --- | --- | --- |
| `TestBaseFS_WithMockFS` | Placeholder skip in `internal/scaffold` (mock FS not wired) | Unrelated to this change; pre-existing |
| `TestAvailablePacks_WithMockFS` | Placeholder skip in `internal/scaffold` (mock FS not wired) | Unrelated to this change; pre-existing |

Both skips predate this branch and do not affect the upgrade fix.

## Test gaps

- `internal/cli` coverage at 31.1% reflects untested non-upgrade subcommands (`doctor`, `abort`, `retry`, parts of `pack`, `version`, etc.). These are outside the scope of this plan but represent long-term coverage debt for the CLI layer.
- No end-to-end test exercises the real `scaffold.PackFS` failure path — the integration test synthesizes failure by injecting an unknown pack name into `installedPacks`. This is sufficient because the production failure mode is exactly that (missing pack) and it triggers the same code path; a hypothetical "valid pack name with corrupted embed FS" case is not realistically reachable without patching embed state.
- Interactive prompt paths (stdin-attached confirmation for conflicts) are not exercised by tests; the plan scopes to non-interactive runs. Follow-up work could add a `*testing.T` harness over the prompt, tracked as future CLI coverage.
- No flaky tests observed in this run. Re-running the targeted suites twice produced identical results.

## Verdict

- Pass: yes
- Fail: no
- Blocked: no

**Tests are green. Safe to proceed to `/sync-docs` → `/codex-review` → `/pr` per the post-implementation pipeline.**

## Round 2 (post-codex)

- Date: 2026-04-21
- Trigger: Codex ACTION_REQUIRED finding — pack removal detection silently dropped. Fix landed in commit `d16cb4d` ("fix(upgrade): restore pack removal detection and drop disappeared packs").
- Evidence: `docs/evidence/test-2026-04-21-fix-ralph-upgrade-manifest-hash-loss-round2.log`
- Command: `go test ./... -count=1` (green, exit 0)

### Test suite delta vs. Round 1

| Item | Round 1 | Round 2 | Delta |
| --- | --- | --- | --- |
| Total Go tests | 167 | 168 | +1 |
| Passed | 165 | 166 | +1 |
| Failed | 0 | 0 | 0 |
| Skipped | 2 | 2 | 0 |

Net +1 reflects the plan-driven test churn in `internal/cli`:
- `TestRunUpgrade_PreservesOldPackEntriesOnDiffFailure` was **replaced** (the silent-preserve behavior it asserted is no longer the contract — packs absent from templates are now intentionally dropped from the manifest).
- `TestRunUpgrade_DropsPacksRemovedFromTemplates` **new** (replacement).
- `TestRunUpgrade_ReportsDeletedPackFile` **new** (net add).

### New / replaced tests — status

| Test | Package | Status | Evidence |
| --- | --- | --- | --- |
| `TestRunUpgrade_DropsPacksRemovedFromTemplates` (replaces `TestRunUpgrade_PreservesOldPackEntriesOnDiffFailure`) | `internal/cli` | PASS (0.02s) | Stdout `Notice: pack "ghostpack" no longer exists in templates — manifest tracking dropped (files on disk left untouched)` |
| `TestRunUpgrade_ReportsDeletedPackFile` | `internal/cli` | PASS (0.02s) | Stdout `⚠ packs/languages/golang/deprecated.sh (removed from template — review and delete manually)` + `Removed from template: 1 files` |

Grep confirms the old test name is gone from `internal/cli/cli_test.go` (no stale references).

### Round 1 regression check (no regressions)

All previously-green plan-targeted tests still PASS in Round 2:

| Test | Package | Round 2 status |
| --- | --- | --- |
| `TestComputeDiffs_Skip_PreservesHash` | `internal/upgrade` | PASS |
| `TestComputeDiffsWithManifest_PackPrefixedSubset` | `internal/upgrade` | PASS |
| `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate` | `internal/upgrade` | PASS |
| `TestComputeDiffs_EmptyHashConflictsWhenDiskDiffers` | `internal/upgrade` | PASS |
| `TestComputeDiffs_AutoUpdate` / `_Conflict` / `_AddNewFile` / `_RemoveFile` | `internal/upgrade` | PASS (all four) |
| `TestRunUpgrade_SameVersionIsIdempotent` | `internal/cli` | PASS |
| `TestRunUpgrade_HealsCorruptedManifest` | `internal/cli` | PASS |
| `TestRunUpgrade_AutoUpdate` | `internal/cli` | PASS |

### Package breakdown (Round 2)

| Package | Result | Duration |
| --- | --- | --- |
| `internal/action` | ok | 4.223s |
| `internal/cli` | ok | 0.960s |
| `internal/config` | ok | 1.083s |
| `internal/scaffold` | ok | 1.750s |
| `internal/state` | ok | 1.426s |
| `internal/ui` | ok | 2.096s |
| `internal/ui/panes` | ok | 3.575s |
| `internal/upgrade` | ok | 2.778s |
| `internal/watcher` | ok | 4.041s |
| root, `cmd/ralph`, `cmd/ralph-tui` | no test files | — |

### Skipped (unchanged from Round 1)

`TestBaseFS_WithMockFS` and `TestAvailablePacks_WithMockFS` in `internal/scaffold` — pre-existing placeholder skips, unrelated to this change.

### Round 2 verdict

- Pass: yes
- Fail: no
- Blocked: no
- Regressions: none

**Tests remain green after the Codex-driven pack-removal fix. Safe to proceed to `/sync-docs` → `/codex-review` (re-run) → `/pr`.**

## Round 3 (post-codex-2)

- Date: 2026-04-21
- Trigger: Round 2 Codex follow-up — (1) ACTION_REQUIRED: `ActionRemove` used to preserve the manifest entry via `OldHash`, re-emitting the "removed from template" notice on every subsequent upgrade (broke same-version idempotency, surfaced now that pack files correctly trigger `ActionRemove`). (2) WORTH_CONSIDERING: test manifest-key assertions were hard-coded with forward slashes and would fail on Windows (`executeInit` builds keys via `filepath.Join`). Fix landed in commit `6f038de` ("fix(upgrade): drop removed entries from manifest and harden tests").
- Evidence: `docs/evidence/test-2026-04-21-fix-ralph-upgrade-manifest-hash-loss-round3.log`
- Command: `go test ./... -count=1` (green, exit 0)

### Test suite delta vs. Round 2

| Item | Round 2 | Round 3 | Delta |
| --- | --- | --- | --- |
| Total Go tests | 168 | 168 | 0 |
| Passed | 166 | 166 | 0 |
| Failed | 0 | 0 | 0 |
| Skipped | 2 | 2 | 0 |

Net 0 tests added. Round 3 is a **rename + strengthen** of an existing test, plus assertion-hardening across the two new Round 2 tests:
- `TestRunUpgrade_ReportsDeletedPackFile` → **renamed** to `TestRunUpgrade_ReportsDeletedPackFileOnceThenDrops` (reflects the new two-phase contract: notice emitted once, then dropped).
- Body expanded to (a) capture stdout via `os.Pipe()` and assert the pack-scoped notice appears on the first upgrade, (b) re-read the manifest and assert the entry is dropped, (c) run a second same-version upgrade with stdout captured and assert "removed from template" is NOT re-emitted.
- `TestRunUpgrade_DropsPacksRemovedFromTemplates` gained a positive assertion that `golang` is retained in `Meta.Packs` (closes the Round 2 self-review LOW).
- `TestRunUpgrade_SameVersionIsIdempotent` pack-key assertions switched from `"packs/languages/golang/README.md"` string literals to `filepath.Join("packs", "languages", "golang", "README.md")` for Windows portability.

### Round 3 targeted tests — status

| Test | Package | Status | Evidence |
| --- | --- | --- | --- |
| `TestRunUpgrade_ReportsDeletedPackFileOnceThenDrops` (renamed + strengthened) | `internal/cli` | PASS (0.03–0.04s) | First-upgrade stdout contains the namespaced pack-file notice (`packs/languages/golang/deprecated.sh`); manifest drop verified by `m2.Files[deprecatedEntry]` check; second upgrade stdout does NOT contain `"removed from template"` |
| `TestRunUpgrade_DropsPacksRemovedFromTemplates` (positive retention assertion added) | `internal/cli` | PASS (0.03s) | `ghostpack` dropped from `Meta.Packs` AND `golangFound == true` retention assertion passes |
| `TestRunUpgrade_SameVersionIsIdempotent` (`filepath.Join` keys) | `internal/cli` | PASS (0.03s) | `packReadme := filepath.Join("packs", "languages", "golang", "README.md")` found in manifest; no empty-hash entries; no unprefixed `README.md` leak |

### Round 2 regression check (no regressions elsewhere)

All previously-green plan-targeted tests still PASS in Round 3:

| Test | Package | Round 3 status |
| --- | --- | --- |
| `TestComputeDiffs_Skip_PreservesHash` | `internal/upgrade` | PASS |
| `TestComputeDiffsWithManifest_PackPrefixedSubset` | `internal/upgrade` | PASS |
| `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate` | `internal/upgrade` | PASS |
| `TestComputeDiffs_EmptyHashConflictsWhenDiskDiffers` | `internal/upgrade` | PASS |
| `TestComputeDiffs_AutoUpdate` / `_Conflict` / `_AddNewFile` / `_RemoveFile` | `internal/upgrade` | PASS (all four) |
| `TestRunUpgrade_HealsCorruptedManifest` | `internal/cli` | PASS |
| `TestRunUpgrade_AutoUpdate` | `internal/cli` | PASS |
| `TestExecuteInit_*` (3 tests), `TestRunDoctor_Passes`, `TestNewRootCmd_HasAllSubcommands` | `internal/cli` | PASS |

### Package breakdown (Round 3)

| Package | Result | Duration |
| --- | --- | --- |
| `internal/action` | ok | 2.248s |
| `internal/cli` | ok | 0.597s |
| `internal/config` | ok | 0.550s |
| `internal/scaffold` | ok | 0.725s |
| `internal/state` | ok | 1.408s |
| `internal/ui` | ok | 0.913s |
| `internal/ui/panes` | ok | 1.818s |
| `internal/upgrade` | ok | 1.063s |
| `internal/watcher` | ok | 3.200s |
| root, `cmd/ralph`, `cmd/ralph-tui` | no test files | — |

### Coverage (Round 3)

- `internal/upgrade`: **80.9%** (unchanged — no production code changes in this package in Round 3)
- `internal/cli`: **31.6%** (+0.5pp vs. Round 2's 31.1% — new stdout-capture branches in `TestRunUpgrade_ReportsDeletedPackFileOnceThenDrops` hit additional `upgrade.go` print paths)

### Skipped (unchanged)

`TestBaseFS_WithMockFS` and `TestAvailablePacks_WithMockFS` in `internal/scaffold` — pre-existing placeholder skips, unrelated to this change.

### Round 3 totals

- Total: 168
- Passed: 166
- Failed: 0
- Skipped: 2

### Round 3 verdict

- Pass: yes
- Fail: no
- Blocked: no
- Regressions: none

**Tests remain green after the Round 2 Codex follow-up fixes (manifest drop on `ActionRemove` + `filepath.Join` portability). All three specifically-called-out assertions (renamed stdout-capture test, positive golang retention, `filepath.Join` keys) pass. Safe to proceed to `/sync-docs` → `/codex-review` (re-run) → `/pr`.**

## Round 4 (post-codex-3)

- Date: 2026-04-21
- Trigger: Round 3 Codex follow-up P2 — `scaffold.AvailablePacks()` returning an error (e.g. missing embedded `templates/packs/` directory, `ReadDir` failure) used to abort `runUpgrade` before base diffs could be written, so a pack-metadata glitch would block base-file updates entirely. Fix landed in commit `0d1c4b0` ("fix(upgrade): keep upgrading when AvailablePacks fails"): downgrades the error to a `Warning:` line, preserves every installed pack's manifest entries as a transient fallback, and continues with base upgrade.
- Evidence: `docs/evidence/test-2026-04-21-fix-ralph-upgrade-manifest-hash-loss-round4.log`
- Command: `go test ./... -count=1` (green, exit 0)

### Test suite delta vs. Round 3

| Item | Round 3 | Round 4 | Delta |
| --- | --- | --- | --- |
| Total Go tests | 168 | 169 | +1 |
| Passed | 166 | 167 | +1 |
| Failed | 0 | 0 | 0 |
| Skipped | 2 | 2 | 0 |

Net +1 reflects the single new test added for this Codex fix:
- `TestRunUpgrade_SurvivesAvailablePacksFailure` **new** in `internal/cli/cli_test.go:365`. Exercises the fallback path by pointing `scaffold.PackFS()` at a non-existent embedded directory so `AvailablePacks()` returns an error, then asserts (a) the upgrade does not abort, (b) the `Warning: unable to list available packs … (preserving installed pack entries)` line is emitted, and (c) the installed `golang` pack manifest entries are preserved.

### Round 4 targeted tests — status

| Test | Package | Status | Evidence |
| --- | --- | --- | --- |
| `TestRunUpgrade_SurvivesAvailablePacksFailure` (new) | `internal/cli` | PASS (0.02–0.03s) | Verbose stdout contains `Warning: unable to list available packs: open templates/packs: file does not exist (preserving installed pack entries)`; subsequent `Updated: 0 files / Skipped: 0 files / Manifest updated: .ralph/manifest.toml` confirms the run completed instead of aborting. |

### Round 3 regression check (no regressions)

All previously-green plan-targeted tests still PASS in Round 4 (verified from `/tmp/round4-verbose.log`):

| Test | Package | Round 4 status |
| --- | --- | --- |
| `TestComputeDiffs_Skip_PreservesHash` | `internal/upgrade` | PASS |
| `TestComputeDiffsWithManifest_PackPrefixedSubset` | `internal/upgrade` | PASS |
| `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate` | `internal/upgrade` | PASS |
| `TestComputeDiffs_EmptyHashConflictsWhenDiskDiffers` | `internal/upgrade` | PASS |
| `TestComputeDiffs_AutoUpdate` / `_Conflict` / `_AddNewFile` / `_RemoveFile` | `internal/upgrade` | PASS (all four) |
| `TestRunUpgrade_SameVersionIsIdempotent` | `internal/cli` | PASS |
| `TestRunUpgrade_HealsCorruptedManifest` | `internal/cli` | PASS |
| `TestRunUpgrade_AutoUpdate` | `internal/cli` | PASS |
| `TestRunUpgrade_DropsPacksRemovedFromTemplates` | `internal/cli` | PASS |
| `TestRunUpgrade_ReportsDeletedPackFileOnceThenDrops` | `internal/cli` | PASS |

### Package breakdown (Round 4)

| Package | Result | Duration |
| --- | --- | --- |
| `internal/action` | ok | 4.059s |
| `internal/cli` | ok | 0.827s |
| `internal/config` | ok | 1.261s |
| `internal/scaffold` | ok | 0.928s |
| `internal/state` | ok | 1.954s |
| `internal/ui` | ok | 1.622s |
| `internal/ui/panes` | ok | 3.430s |
| `internal/upgrade` | ok | 2.651s |
| `internal/watcher` | ok | 4.817s |
| root, `cmd/ralph`, `cmd/ralph-tui` | no test files | — |

### Coverage (Round 4)

- `internal/upgrade`: **80.9%** (unchanged — no production code changes in this package in Round 4)
- `internal/cli`: **32.5%** (+0.9pp vs. Round 3's 31.6% — new warning/fallback branch in `upgrade.go` is now covered by `TestRunUpgrade_SurvivesAvailablePacksFailure`)

### Skipped (unchanged)

`TestBaseFS_WithMockFS` and `TestAvailablePacks_WithMockFS` in `internal/scaffold` — pre-existing placeholder skips, unrelated to this change.

### Round 4 totals

- Total: 169
- Passed: 167
- Failed: 0
- Skipped: 2

### Round 4 verdict

- Pass: yes
- Fail: no
- Blocked: no
- Regressions: none

**Tests remain green after the Round 3 Codex P2 follow-up fix (`AvailablePacks` failure no longer aborts `runUpgrade`). The new `TestRunUpgrade_SurvivesAvailablePacksFailure` passes, all prior-round targeted tests are regression-free, and `internal/cli` coverage improved by +0.9pp. Safe to proceed to `/sync-docs` → `/codex-review` (re-run) → `/pr`.**

## Round 5 (post-codex-4)

- Date: 2026-04-21
- Commit under test: `ef8e3ed` ("fix(upgrade): avoid heal loop and prevent silent reintroduction overwrites")
- Branch: `fix/ralph-upgrade-manifest-hash-loss`
- Command: `go test ./... -count=1 -v`
- Evidence: `docs/evidence/test-2026-04-21-fix-ralph-upgrade-manifest-hash-loss-round5.log` (749 lines)
- Scope: Round 5 revalidates the Codex-4 follow-up fix (`ef8e3ed`) which closes two safety holes:
  1. **Heal-loop guard** — when a manifest entry has an empty `OldHash` but the disk file differs from the template, the diff must be `ActionConflict` and carry `OldHash == newHash` (so the subsequent `applyDiffs` writes a non-empty hash instead of re-healing the same file on the next run).
  2. **Reintroduction safeguard** — when a file is absent from the manifest but present on disk with content that differs from a newly-reintroduced template file, the diff must surface as `ActionConflict` instead of `ActionAdd` (prevents silent overwrite of a user's kept file when a later template release re-adds a previously-removed path).

### Round 5 test execution

| Suite / Command | Tests | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- |
| `go test ./... -count=1 -v` | 171 | 169 | 0 | 2 | ~3s wall (parallel packages) |

### New / updated tests in this round (all PASS)

| Test | Package | Status | Purpose |
| --- | --- | --- | --- |
| `TestComputeDiffs_EmptyHashConflictsWhenDiskDiffers` (updated) | `internal/upgrade` | PASS (0.00s) | Now asserts `diffs[0].OldHash == HashBytes(template)` in addition to `Action == ActionConflict`. This pins the heal contract: the conflict resolution must write the new template hash into the manifest, not leave it empty (otherwise the next `upgrade` run would heal-loop the same file). Evidence: `log:710-711`. |
| `TestComputeDiffs_AddBecomesConflictWhenDiskDiffers` (new) | `internal/upgrade` | PASS (0.00s) | Regression guard: a file absent from the manifest but present on disk with differing content must surface as `ActionConflict`, not `ActionAdd`. Without the fix in `ef8e3ed`, a template release that reintroduces a previously-removed path would silently overwrite the user's file. Evidence: `log:712-713`. |
| `TestComputeDiffs_AddStaysAddWhenDiskMatchesTemplate` (new) | `internal/upgrade` | PASS (0.00s) | Complementary case to the safeguard: if the disk file already matches the new template byte-for-byte, the diff must remain `ActionAdd` (no spurious conflict prompt). This ensures the new safeguard does not over-trigger on benign re-adds. Evidence: `log:714-715`. |

### Plan-targeted regression tests (all PASS)

| Test | Package | Round 5 status |
| --- | --- | --- |
| `TestComputeDiffs_Skip_PreservesHash` | `internal/upgrade` | PASS |
| `TestComputeDiffsWithManifest_PackPrefixedSubset` | `internal/upgrade` | PASS |
| `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate` | `internal/upgrade` | PASS |
| `TestComputeDiffs_AutoUpdate` / `_Conflict` / `_AddNewFile` / `_RemoveFile` | `internal/upgrade` | PASS (all four) |
| `TestRunUpgrade_AutoUpdate` | `internal/cli` | PASS |
| `TestRunUpgrade_SameVersionIsIdempotent` | `internal/cli` | PASS |
| `TestRunUpgrade_HealsCorruptedManifest` | `internal/cli` | PASS |
| `TestRunUpgrade_DropsPacksRemovedFromTemplates` | `internal/cli` | PASS |
| `TestRunUpgrade_ReportsDeletedPackFileOnceThenDrops` | `internal/cli` | PASS |
| `TestRunUpgrade_SurvivesAvailablePacksFailure` | `internal/cli` | PASS |

### Package breakdown (Round 5)

| Package | Result | Duration |
| --- | --- | --- |
| `internal/action` | ok | 2.364s |
| `internal/cli` | ok | 0.605s |
| `internal/config` | ok | 0.523s |
| `internal/scaffold` | ok | 0.893s |
| `internal/state` | ok | 1.604s |
| `internal/ui` | ok | 1.260s |
| `internal/ui/panes` | ok | 1.858s |
| `internal/upgrade` | ok | 1.073s |
| `internal/watcher` | ok | 2.340s |
| root, `cmd/ralph`, `cmd/ralph-tui` | no test files | — |

### Coverage (Round 5)

- `internal/upgrade`: **82.0%** (+1.1pp vs. Round 4's 80.9% — the two new `AddBecomesConflict` / `AddStaysAdd` cases exercise the previously-uncovered `ActionAdd` disk-vs-template comparison branch in `ComputeDiffsWithManifest`)
- `internal/cli`: **32.5%** (unchanged vs. Round 4 — no new `internal/cli` tests this round)

### Skipped (unchanged)

`TestBaseFS_WithMockFS` and `TestAvailablePacks_WithMockFS` in `internal/scaffold` — pre-existing placeholder skips, unrelated to this change.

### Round 5 totals

- Total: 171
- Passed: 169
- Failed: 0
- Skipped: 2

### Round 5 verdict

- Pass: yes
- Fail: no
- Blocked: no
- Regressions: none

**Tests remain green after the Codex-4 follow-up fix (`ef8e3ed`). All three new/updated assertions (`AddBecomesConflictWhenDiskDiffers`, `AddStaysAddWhenDiskMatchesTemplate`, and the `OldHash` assertion in `EmptyHashConflictsWhenDiskDiffers`) pass; all prior-round targeted tests are regression-free; `internal/upgrade` coverage improved by +1.1pp. Safe to proceed to `/sync-docs` → `/codex-review` (re-run) → `/pr`.**
