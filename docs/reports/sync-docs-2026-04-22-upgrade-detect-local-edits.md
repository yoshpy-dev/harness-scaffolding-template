# Sync-docs report: upgrade-detect-local-edits

- Date: 2026-04-22
- Plan: `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md`
- Branch: `feat/upgrade-detect-local-edits`
- Maintainer: `doc-maintainer` subagent (Claude Code)
- Upstream triggers:
  - Pass 1: documentation drift flagged in `docs/reports/verify-2026-04-22-upgrade-detect-local-edits.md` §Documentation drift.
  - Pass 2: additional drift items flagged in `docs/reports/verify-2026-04-22-upgrade-detect-local-edits-pass2.md` §Documentation drift, following Codex-driven fix `a920352` (`fix(upgrade): honor --force and survive template removal for unmanaged entries`) which added two new acceptance criteria (plan lines 68-69).

## Scope

Align product documentation with the implemented behavior of `ralph upgrade` for:
- local-edit detection on unchanged templates (`newHash == manifestHash` but `diskHash != manifestHash` → `ActionConflict`)
- `Managed=false` user-owned convergence semantics (silent skip after user `[s]kip`)
- `--force` re-adoption of `Managed=false` entries (pass-2 contract)
- `Managed=false` survival across template-side file removal (pass-2 contract)
- unified diff display with `--- local` / `+++ template (version)` direction
- prompt storm avoidance and disk-read-failure fallback

No implementation or test files were touched in either pass.

## Files updated

### Pass 1 (commit `5465679`)

| File | Change | Reason |
| --- | --- | --- |
| `docs/specs/2026-04-16-ralph-cli-tool.md` (§ 冪等性と自動修復) | Appended new bullet at line 297: "ローカル編集検知と `Managed=false` 収束 (local-edit detection & user-owned convergence)" covering the 11 pass-1 acceptance criteria. | Spec previously described only `ActionConflict` at a high level ("コンフリクト時はファイルごとに上書き/スキップ/diff 表示を選択可能", line 29) and did not mention the new detection branch, the `Managed=false` convergence contract, the unified-diff direction, or the prompt-storm avoidance. |
| `docs/tech-debt/README.md` | Appended new row for `ralph upgrade --resync <path>` / `--adopt` escape hatch. | Self-review identified this as a deferred escape hatch to re-adopt unmanaged entries; needed persistent tracking outside chat. |
| `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md` | Flipped Review / Verification / Test artifact boxes in Progress checklist. | Bring plan progress in line with artifacts already on disk. |

### Pass 2 (this round, post-`a920352`)

| File | Change | Reason |
| --- | --- | --- |
| `docs/specs/2026-04-16-ralph-cli-tool.md` (line 295, `ActionRemove` bullet) | Appended caveat: `Managed=false` entries are excluded from the `ActionRemove → drop-from-manifest` contract — template-side deletion produces `ActionSkip` (not `ActionRemove`), and the manifest entry is preserved across the template-removal boundary. | Commit `a920352` refactored the removal-detection loop (`internal/upgrade/diff.go:228-252`) to insert an `if !mf.Managed` guard before the `ActionRemove` emission, directly contradicting the pre-existing spec wording. Without the caveat, a future reader reconstructing the contract from spec alone would expect `Managed=false` entries to be dropped. Locked in by `TestComputeDiffs_Unmanaged_SurvivesTemplateRemoval` (`diff_test.go:365`) and `TestRunUpgrade_UnmanagedSurvivesTemplateRemovalAcrossRuns` (`cli_test.go:699`). |
| `docs/specs/2026-04-16-ralph-cli-tool.md` (line 297, Managed=false convergence bullet) | Strengthened wording to (a) distinguish `overwrite` (ActionConflict path only) from `--force` (both ActionConflict and already-`Managed=false` paths), (b) explicitly document `--force` re-adoption flipping `Managed=false` back to `{Hash: newHash, Managed: true}` (plan AC line 68), (c) note the template-removal exception where `--force` cannot re-adopt and user-owned contract survives (plan AC line 69), (d) clarify that `--resync <path>` is specifically a *per-path* escape hatch since tree-wide re-adoption already exists via `--force`. | Pass-1 wording conflated `overwrite` and `--force` (both listed as "ローカルをテンプレートへ揃え、マニフェストを {Hash: newHash, Managed: true} に戻す") and did not cover the `Managed=false` + `--force` or `Managed=false` + template-removed paths that are now first-class contracts. Locked in by `TestComputeDiffs_Unmanaged_CarriesNewContentForForceReadoption` (`diff_test.go:399`) and `TestRunUpgrade_ForceReadoptsUnmanaged` (`cli_test.go:645`). |
| `docs/tech-debt/README.md` (`--resync` row) | Rewrote the debt row. Renamed label to "per-path escape hatch" to match scope. Updated wording to acknowledge tree-wide re-adoption via `--force` is first-class and cross-link to the spec section. Updated trigger-to-pay-down to cite the `--force` blast radius as the motivation. | Pass-1 row said "there is no first-class way to re-adopt ... short of ... running `--force` on the whole tree", which read as if `--force` was a hypothetical workaround. Post-`a920352`, `--force` on the whole tree is a real, tested escape hatch. The remaining debt is narrower: the lack of *per-path* granularity. |
| `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md` (AC list, lines 58-70) | Flipped all 13 acceptance-criteria boxes from `[ ]` to `[x]`. | All 13 criteria are locked in by tests that PASS in pass 2 (see `docs/reports/test-2026-04-22-upgrade-detect-local-edits-pass2.md`). `go test ./... -count=1` and `HARNESS_VERIFY_MODE=static ./scripts/run-static-verify.sh` both green on commit `a920352`. Per verifier memory, stale AC boxes are a known drift pattern — correcting here. |
| `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md` (Progress checklist) | Appended pass-2 artifact references to the Review / Verification / Test lines (`…-pass2.md`). Added new "Sync-docs artifact created" line linking to this report. | Keep progress checklist current per `.claude/rules/planning.md`. |

