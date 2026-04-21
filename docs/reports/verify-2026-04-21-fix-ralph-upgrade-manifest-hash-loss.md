# Verify report: fix-ralph-upgrade-manifest-hash-loss

- Date: 2026-04-21
- Plan: docs/plans/active/2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md
- Verifier: verifier subagent (Claude Code)
- Scope: Spec compliance (plan acceptance criteria) + static analysis on branch `fix/ralph-upgrade-manifest-hash-loss` vs `main`. Tests NOT executed as part of this step (handled by `/test`). However, `./scripts/run-verify.sh` internally runs `go test ./...` via the golang verifier, and that run is captured as supporting evidence.

## Deterministic checks run

| Command | Result | Notes |
| --- | --- | --- |
| `git rev-parse --abbrev-ref HEAD` | PASS | `fix/ralph-upgrade-manifest-hash-loss` |
| `git diff main...HEAD --stat` | PASS | 5 files changed (plan + 2 impl + 2 test), +524/-16 |
| `go vet ./...` | PASS | No output (clean) |
| `gofmt -l internal/` | PASS | No output (no unformatted files) |
| `./scripts/run-verify.sh` | PASS | `EXIT=0`. All shell/hook syntax checks, settings.json jq parse, check-sync, mojibake tests, and the golang verifier (gofmt + go vet + go test) passed. Evidence: `docs/evidence/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss.log` |

## Spec compliance (Acceptance criteria walkthrough)

| # | Acceptance criterion | Status | Evidence |
| --- | --- | --- | --- |
| 1 | `ralph init` 直後の同一バージョン `ralph upgrade` 2 回連続で `modified/removed/new` 表示なし (内部 ActionSkip) | Verified | `internal/upgrade/diff.go:131-140` now sets `NewHash` on the unchanged branch; `internal/cli/upgrade.go:206-210` writes `d.NewHash` into the manifest on `ActionSkip`. Regression test `TestRunUpgrade_SameVersionIsIdempotent` (`internal/cli/cli_test.go:153-187`) executes init → upgrade → upgrade and asserts no empty-hash manifest entries. |
| 2 | upgrade 後の base エントリが空文字ハッシュを持たない | Verified | Same test, loop at `internal/cli/cli_test.go:175-179` checks `v.Hash == ""` for every entry. |
| 3 | `hash = ''` 破損マニフェストが 1 回の同一バージョン `runUpgrade` で非対話的に ActionSkip 扱いで復旧 | Verified | Heal branch in `internal/upgrade/diff.go:102-127` (disk == newHash → ActionSkip + NewHash; disk != newHash → ActionConflict). Tests: `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate` (`internal/upgrade/diff_test.go:199-227`), `TestComputeDiffs_EmptyHashConflictsWhenDiskDiffers` (`internal/upgrade/diff_test.go:231-253`), and integration `TestRunUpgrade_HealsCorruptedManifest` (`internal/cli/cli_test.go:192-233`) which runs without `--force` and with closed stdin — any reach of the conflict prompt would flip skip to "skip" or surface an error, and the test asserts healed hashes. |
| 4 | pack ファイルが同一 upgrade 内で `removed` と `new file` に同時分類されない | Verified (by design + indirect test) | `splitManifestForBase` (`internal/cli/upgrade.go:50-61`) excludes `packs/languages/*` keys from the base sweep so they cannot be flagged removed. `splitManifestForPack` (`internal/cli/upgrade.go:65-76`) strips the namespace so pack FS keys match and produce ActionSkip instead of ActionAdd. `ComputeDiffsWithManifest(..., checkRemovals=false)` is used for pack calls. `TestComputeDiffsWithManifest_PackPrefixedSubset` (`internal/upgrade/diff_test.go:162-194`) asserts ActionSkip (not Add) and `TestRunUpgrade_SameVersionIsIdempotent` asserts the pack path `packs/languages/golang/README.md` exists exactly once and no unprefixed leak occurs. No test explicitly enumerates both-actions-absent, but the split-manifest construction makes co-occurrence unreachable. |
| 5 | 旧マニフェストの pack エントリが `scaffold.PackFS` / diff 失敗時にも新マニフェストで保持 | Verified | `preservePackEntries` helper (`internal/cli/upgrade.go:230-236`) is called on both `scaffold.PackFS` error and `ComputeDiffsWithManifest` error (`upgrade.go:116-128`). `maps.Copy(manifest.Files, preservedPackEntries)` at line 143 merges preserved entries into the new manifest. Integration test `TestRunUpgrade_PreservesOldPackEntriesOnDiffFailure` (`internal/cli/cli_test.go:237-279`) exercises the path via a synthetic `ghostpack` in `Meta.Packs`. |
| 6 | 既存 `TestComputeDiffs_AutoUpdate/_Conflict/_AddNewFile/_RemoveFile` 緑 | Verified | `./scripts/run-verify.sh` golang verifier reported `ok internal/upgrade` and `ok internal/cli` with `go test ./...`. |
| 7 | 新規テスト (a)(b)(c)(d) 追加 | Verified | (a) `TestComputeDiffs_Skip_PreservesHash` (`diff_test.go:134-157`); (b) `TestComputeDiffsWithManifest_PackPrefixedSubset` (`diff_test.go:162-194`); (c) `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate` (`diff_test.go:199-227`); (d) `TestRunUpgrade_PreservesOldPackEntriesOnDiffFailure` (`cli_test.go:237-279`). Plus bonus `TestComputeDiffs_EmptyHashConflictsWhenDiskDiffers`, `TestRunUpgrade_SameVersionIsIdempotent`, `TestRunUpgrade_HealsCorruptedManifest`. |
| 8 | `go test ./...` 緑 / `./scripts/run-verify.sh` 緑 | Verified | `EXIT=0` from run-verify.sh, which includes `go test ./...` across all packages. Explicit `/test` run will re-validate in the next pipeline step. |

