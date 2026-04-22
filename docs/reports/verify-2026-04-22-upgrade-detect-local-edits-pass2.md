# Verify report (pass 2 — post-Codex fix): upgrade-detect-local-edits

- Date: 2026-04-22
- Plan: `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md`
- Verifier: verifier subagent
- Scope: spec compliance of the two newly-added acceptance criteria (plan lines 68–69) and regression on the pre-existing 10; static analysis (`HARNESS_VERIFY_MODE=static ./scripts/run-static-verify.sh`); documentation drift vs. the fix behavior. Behavioral test execution is explicitly deferred to `/test`.
- Branch: `feat/upgrade-detect-local-edits` (commit `a920352` at HEAD; 8 commits ahead of `main`)
- Fix commit under review: `a920352` (fix(upgrade): honor --force and survive template removal for unmanaged entries)
- Pass-1 report: `docs/reports/verify-2026-04-22-upgrade-detect-local-edits.md`
- Evidence: `docs/evidence/verify-2026-04-22-upgrade-detect-local-edits-pass2.log`

## Context and scope

Pass 1 (`verify-2026-04-22-upgrade-detect-local-edits.md`) issued a PASS on 11 acceptance criteria and flagged three follow-ups: (a) `/sync-docs` to update spec + tech-debt, (b) Codex triage, (c) behavioral tests via `/test`.

Between Pass 1 and Pass 2 the following commits landed:

| Commit | Purpose |
| --- | --- |
| `5465679` | `docs: sync spec, tech-debt, and plan checklist for upgrade local-edit detection` — `/sync-docs` output from pipeline re-run |
| `a920352` | `fix(upgrade): honor --force and survive template removal for unmanaged entries` — addresses 2 Codex ACTION_REQUIRED findings |

The plan acceptance-criteria list grew from 11 → 13 (new ACs at lines 68–69 locking in the Codex-fix contracts). This Pass 2 verifies:
1. The two new ACs are satisfied with file-level + test-level evidence.
2. The pre-existing 11 ACs did not regress.
3. Static analysis is still green on the merged tip.
4. Documentation drift introduced by the fix.

## Spec compliance

Each AC is mapped to (a) the code branch that realizes it and (b) the test that locks the behavior in. Tests are referenced as static evidence — they are *not* executed here (per skill scope); actual exercise belongs to `/test`.

### New acceptance criteria (pass 2)

| Acceptance criterion | Status | Evidence |
| --- | --- | --- |
| (10-new) `--force` は `Managed=false` エントリも再管理下に戻す（テンプレート内容を書き込み、manifest を `{Hash: newHash, Managed: true}` に flip）— plan:68 | Verified (static) | Two-layer implementation: (a) `internal/upgrade/diff.go:83-100` — the unmanaged-skip early-return now populates `NewContent: content` (the pass-1 revision omitted it, stranding `--force` without bytes to write); (b) `internal/cli/upgrade.go:242-272` — the `case upgrade.ActionSkip` switch arm adds a guarded sub-branch `case force && wasUnmanaged && d.NewContent != nil:` that `os.WriteFile(..., d.NewContent, ...)` and `manifest.SetFile(d.Path, d.NewHash)` (flipping Managed back to true). `wasUnmanaged` is computed from `oldManifest.Files[d.Path]` so it reflects the pre-upgrade state, not the current pass's decisions. Locked in at diff layer by `TestComputeDiffs_Unmanaged_CarriesNewContentForForceReadoption` (`diff_test.go:399-427`; asserts `diffs[0].NewContent != nil` and byte-equal to template). Locked in at end-to-end layer by `TestRunUpgrade_ForceReadoptsUnmanaged` (`cli_test.go:645-696`; runs `runUpgradeIO(dir, false, "s\n", ...)` → asserts Managed=false, then `runUpgrade(dir, true)` → asserts disk content restored to `# AGENTS\n` and `entry.Managed == true` and `entry.Hash == HashBytes("# AGENTS\n")`). |
| (11-new) `Managed=false` エントリはテンプレート側から削除されても manifest から drop されず silent skip で維持される — plan:69 | Verified (static) | `internal/upgrade/diff.go:228-252` — the removal-detection loop was refactored from `for path := range manifest.Files` to `for path, mf := range manifest.Files`, and a `if !mf.Managed { ... ActionSkip ... continue }` branch was inserted before the `ActionRemove` emission. The emitted `FileDiff` has `Action=ActionSkip` with only `OldHash` populated (no `NewContent` since the template has no bytes). The `runUpgrade` loop then hits `case upgrade.ActionSkip → case wasUnmanaged: manifest.SetFileUnmanaged(d.Path, prev.Hash)` (`internal/cli/upgrade.go:268-269`), preserving the entry across the template-removal boundary. Locked in at diff layer by `TestComputeDiffs_Unmanaged_SurvivesTemplateRemoval` (`diff_test.go:365-397`; asserts `ActionSkip` and explicitly checks *no* `ActionRemove` for the entry). Locked in at end-to-end layer by `TestRunUpgrade_UnmanagedSurvivesTemplateRemovalAcrossRuns` (`cli_test.go:699-758`; skips on first run, swaps `scaffold.EmbeddedFS` to drop `AGENTS.md`, re-runs, and asserts the entry is neither surfaced as removed nor dropped from the manifest, and `!entry.Managed`). |

