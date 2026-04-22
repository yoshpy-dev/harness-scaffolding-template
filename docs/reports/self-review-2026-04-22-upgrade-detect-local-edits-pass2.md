# Self-review report: upgrade-detect-local-edits (pass 2 — post-Codex fix)

- Date: 2026-04-22
- Plan: `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md`
- Reviewer: Claude Code (reviewer subagent)
- Scope: diff quality of commit `a920352` (fix(upgrade): honor --force and survive template removal for unmanaged entries) on branch `feat/upgrade-detect-local-edits` vs `origin/main`. Pass 1 already covered the earlier commits; this pass focuses on the incremental fix that addresses 2 Codex ACTION_REQUIRED findings.

## Evidence reviewed

- Commit under review: `a920352` (6 files changed, +274/−17)
  - `internal/upgrade/diff.go` (+24/−12)
  - `internal/cli/upgrade.go` (+28/−6)
  - `internal/upgrade/diff_test.go` (+66)
  - `internal/cli/cli_test.go` (+114)
  - `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md` (+2)
  - `docs/reports/codex-triage-2026-04-22-upgrade-detect-local-edits.md` (+39, new)
- Full-branch diff `origin/main...feat/upgrade-detect-local-edits`: 14 files, +1668/−87 (context only; pass 1 covered this)
- Plan: `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md` (acceptance criteria #10 and #11 added in this pass)
- Codex triage: `docs/reports/codex-triage-2026-04-22-upgrade-detect-local-edits.md` (2 ACTION_REQUIRED; both addressed by a920352)
- Pass 1 self-review: `docs/reports/self-review-2026-04-22-upgrade-detect-local-edits.md`

## Findings

| Severity | Area | Finding | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| LOW | maintainability | The `ActionSkip` force-readopt branch increments `updated` but never updates `skipped`. Consistent with the existing pattern for managed silent-skip entries (they also don't increment any counter), but this is the first time an `ActionSkip` diff *writes to disk*, which makes the silence slightly more surprising. The end-of-run summary line `Skipped: %d files (user-modified)` will no longer include re-adopted entries — that's actually correct (they were re-adopted, not skipped) but the asymmetry is worth calling out. | `internal/cli/upgrade.go:256-272` | Either (a) add a short comment that updated/skipped/notified intentionally don't cover every ActionSkip variant, or (b) leave as-is and track this as known gap. Not blocking. |
| LOW | readability | The comment block at `internal/cli/upgrade.go:242-253` documents three sub-cases (unmanaged+force+has-template, unmanaged+no-template, managed/heal) but the `switch` arms cover them via a guarded `force && wasUnmanaged && d.NewContent != nil` predicate. A reader has to mentally zip the comment bullets to the `case` conditions. Minor. | `internal/cli/upgrade.go:242-272` | Consider inlining one-line comments directly above each `case` arm to mirror the three bullets. Style, not correctness. |
| LOW | maintainability | The force-readopt path bypasses the conflict-resolution prompt entirely even when the disk content diverges significantly from the unmanaged baseline. This is the documented `--force` contract ("overwrite all files without prompting"), so it's intentional — but it means a user who had custom work in `AGENTS.md` loses it silently to a single `--force` invocation with no intermediate warning. Pass 1 already covered similar behavior for managed conflicts; this just extends it. | `internal/cli/upgrade.go:257-267` | No change. Intentional by spec. Consider surfacing in release notes so users understand `--force` now re-adopts previously-skipped files too. (This is already noted in the spec diff at commit `5465679`.) |
| LOW | testability | `TestRunUpgrade_UnmanagedSurvivesTemplateRemovalAcrossRuns` uses `strings.Contains(out.String(), "AGENTS.md") && strings.Contains(out.String(), "removed from template")` as the negative-assert. If the output message wording drifts (e.g. "gone upstream", "no longer in template"), the test would falsely pass. The authoritative manifest-state check below (`m.Files["AGENTS.md"]` + `!entry.Managed`) does guard the invariant, so this is redundancy-in-case-of-wording-drift rather than a correctness gap. | `internal/cli/cli_test.go:758-760` | Replace the string-match with a direct check that `ActionRemove` didn't fire, or pin the exact message constant. Non-blocking. |
| LOW | test-coverage-shape | `TestRunUpgrade_UnmanagedSurvivesTemplateRemovalAcrossRuns` only exercises `force=false`. The new ActionSkip branch for `force && wasUnmanaged && d.NewContent == nil` (template removed the path, user ran `--force`) is not directly asserted. The code path is trivially correct (falls through to `case wasUnmanaged:`), but a one-liner test would nail it down. | `internal/cli/cli_test.go:734` (`runUpgradeIO(dir, false, ...)`) | Not blocking (the condition is exercised indirectly by the no-force test since the fall-through arm is the same code). Add only if the team wants exhaustive branch coverage. |

No CRITICAL, HIGH, or MEDIUM findings.

### Items explicitly checked and cleared

- **Unnecessary changes** — none. Every hunk in `a920352` maps directly to one of the two Codex findings.
- **Naming** — `wasUnmanaged`, `hadEntry`, `preservedPackEntries` are grep-able and consistent with the surrounding package vocabulary. `SetFileUnmanaged` is already used elsewhere in the file.
- **Typos** — none found in code, comments, or test names.
- **Null safety** — `d.NewContent != nil` guard is explicit at `internal/cli/upgrade.go:257`. `hadEntry` guard at line 254 prevents nil-map-miss from promoting a non-unmanaged entry into the force-readopt arm.
- **Debug code** — no stray `println`, `fmt.Printf`, `TODO`, or commented-out blocks introduced.
- **Secrets** — none. No env-var reads, no credentials, no URLs.
- **Exception handling** — the `os.MkdirAll` / `os.WriteFile` errors in the force-readopt arm are wrapped with context (`"creating parent dir for %s: %w"`, `"writing %s: %w"`) — same style as the sibling `ActionAutoUpdate` / `ActionAdd` branches. No swallowed errors.
- **Security** — `filepath.Join(absDir, d.Path)` is the same pattern used throughout the file. `d.Path` comes from `fs.WalkDir` over `embed.FS`, which rejects `..` segments at the embed layer, so no new path-traversal risk is introduced. `scaffold.FilePerm(d.Path)` preserves existing permission policy.
- **Exception handling on removed-unmanaged branch** — the ActionSkip case for template-removed unmanaged entries hits `case wasUnmanaged:` and calls `SetFileUnmanaged(d.Path, prev.Hash)`. `prev` is guaranteed non-zero here because `hadEntry=true`. No nil deref.
- **Coverage-gap-turned-contract** — `TestComputeDiffs_Unmanaged_SurvivesTemplateRemoval` and `TestComputeDiffs_Unmanaged_CarriesNewContentForForceReadoption` assert the two new invariants at the diff layer; `TestRunUpgrade_ForceReadoptsUnmanaged` asserts the end-to-end contract through `runUpgrade`. The three layers form a complete regression net for the Codex findings.
- **Counter drift** — reviewed. Pre-existing pattern: `ActionSkip` doesn't increment `skipped`. This commit preserves that pattern (no regression).
- **Symmetric state transitions** — the force-readopt arm writes `manifest.SetFile(d.Path, d.NewHash)` (flipping Managed back to true), consistent with the pass-1 overwrite arm at line 206.
- **Plan acceptance criteria alignment** — two new checkboxes (lines 68-69) match the two Codex ACTION_REQUIRED findings; both are covered by new tests.

## Positive notes

- The fix is minimal and surgical: each Codex finding gets one code-side change plus one or two tests. No drive-by refactors.
- Comments at `internal/upgrade/diff.go:84-89` and `internal/cli/upgrade.go:242-253` explicitly document *why* the code takes the path it does, not just *what* it does. The "NewContent is carried so the caller can implement re-adoption without a second FS walk" rationale is exactly the kind of hand-off note that saves the next reader from re-derivation.
- The removal-loop refactor from `for path := range manifest.Files` to `for path, mf := range manifest.Files` (with `mf` used directly instead of re-indexing `manifest.Files[path]`) also removes a double-lookup that existed in the pre-commit version. Small but welcome.
- `TestComputeDiffs_Unmanaged_SurvivesTemplateRemoval` contains both a positive ("must be ActionSkip") and a negative ("must not be ActionRemove") assertion on the same entry, which is unusual but correctly defensive — it prevents future refactors from silently demoting `ActionSkip` to a no-op while satisfying the positive assertion.
- The Codex triage doc (`codex-triage-2026-04-22-upgrade-detect-local-edits.md`) cross-references the verify report's "Coverage gap #1" and explicitly connects it to the functional contract violation, which is the kind of chain-of-reasoning trail reviewers want to see.

## Tech debt identified

| Debt item | Impact | Why deferred | Trigger to pay down | Related plan/report |
| --- | --- | --- | --- | --- |
| Skipped/Updated/Notified counters don't count all ActionSkip variants (pre-existing + extended here) | Summary line under-reports silent-skip and re-adopt events; minor UX clarity | Pre-existing pattern; fixing it now expands this PR's scope beyond the Codex fix | When adding a `--verbose` flag or when a user reports the summary feels inaccurate | `internal/cli/upgrade.go:167-273`, this report |

_(One row added; appending to `docs/tech-debt/` below via the follow-up task list.)_

## Recommendation

- Merge: yes. No CRITICAL, HIGH, or MEDIUM findings. The fix correctly closes both Codex ACTION_REQUIRED findings and adds proportionate test coverage at both the unit and integration layers.
- Follow-ups (non-blocking):
  - Consider tightening the output-substring assertion in `TestRunUpgrade_UnmanagedSurvivesTemplateRemovalAcrossRuns` to pin the exact message constant (LOW).
  - Consider adding a `--verbose` counter for silent-skip / re-adopt events to close the summary-line asymmetry (tech-debt row above).
  - The force-readopt re-adoption behavior should be called out in release notes so users who previously ran `ralph upgrade` then chose `skip` understand that a future `--force` will overwrite their local variant.