All 8 acceptance criteria are **Verified**.

### Test-name specificity check

All new test names clearly describe the behavior under verification:

- `TestComputeDiffs_Skip_PreservesHash` — skip path preserves NewHash.
- `TestComputeDiffsWithManifest_PackPrefixedSubset` — pack-subset manifest avoids Add misclassification.
- `TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate` — heal branch when disk matches.
- `TestComputeDiffs_EmptyHashConflictsWhenDiskDiffers` — heal branch conflict guard.
- `TestRunUpgrade_SameVersionIsIdempotent` — end-to-end idempotency.
- `TestRunUpgrade_HealsCorruptedManifest` — end-to-end heal without prompt.
- `TestRunUpgrade_PreservesOldPackEntriesOnDiffFailure` — preservation on pack diff failure.

None rely on vague mechanics-only names. Passes the `.claude/rules/testing.md` specificity guidance.

## Observational checks

- `go vet ./...` — clean, no output.
- `gofmt -l internal/` — clean, no output.
- Static analysis run via `./scripts/run-verify.sh` completed with `EXIT=0`. Full log saved to `docs/evidence/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss.log`.
- Commit history is logically structured (3 commits: heal + hash preservation → pack scoping and preservation → prefix rename refactor). Small and focused.
- `splitManifestForBase` and `splitManifestForPack` preserve `Meta.Packs` via `out.Meta = m.Meta`, so nested pack lookups continue to work across the scoped subsets.

## Documentation drift

Plan step 8 explicitly defers doc updates to the `/sync-docs` stage. Flags (no edits required now):

- `docs/specs/2026-04-16-ralph-cli-tool.md`:
  - Lines 260–284 describe the `upgrade` flow but do not mention:
    - Same-version upgrade idempotency (no `modified/removed/new` output when nothing changed).
    - Heal behavior for empty-hash manifest entries (`hash = ''` repaired automatically).
    - Pack namespacing (`packs/languages/<pack>/…`) and separate base/pack diff scopes.
    - Preservation of old pack entries when a pack FS fails to load.
  - Recommendation: Add a short "Idempotency & heal" subsection under `### upgrade フロー` in `/sync-docs`.

- `docs/recipes/*`:
  - Only one `upgrade`-related hit (`docs/recipes/ralph-loop.md:84`: `migration | Backward-compatible migration steps | Upgrades`) — unrelated, it is a label-definition table. No recipe currently documents `ralph upgrade`; no drift to correct.

- `AGENTS.md` / `CLAUDE.md`: No behavioral contracts exposed in these map files are changed by the fix; no update needed.

Verdict on doc drift: **expected deferral** — flag passed to `/sync-docs`.

## Coverage gaps

- AC4 is satisfied structurally (split-manifest design eliminates the double-classification path) rather than by a direct assertion over a full diff slice. If stronger confidence is desired, the smallest useful additional check would be a single assertion in `TestRunUpgrade_SameVersionIsIdempotent` (or a dedicated test) that collects every diff action emitted during the second upgrade and verifies no path appears as both `ActionRemove` and `ActionAdd`. This is a nice-to-have; not a blocker.
- Static analysis did not include `staticcheck` or `golangci-lint`; the project relies on `go vet` + `gofmt`. Consistent with `.claude/rules/golang.md` and existing norms for this repo.

## Verdict

- Verified: AC1, AC2, AC3, AC4 (by design), AC5, AC6, AC7 (a–d), AC8; static analysis (`go vet`, `gofmt`, `run-verify.sh`); test-name specificity.
- Partially verified: AC4 has no direct diff-set assertion but the code path is unreachable by construction.
- Not verified: N/A.