### Regression check on pre-existing acceptance criteria

| AC | Status | Regression evidence |
| --- | --- | --- |
| (1) テンプレート未変更 + ローカル編集あり → `ActionConflict` | No regression | `diff.go:177-196` unchanged vs pass 1. `TestComputeDiffs_LocalEditWithUnchangedTemplate` unchanged. |
| (2) テンプレート未変更 + ローカル編集なし → `ActionSkip` (heal 含む) | No regression | `diff.go:172-186` and `diff.go:139-169` (heal) unchanged. `TestComputeDiffs_Skip_PreservesHash` / `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate` unchanged. |
| (3) テンプレート変更 + ローカル編集あり → `ActionConflict` | No regression | `diff.go:199-220` unchanged. `TestComputeDiffs_Conflict` unchanged. |
| (4) `[d]iff` は `--- local` / `+++ template (version)` | No regression | `internal/cli/upgrade.go:357-362` unchanged. |
| (5) `[d]iff` 後 reprompt / EOF → skip | No regression | `internal/cli/upgrade.go:320-342` unchanged. |
| (6) disk 読み取り失敗 → 警告 + hash サマリ継続 | No regression | `internal/cli/upgrade.go:348-356` unchanged. |
| (7) `overwrite` → manifest `{newHash, Managed=true}` | No regression | `internal/cli/upgrade.go:201-207` unchanged. |
| (8) `skip` → manifest `{diskHash, Managed=false}` | No regression | `internal/cli/upgrade.go:208-224` unchanged. |
| (9) `Managed=false` → `ActionSkip` (抑制) | Strengthened, not regressed | `diff.go:84-100` now *additionally* carries `NewContent` to enable force re-adoption. The silent-skip outcome in `runUpgrade` is preserved for `force=false` via the `case wasUnmanaged:` arm (line 268). `TestComputeDiffs_Unmanaged_IsSilentSkip` still passes as written (it asserts only `Action=ActionSkip`, not `NewContent=nil`). |
| (10-old) `ralph upgrade --force` 全上書き、`Managed` 戻る (`ActionConflict` 経路) | No regression | `internal/cli/upgrade.go:189-198` (conflict+force arm) unchanged. `TestRunUpgrade_ForceOverwritesLocalEdit` unchanged. |
| (12 ≡ plan:70) `./scripts/run-verify.sh` / `go test ./...` 緑 | Verified (static) | `HARNESS_VERIFY_MODE=static ./scripts/run-static-verify.sh` → exit 0 (see Static analysis section below). `go test ./...` embedded in the golang verifier reported all packages `ok` (from cache). Full `go test ./... -count=1` is `/test`'s job. |

