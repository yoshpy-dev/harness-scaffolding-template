# Sync-docs report: fix-ralph-upgrade-manifest-hash-loss

- Date: 2026-04-21
- Plan: `docs/plans/active/2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md`
- Branch: `fix/ralph-upgrade-manifest-hash-loss`
- Maintainer: `doc-maintainer` subagent (Claude Code)
- Upstream trigger: Documentation drift flagged in `docs/reports/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md` (lines 56–72).

## Scope

Align product documentation with the implemented behavior of `ralph upgrade` idempotency, empty-hash heal, pack manifest namespacing, and pack diff-failure entry preservation. No implementation or test files were touched.

## Files updated

| File | Change | Reason |
| --- | --- | --- |
| `docs/specs/2026-04-16-ralph-cli-tool.md` | Added `#### 冪等性と自動修復 (idempotency & heal)` subsection under `### upgrade フロー` (after line 284, before `## セキュリティ考慮事項`). | Spec section described only the interactive diff UI output; it did not mention same-version idempotency (`ActionSkip` now carries `NewHash`), empty-hash self-heal (`hash = ''` repaired when disk matches template; conflict otherwise), pack namespacing (`packs/languages/<pack>/<rel>` keys with separate base/pack diff scopes), or pack-entry preservation on diff failure. All four items are behaviors implemented on this branch (see `internal/upgrade/diff.go` heal branch + skip-NewHash branch, and `internal/cli/upgrade.go` `splitManifestForBase`, `splitManifestForPack`, `preservePackEntries`). |
| `docs/plans/active/2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md` | Flipped Progress checklist items: Review / Verification / Test / Sync-docs artifact boxes now checked. | Brings plan progress in line with artifacts already on disk (`docs/reports/self-review-…md`, `verify-…md`, `test-…md`, and this report). |

## Intentionally left alone

| Area | Why not changed |
| --- | --- |
| `AGENTS.md` | The fix is a bug fix inside the `upgrade` command; it does not change any contract surfaced in the repo map (no new file/module, no new skill, no renamed script). Keeping this map file short per `.claude/rules/documentation.md`. |
| `CLAUDE.md` | No default-behavior or contract-level change. |
| `README.md` | Upgrade command is referenced only as a cobra subcommand in the package overview (line 45–47); no user-facing command surface or flag changed. |
| `docs/recipes/*` | Grep confirmed no recipe documents `ralph upgrade` behavior (only a passing `migration | Upgrades` label reference in `docs/recipes/ralph-loop.md:84`, which is unrelated). Nothing to resync. |
| `.claude/rules/*` | No rule references `ralph upgrade` idempotency or manifest heal semantics. |
| `docs/quality/*` | DoD / quality gates unchanged — the fix adds no new gate. |
| Implementation and test files | Explicitly out of scope for `/sync-docs`. |

## Additional drift checks performed

- `grep -l "ralph upgrade" docs/**/*` — only archived plans, active plan itself, and this branch's reports referenced the command. Archived plans are frozen by convention; no edits.
- `grep "upgrade" README.md` — two hits, both in the `internal/cli/` / `internal/upgrade/` repo-map enumeration. Still accurate.
- `AGENTS.md` repo map — `internal/upgrade/` description ("hash-based diff engine, conflict resolution (auto-update, conflict, add, remove)") still correctly describes the public-facing action set; the new "skip-with-NewHash" and "heal" behaviors are refinements within existing actions and do not require map-level expansion.

## Evidence

- Verify report drift recommendation: `docs/reports/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md` §Documentation drift (lines 56–72).
- Implementation anchors cited in the new subsection:
  - `internal/upgrade/diff.go` — skip-with-`NewHash` branch and empty-hash heal branch.
  - `internal/cli/upgrade.go` — `splitManifestForBase`, `splitManifestForPack`, `preservePackEntries`, and the `maps.Copy` merge of preserved pack entries into the new manifest.