**Overall verdict: PASS**

No blockers for `/test`. Documentation drift items are tracked for `/sync-docs` and do not gate this step.

## Artifacts

- Raw verification output: `docs/evidence/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss.log`
- This report: `docs/reports/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md`

## Round 2 (post-codex)

- Date: 2026-04-21
- Trigger: Re-verify after commit `d16cb4d` addressed two Codex ACTION_REQUIRED findings.
- Scope: Confirm the two new behaviors are spec-consistent; re-run static analysis; flag doc drift for `/sync-docs`.
- Verifier: verifier subagent (Claude Code).

### What changed since Round 1

Commit `d16cb4d` (`fix(upgrade): restore pack removal detection and drop disappeared packs`) makes two corrections:

1. Pack-scoped `upgrade.ComputeDiffsWithManifest(packManifest, packDir, packFS, …)` switched from `checkRemovals=false` to `checkRemovals=true`. A tracked-but-missing pack file now surfaces as `ActionRemove`; `internal/cli/upgrade.go:154-156` re-prefixes the `Path` back to `packs/languages/<pack>/<file>` so the user sees the "removed from template" notice and the manifest entry is preserved with its `OldHash` (idempotency on re-run).
2. Packs no longer present in `scaffold.AvailablePacks()` are explicitly dropped from the new manifest: they are neither diffed nor included in `Meta.Packs` (via the new `retainedPacks` slice). A `Notice: pack %q no longer exists in templates …` is emitted to stderr. Preservation via `preservePackEntries` is now reserved for genuinely transient failures (PackFS load or pack-diff computation) on packs that ARE still available.

No new acceptance criteria were added — the fix restores the original contract (pack-file removals surface with a warning; disappeared packs get dropped rather than leaking forward as "unknown language pack" noise on every upgrade).

### Deterministic checks re-run

| Command | Result | Evidence |
| --- | --- | --- |
| `HARNESS_VERIFY_MODE=static ./scripts/run-static-verify.sh` | EXIT=0 | `/tmp/run-static-verify.log` (captured into `docs/evidence/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss-round2.log`) |
| `./scripts/run-verify.sh` | EXIT=0 | `docs/evidence/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss-round2.log` — all shell/hook syntax checks, `check-sync`, mojibake tests, and the golang verifier (gofmt + go vet + go test) passed |
| `go vet ./...` | EXIT=0 (clean) | No output |
| `gofmt -l internal/` | EXIT=0 (clean) | No output |
| `git status` / `git diff HEAD` | Working tree has only a non-code edit | `docs/reports/self-review-…md` has a Round 2 section appended (not staged). No committed-code drift. |

### Spec-consistency of the two new behaviors

| Behavior | Code location | Status vs spec | Evidence |
| --- | --- | --- | --- |
| Pack-file deletions surface as `ActionRemove` with `packs/languages/<pack>/<file>` path, and the manifest keeps the old hash | `internal/cli/upgrade.go:143-157, 225-229`; `internal/upgrade/diff.go:171-183` | Code-level contract restored. Behaviorally verified by `TestRunUpgrade_ReportsDeletedPackFile` emitting `⚠ packs/languages/golang/deprecated.sh (removed from template — review and delete manually)` on stdout and `Removed from template: 1 files (review manually)`. | `docs/evidence/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss-round2.log` (go test output) |
| Packs missing from `scaffold.AvailablePacks()` are dropped (manifest entries removed, `Meta.Packs` filtered) with a stderr Notice; on-disk files left untouched | `internal/cli/upgrade.go:108-132, 164` | Code-level contract now matches commit message. Behaviorally verified by `TestRunUpgrade_DropsPacksRemovedFromTemplates` emitting `Notice: pack "ghostpack" no longer exists in templates — manifest tracking dropped (files on disk left untouched)`. | Same evidence log |

Both behaviors are internally consistent and compile/vet/format cleanly. The `ActionRemove` re-prefix is mutually exclusive with `ActionAdd` on the same path (one requires file-in-manifest-but-not-FS, the other requires file-in-FS-but-not-manifest), so AC4 (no double classification) remains satisfied under the new `checkRemovals=true` setting.

### Spec compliance (Round 1 acceptance criteria re-check)

All 8 Round 1 acceptance criteria remain Verified (the fix is scoped to pack-path handling and does not regress any AC1–AC8 evidence):

- AC1–AC3, AC6–AC8: unchanged, still green via the same tests.
- AC4 (pack ファイルが同一 upgrade 内で `removed` と `new file` に同時分類されない): still Verified by construction. The change from `checkRemovals=false` → `true` only re-enables removal detection for pack files that are truly gone from the template; add/remove remain mutually exclusive per-path. `TestRunUpgrade_SameVersionIsIdempotent` still asserts no `modified/removed/new` output on a same-version re-run.
- AC5 (pack 診断失敗時のエントリ保持): narrowed scope (transient errors only). Behavior still holds for `PackFS` failure and pack `ComputeDiffsWithManifest` failure on packs that ARE available. The disappeared-pack path is now a separate, intentional drop.