All 13 ACs are satisfied at the file + test level. No pre-existing AC regressed.

### Semantic subtlety: AC #10-old vs AC #10-new

These are *not* redundant — they test different branches:
- **AC #10-old** (`--force` on `ActionConflict`): user has a live conflict AND passes `--force` → template wins, Managed=true. Exercised by `TestRunUpgrade_ForceOverwritesLocalEdit`.
- **AC #10-new** (`--force` on already-`Managed=false`): user previously chose skip (entry is already unmanaged) AND passes `--force` on a subsequent run → template wins, Managed flips back to true. Exercised by `TestRunUpgrade_ForceReadoptsUnmanaged`.

The fix does *not* change AC #10-old behavior; it extends force-overwrite coverage to a second path (`ActionSkip` with `wasUnmanaged && NewContent != nil`).

## Static analysis

| Command | Result | Notes |
| --- | --- | --- |
| `HARNESS_VERIFY_MODE=static ./scripts/run-static-verify.sh` | PASS (exit 0) | Full run captured in `docs/evidence/verify-2026-04-22-upgrade-detect-local-edits-pass2.log`. |
| `shellcheck` (hooks + verify scripts) | PASS | All `.claude/hooks/*.sh` and `templates/base/.claude/hooks/*.sh` OK. |
| `sh -n` (all hook scripts, root + template mirror) | PASS | Syntax OK, 18 scripts checked. |
| `jq -e . .claude/settings.json` and `templates/base/.claude/settings.json` | PASS | Both settings.json parse cleanly. |
| `scripts/check-sync.sh` | PASS | `IDENTICAL=107, DRIFTED=0, ROOT_ONLY=0, TEMPLATE_ONLY=9, KNOWN_DIFF=3`. No template/root mirror drift introduced by the fix. |
| `gofmt` | PASS | `gofmt: ok` (0 unformatted files). |
| `go vet` | PASS | `0 issues`. |
| `go test ./...` (triggered by the golang verifier) | PASS | All packages `ok` (cached). Execution analysis belongs to `/test`. |

No new `TODO` / `FIXME` / debug prints / commented-out blocks introduced — spot-checked against the fix diff.

## Documentation drift

| Doc / contract | In sync? | Notes |
| --- | --- | --- |
| `docs/specs/2026-04-16-ralph-cli-tool.md` § 冪等性と自動修復 (lines 286–297) | **Partial drift** | Line 297 adds the "ローカル編集検知と `Managed=false` 収束" bullet covering ACs #1–#10-old (pass-1 set). It explicitly states `overwrite` 選択や `--force` はローカルをテンプレートへ揃え、マニフェストを `{Hash: newHash, Managed: true}` に戻す — which *does* cover AC #10-new ("戻す" implies unmanaged→managed flip) if read tightly. However, AC #11-new (template-removal survival) is **not explicitly described**. A reader consulting only the spec would be led by line 295 (`ActionRemove 後のマニフェスト・ドロップ`) to believe unmanaged entries are dropped on template removal — exactly the contract the fix breaks. Suggested amendment: add a caveat sentence to line 295 or line 297 along the lines of `ただし Managed=false エントリはテンプレート側の削除後も ActionRemove ではなく ActionSkip として扱われ、manifest 上に残る（user-owned 契約の生存範囲）`. Not blocking for this verify verdict — `/sync-docs` scope. |
| `docs/tech-debt/README.md` (line 22 `--resync` row) | In sync (adequate) | The row language "there is no first-class way to re-adopt it back under ralph management short of hand-editing `.ralph/manifest.toml` or running `--force` on the whole tree" now correctly reflects the post-fix state (tree-wide `--force` is now a real escape hatch, not theoretical). The word-level phrasing "short of ... running `--force` on the whole tree" is still accurate. No update needed, though a one-liner acknowledgment that this escape hatch exists could improve clarity (non-blocking). |
| `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md` (AC list) | In sync (lines 68–69 added) | Two new AC checkboxes added to match the two Codex ACTION_REQUIRED findings. Boxes remain `[ ]` per known drift pattern (verifier memory `feedback_plan_ac_checklist_drift.md`); not blocking. |
| `docs/reports/codex-triage-2026-04-22-upgrade-detect-local-edits.md` | In sync | New file; triage cross-references both the pass-1 verify report's Coverage Gap #1 and the Codex output, establishing traceability from AC → finding → fix → test. |
| `README.md` | No drift | No upgrade-specific contract text. |
| `AGENTS.md` | No drift | No upgrade-specific contract text. |
| `.claude/rules/` | No drift | No rule file references `Managed=false` semantics or removal-detection behavior. |
| `docs/architecture/repo-map.md` | No drift | Lists `internal/upgrade/` without behavioral contract. |