## Intentionally left alone

| Area | Why not changed |
| --- | --- |
| `AGENTS.md` | Repo map still describes `internal/upgrade/` as "hash-based diff engine, conflict resolution (auto-update, conflict, add, remove)". The new force-readopt path stays under "conflict" semantics; the template-removal-survives-for-unmanaged path is a refinement of "remove", not a new top-level action. Keeping this map file short per `.claude/rules/documentation.md`. |
| `CLAUDE.md` | No default-behavior or contract-level change. |
| `README.md` | Upgrade command is referenced only as a cobra subcommand in the package overview; no user-facing command surface or flag changed. |
| `docs/recipes/*` | Grep confirmed no recipe documents `ralph upgrade` conflict UI or `Managed=false` semantics. |
| `docs/architecture/repo-map.md` | Lists `internal/upgrade/` without behavioral contract. |
| `.claude/rules/*` | No rule file references `ralph upgrade` conflict flow, `Managed` field semantics, or `--force` escape-hatch behavior. |
| `docs/quality/*` | DoD / quality gates unchanged — the change adds no new gate. |
| Implementation and test files | Explicitly out of scope for `/sync-docs`. |

## Cross-reference checks performed

- `grep -l "ralph upgrade" docs/**/*` — only archived plans, the active plan, `docs/specs/2026-04-16-ralph-cli-tool.md`, tech-debt, and this branch's reports referenced the command. Archived plans are frozen by convention; no edits.
- `grep -l "Managed" .claude/rules/ docs/recipes/ README.md AGENTS.md CLAUDE.md` — no matches outside of the spec section and tech-debt. No drift.
- `grep -l "\-\-force" .claude/rules/ docs/recipes/` — no matches. No drift.
- `scripts/check-sync.sh` (pass 2 verify log) — `IDENTICAL=107, DRIFTED=0, ROOT_ONLY=0, TEMPLATE_ONLY=9, KNOWN_DIFF=3`. No template/root mirror drift.
- Spec cross-reference consistency: the new line-295 caveat ("下記 user-owned 収束の契約を参照") forward-references line 297, and the line-297 bullet back-references `docs/tech-debt/README.md` for the per-path escape-hatch deferral. The tech-debt row now forward-references the spec section for the `--force` tree-wide escape hatch. Reader can traverse either direction.

## Evidence

- Pass 1 sync-docs log: `docs/evidence/sync-docs-2026-04-22-upgrade-detect-local-edits.log`
- Pass 2 sync-docs log: `docs/evidence/sync-docs-2026-04-22-upgrade-detect-local-edits-pass2.log`
- Pass 1 verify drift recommendation: `docs/reports/verify-2026-04-22-upgrade-detect-local-edits.md` §Documentation drift
- Pass 2 verify drift recommendation: `docs/reports/verify-2026-04-22-upgrade-detect-local-edits-pass2.md` §Documentation drift (Partial drift on spec line 295/297)
- Implementation anchors cited in the new spec wording:
  - `internal/upgrade/diff.go:84-100` — unmanaged-skip early-return now carries `NewContent` for force re-adoption
  - `internal/upgrade/diff.go:228-252` — removal-detection loop skips unmanaged entries instead of emitting `ActionRemove`
  - `internal/cli/upgrade.go:242-272` — `ActionSkip` switch arm routes force+unmanaged+has-template to `os.WriteFile` + `SetFile`, otherwise preserves via `SetFileUnmanaged`
- Test anchors for AC coverage:
  - `internal/upgrade/diff_test.go:365` — `TestComputeDiffs_Unmanaged_SurvivesTemplateRemoval`
  - `internal/upgrade/diff_test.go:399` — `TestComputeDiffs_Unmanaged_CarriesNewContentForForceReadoption`
  - `internal/cli/cli_test.go:645` — `TestRunUpgrade_ForceReadoptsUnmanaged`
  - `internal/cli/cli_test.go:699` — `TestRunUpgrade_UnmanagedSurvivesTemplateRemovalAcrossRuns`

## Verdict

Documentation now matches implementation for all 13 acceptance criteria (pass-1 set of 11 plus pass-2 additions at plan lines 68-69). Spec, tech-debt, and plan are aligned with commit `a920352`. No further doc drift detected outside the spec. Ready for `/codex-review` (pass 2) and `/pr`.