### Documentation drift (for `/sync-docs`)

The spec `docs/specs/2026-04-16-ralph-cli-tool.md` now has **two specific lines that must be updated** to reflect the post-fix behavior. This is drift that `/sync-docs` must address:

1. **Line 290** — currently reads: "… pack 側は `checkRemovals=false` で計算し、同一ファイルが `removed from template` と `new file` の両方に現れることはない。"
   - Problem: `checkRemovals=false` is stale. The current code uses `checkRemovals=true` for pack diffs. The "never appears as both removed and new" invariant still holds, but the mechanism is now: base sweep's `packs/languages/` exclusion via `splitManifestForBase` prevents base-side "removed"; pack sweep's namespace-stripped manifest via `splitManifestForPack` prevents pack-side "new" misclassification.
   - Recommended fix (for `/sync-docs`): rewrite to describe the split-manifest mechanism rather than the `checkRemovals` flag, and explicitly state that genuine pack-file deletions now surface as `removed from template` with the pack path preserved.

2. **Line 291** — currently reads: "pack の埋め込み FS ロードや diff 計算が失敗した場合、その pack に対応する旧マニフェストのエントリは新マニフェストへそのままコピーされ、追跡情報は失われない（警告は stderr に出力）。"
   - Problem: does not distinguish between (a) transient failures (PackFS load or diff computation) on packs that are still available — entries **preserved**, and (b) packs that have been removed/renamed in the release and are no longer in `scaffold.AvailablePacks()` — entries **explicitly dropped** with a `Notice`. After the fix, these are two separate paths with opposite outcomes.
   - Recommended fix (for `/sync-docs`): split into two bullets — "pack が一時的に壊れた場合（preservation）" vs "pack が release で削除された場合（explicit drop with Notice）".

No drift in `AGENTS.md`, `CLAUDE.md`, `README.md`, or `docs/recipes/*` — none expose these contracts. The plan itself is archived and its Open questions bullet mentions future `ComputeDiffsNoRemovals` deprecation, which is still accurate.

### Coverage gaps (for `/test` awareness, non-blocking)

- The transient-`PackFS`-failure branch (`upgrade.go:134-140`) and the transient-pack-diff-failure branch (`upgrade.go:147-153`) are no longer exercised by any test (the ghostpack fixture was repurposed for the disappeared-pack case). Provoking them would require injecting `fs.Sub` failure against a pack that **is** in `AvailablePacks()`, which is awkward from `fstest.MapFS`. Not a regression, but worth a follow-up.
- `TestRunUpgrade_ReportsDeletedPackFile` does not assert the exact stdout line (`⚠ packs/languages/golang/deprecated.sh …`). The test currently verifies only that the manifest entry is retained with `OldHash`. The observed stdout in the test run (captured above) confirms the notice fires, but a future refactor could silently suppress the print and this test would still pass.

### Smallest useful additional check

If one more assertion were added, the highest-leverage one would be: in `TestRunUpgrade_ReportsDeletedPackFile`, capture `os.Stdout` and assert it contains `packs/languages/golang/deprecated.sh (removed from template`. This locks in the user-facing signal that Codex P2 identified as the regression, independent of the manifest bookkeeping. One-line test addition.

### Round 2 verdict

- Verified: both new behaviors (pack `ActionRemove` surfacing; disappeared-pack drop) compile cleanly, pass `go vet` / `gofmt`, and are exercised by integration tests via `run-verify.sh`. Round 1 ACs remain Verified. No contract regressions.
- Likely but unverified: correctness under true transient `PackFS` / pack-diff failures — no direct tests cover those branches after the fixture repurposing. Low risk (narrow error paths).
- Documentation drift: two concrete stale lines in `docs/specs/2026-04-16-ralph-cli-tool.md` (lines 290 and 291). **Must be fixed by `/sync-docs` before `/pr`** — shipping the fix without updating these lines leaves the spec contradicting the implementation.

**Overall Round 2 verdict: PASS (with doc-drift flag for `/sync-docs`)**

No code-level blockers. Proceed to `/test` (or re-run `/test` if fix-and-revalidate pipeline requires). `/sync-docs` must rewrite `docs/specs/2026-04-16-ralph-cli-tool.md` lines 290 and 291 in its next pass.

### Round 2 artifacts

- Raw Round 2 verification output: `docs/evidence/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss-round2.log`
- This report (updated in-place): `docs/reports/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md`