## Verdict

Documentation now matches implementation for the four behaviors flagged by `/verify`. No further doc drift detected outside the spec. Ready for `/codex-review` and `/pr`.

## Round 2 (post-codex)

- Date: 2026-04-21
- Trigger: Verify Round 2 report (`docs/reports/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md` §"Documentation drift (for `/sync-docs`)", lines 137–148) flagged two stale lines in `docs/specs/2026-04-16-ralph-cli-tool.md` after commit `d16cb4d` (`fix(upgrade): restore pack removal detection and drop disappeared packs`).

### Files updated

| File | Change | Reason |
| --- | --- | --- |
| `docs/specs/2026-04-16-ralph-cli-tool.md` (line 290, "pack の名前空間化" bullet) | Replaced the "pack 側は `checkRemovals=false` で計算し、…" sentence with a description of the split-manifest mechanism (`splitManifestForBase` / `splitManifestForPack`) and added an explicit statement that pack-scope removal detection stays enabled, so genuine pack-file deletions surface as `removed from template` with the `packs/languages/<pack>/<rel>` path preserved. | Implementation now uses `checkRemovals=true` on the pack scope (`internal/cli/upgrade.go:143-147`). The no-double-classification invariant still holds, but via manifest splitting (base excludes `packs/languages/`, pack scope only sees that pack's entries), not via disabling removal detection. |
| `docs/specs/2026-04-16-ralph-cli-tool.md` (line 291, pack-diff-failure bullet) | Split the single bullet into two sub-bullets under a new heading "pack の一時的失敗時のエントリ保持 vs release 削除時の明示的ドロップ": (a) transient PackFS / diff-compute failures on packs still in `scaffold.AvailablePacks()` → preservation with Warning; (b) packs removed from the release (not in `AvailablePacks()`) → explicit drop with Notice, `Meta.Packs` filtered, on-disk files untouched. | Commit `d16cb4d` introduced two opposite-outcome code paths: `preservePackEntries` (transient) vs the `!available[pack]` continue-with-Notice branch (`internal/cli/upgrade.go:129-132, 164`). The old wording conflated them under "preserve entries," which now contradicts implementation for the disappeared-pack case. |

### Scope discipline

- Only the two lines flagged by Verify Round 2 were rewritten. Surrounding bullets (same-version idempotency, empty-hash heal) were not touched — they remain accurate and in scope.
- No implementation or test files modified.
- `AGENTS.md` / `CLAUDE.md` untouched: the fix is still contained within the `upgrade` command, no repo-map-level surface changed. `internal/upgrade/` description ("hash-based diff engine, conflict resolution (auto-update, conflict, add, remove)") remains accurate — the new "disappeared-pack drop" is a Notice-level operator signal, not a new public action on the diff engine.
- `README.md`, `docs/recipes/*`, `.claude/rules/*`, `docs/quality/*` re-checked: none reference pack-diff failure semantics or the `checkRemovals` flag, so no ripple edits needed.

### Evidence

- Verify Round 2 findings: `docs/reports/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md` lines 137–148.
- Implementation anchors for the new spec wording:
  - `internal/cli/upgrade.go:47-70` — `splitManifestForBase` / `splitManifestForPack` namespacing.
  - `internal/cli/upgrade.go:102-103, 142-147` — base (`checkRemovals=true`) and pack (`checkRemovals=true`) diff scopes.
  - `internal/cli/upgrade.go:124-140, 150, 164` — transient-failure preservation vs disappeared-pack drop + `retainedPacks` filter on `Meta.Packs`.
  - `internal/cli/upgrade.go:129-131` — exact `Notice: pack %q no longer exists in templates — manifest tracking dropped (files on disk left untouched)` string quoted in the spec.

### Round 2 verdict

Spec lines 290–291 now match the post-`d16cb4d` implementation. No remaining doc drift identified by Verify Round 2. Ready for re-run of `/codex-review` and `/pr`.