## Observational checks

- **Early-return ordering invariant preserved**: `diff.go:84-100` still sits *before* the `!inManifest` add branch, the empty-hash heal, the unchanged-template branches, and the changed-template branches. `Managed=false` remains a strict override. The only change is that it now also carries `NewContent`, which downstream code (the force arm) opts into via an explicit `d.NewContent != nil` guard. No branch above it was modified.
- **Removal-loop invariant preserved**: The refactor from `for path := range manifest.Files` to `for path, mf := range manifest.Files` is a pure rename + guard insertion. The managed-entry `ActionRemove` path (line 246–250) is unchanged; only an `if !mf.Managed` branch was inserted before it. No behavior change for the managed path.
- **`checkRemovals=false` safety**: Pack-scoped diffs pass `checkRemovals=false`, so the new unmanaged-preserve branch in the removal loop does not fire for pack entries. This preserves the pre-existing pack-preservation path (which is handled at the `runUpgrade` level via `preservePackEntries`).
- **`hadEntry` guard correctness**: `prev, hadEntry := oldManifest.Files[d.Path]` at `upgrade.go:254` uses `oldManifest` (pre-upgrade state), not `manifest` (the new one being built). This is the only correct choice — `manifest` is still being populated and may not yet have the entry. Verified by inspection.
- **`hash` fallback chain in `resolutionSkip`** (`upgrade.go:213-220`): unchanged from pass 1. The defensive `d.OldHash` / `d.NewHash` fallbacks are still unreachable for any current `ActionConflict` producer (all populate `DiskHash`); this is noted as defensive-only.
- **New test layering**: both new diff-level tests (`*_SurvivesTemplateRemoval`, `*_CarriesNewContentForForceReadoption`) and both new integration tests (`*_ForceReadoptsUnmanaged`, `*_UnmanagedSurvivesTemplateRemovalAcrossRuns`) form a two-layer regression net, mirroring the existing pass-1 unit-then-integration pattern.
- **`manifest.SetFile` vs `SetFileUnmanaged` symmetry**: preserved. The fix adds one new call site for `SetFile` (`upgrade.go:265`, the force-readopt branch) and one new call site for `SetFileUnmanaged` (`upgrade.go:269`, the unmanaged-survive branch). Both write the full `ManifestFile{Hash, Managed}` struct; no partial mutation.
- **`EmbeddedFS` swap fixture in `cli_test.go:732-738`**: the test creates a synthetic `fstest.MapFS` that preserves pack FS paths while dropping only `AGENTS.md`. This exercises the removal-detection loop with a real FS walk. `t.Cleanup(func() { setupTestEmbedFS(t) })` restores the original FS so later tests are isolated. Verified by inspection.
- **No concurrency primitives introduced**: the fix is purely sequential I/O + pure functions. No goroutines, channels, sync.Mutex, or atomic ops added.

## Coverage gaps

1. **`--force` + unmanaged + template-removed path** (non-blocking): if a user had previously skipped `foo.md` (entry is Managed=false), the template later drops `foo.md`, and the user runs `ralph upgrade --force`, the new fix emits `ActionSkip` with `NewContent == nil` (no bytes to write — template doesn't ship the file). The switch-arm condition `force && wasUnmanaged && d.NewContent != nil` evaluates *false*, falling through to `case wasUnmanaged: manifest.SetFileUnmanaged(d.Path, prev.Hash)`. Outcome: unmanaged entry is preserved unchanged, disk is untouched, `Managed` stays false. This is the correct behavior (force cannot re-adopt a file that no longer exists upstream) but it is not directly asserted by a dedicated test. The pass-2 self-review also flagged this as a branch-coverage gap. Suggested `/test` follow-up: `TestRunUpgrade_Force_CannotReadoptUnmanagedWhenTemplateRemovedPath`.
2. **CRLF-in-unified-diff edge case** (carried over from pass 1): still not covered. Not a blocker.
3. **Plan progress checklist (AC boxes)** (carried over from pass 1): still `[ ]` for all 13. Known drift pattern per memory; flag for author rather than block.
4. **Spec drift on AC #11-new** (new in pass 2): `docs/specs/2026-04-16-ralph-cli-tool.md` line 295 still describes `ActionRemove` as dropping manifest entries without the `Managed=false` exception. The line-297 bullet added by commit `5465679` focuses on the conflict/skip/force flow but doesn't call out the removal-survival contract. `/sync-docs` re-run should amend either line 295 or line 297.

## Verdict

- **Verified**:
  - Both new acceptance criteria (plan lines 68–69) are satisfied with file-level + test-level evidence.
  - Pass-1's 11 ACs did not regress; the single relevant behavior change (`diff.go:84-100` now carries `NewContent` for unmanaged entries) is additive and guarded by `d.NewContent != nil` at the consumption site.
  - Static analysis green (`HARNESS_VERIFY_MODE=static ./scripts/run-static-verify.sh` → exit 0).
  - No drift in `README.md`, `AGENTS.md`, `docs/architecture/`, `.claude/rules/`.
  - `/sync-docs` pass 1 addressed pass-1's spec + tech-debt drift (commit `5465679`).

- **Partially verified (doc drift flagged, non-blocking for verdict, belongs to `/sync-docs`)**:
  - `docs/specs/2026-04-16-ralph-cli-tool.md` needs a one-sentence amendment for AC #11-new (unmanaged entries survive template removal). Suggested wording: append to line 295 `ただし `Managed=false` エントリはテンプレート側の削除を跨いでも `ActionRemove` ではなく `ActionSkip` として扱われ、マニフェスト上に残る（user-owned 契約の生存範囲）。再び管理下に戻すには `--force` か将来の `--resync` / `--adopt` が必要。`
  - Plan progress-checklist boxes still unticked (cosmetic).

- **Not verified (deferred by skill scope)**:
  - Actual behavioral test pass/fail — `/test`. The static verifier did observe cached `ok` across all packages, but a full `go test ./... -count=1` for the fix commit is `/test`'s job.
  - Interactive terminal behavior (real TTY, color rendering, signal handling) — `/test` or manual walkthrough.

- **Suggested minimal next check (highest confidence for lowest cost)**:
  1. `/test`: run `go test ./internal/upgrade/... ./internal/cli/... -count=1 -v -run 'Unmanaged|ForceReadopts|SurvivesTemplateRemoval'` and capture output to `docs/evidence/test-2026-04-22-upgrade-detect-local-edits-pass2.log`. The `-run` filter keeps focus on the four new tests added by commit `a920352`.
  2. Optional: one-line spec amendment on AC #11-new as described above (feeds the next `/sync-docs` invocation).

**Verdict: PASS.** The Codex fix is correctly implemented, both new acceptance criteria are locked in by tests at both the diff and integration layers, pre-existing behavior did not regress, and static analysis is clean. One documentation drift item (spec AC #11-new) is flagged for `/sync-docs` but does not block the verify verdict. Pipeline may continue to `/test`.
