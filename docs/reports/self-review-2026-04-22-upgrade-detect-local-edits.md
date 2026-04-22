# Self-review report: upgrade — detect local edits and show unified diff

- Date: 2026-04-22
- Plan: `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md`
- Reviewer: reviewer subagent (self-review)
- Scope: diff quality only (naming, readability, unnecessary changes, typos, null safety, debug code, secrets, exception handling, security, maintainability). Spec compliance, test coverage, and doc drift are deferred to `/verify` and `/test`.

## Evidence reviewed

- `git diff main...feat/upgrade-detect-local-edits` (8 files, +1076 / −82)
- Changed files:
  - `internal/upgrade/unified_diff.go` (new, 238 lines)
  - `internal/upgrade/unified_diff_test.go` (new, 114 lines)
  - `internal/upgrade/diff.go` (+30 / −10)
  - `internal/upgrade/diff_test.go` (+89 test lines)
  - `internal/scaffold/manifest.go` (+14 / −1)
  - `internal/cli/upgrade.go` (+119 / −72)
  - `internal/cli/cli_test.go` (+305 test lines)
  - `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md` (new plan)
- Commit series: `b84bef6` → `ad20e0a` → `f0704fd` → `31ffe99` → `e960ab2` (clean progression: util → logic → CLI → tests → errcheck cleanup).

## Findings

| Severity | Area | Finding | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| LOW | typo | Test function name is misspelled `TestRunUpgrade_InteractiveDiff_ReprompltsOnInvalid` (should be `Reprompts`). Survives compilation so it does not break CI, but hurts grep-ability and test-filter UX. | `internal/cli/cli_test.go:612` | Rename to `TestRunUpgrade_InteractiveDiff_RepromptsOnInvalid` before merge — trivial one-line change. |
| LOW | maintainability | `resolutionSkip = iota` makes skip the zero value. This is safe-by-default (EOF / unknown state collapses to skip, matching the intent of the EOF handler) but the invariant is implicit. A future contributor who adds `resolutionDiff` above `resolutionSkip` silently changes the zero-value behavior. | `internal/cli/upgrade.go:287-292` | Add a one-line comment on the `const` block: `// resolutionSkip must remain the zero value so uninitialized resolutions default to the safe choice.` No code change. |
| LOW | maintainability | `resolveConflict` fallback hash chain (`DiskHash` → `OldHash` → `NewHash`) is defensively written but, after auditing all five `ActionConflict` producers in `diff.go`, every path sets a non-empty `DiskHash`. The two inner branches are effectively dead defensive code. | `internal/cli/upgrade.go:213-222`; `internal/upgrade/diff.go:107-113, 159-166, 186-193, 208-217` | Keep the outer `if hash == ""` as a belt-and-suspenders guard against future ActionConflict producers, but collapse the inner fallback. Alternatively, leave as-is and accept a fraction of a percent of unreachable-branch coverage. Non-blocking. |
| LOW | readability | `showDiff` argument order to `UnifiedDiff` treats the **local** file as the "old" side and the **template** as the "new" side, so the rendered diff reads as "transform local → template". This is a reasonable convention (+/- lines show "what overwrite would do"), but it is the **opposite** of what the plan's Acceptance Criteria #4 describes (`--- template (version) / +++ local`). The integration test `TestRunUpgrade_InteractiveDiff_ShowsUnifiedDiff` was written to match the code, so CI is green — but the plan text and code are out of sync. | `internal/cli/upgrade.go:335-340`; plan line 61; test `internal/cli/cli_test.go:558-568` | Confirm intended semantics and align. I recommend keeping the code (local-as-old reads better for "here is what overwrite will change") and updating the plan's AC #4 text in a follow-up. `/verify` should flag this formally; noting here so the reviewer is aware before acting on any verify finding. |
| LOW | readability | `groupHunks` (43 lines, 4-deep nesting with `look` / `end` / `trailing` intertwined) is the least-readable function in the diff and lacks inline commentary on the invariant being maintained (why merge-if-overlap is computed with `2*context`, why `trailing` is clamped). | `internal/upgrade/unified_diff.go:170-238` | Extract `mergeOverlappingChanges(...)` and `appendTrailingContext(...)` helpers, OR add 3-4 lines of comments describing the invariant. Tests cover the behavior well enough that this is style-only. |
| LOW | maintainability | `writef` helper comment references the static analyzer (`errcheck`) but names no rule; future readers grepping for `errcheck` in the repo will find only this file. The rationale ("silence instead of sprinkling `_, _ =`") is sound. | `internal/cli/upgrade.go:279-285` | Either cite the specific lint (`//nolint:errcheck` style) or inline-document that `writef` is the canonical progress-print helper. Minor. |
| INFO | positive | `SetFileUnmanaged` is a well-scoped additive helper with a clear godoc explaining the ownership semantics. No mutation of existing `SetFile` — backward-compatible by construction. | `internal/scaffold/manifest.go:69-88` | — |
| INFO | positive | The EOF handling in `resolveConflict` (`err != nil && line == ""`) is subtler than the old `fmt.Scanln` pattern and correctly handles the partial-line case (`"o"` followed by EOF with no newline would still be read). | `internal/cli/upgrade.go:303-307` | — |
| INFO | positive | `removingReader` is a clean mid-test injection primitive for filesystem-race simulation and is self-contained in the test file. Good pattern for future I/O-fallback tests. | `internal/cli/cli_test.go:731-756` | — |
| INFO | positive | `ActionSkip` branch now respects prior `Managed=false` entries (`if prev, ok := oldManifest.Files[d.Path]; ok && !prev.Managed`), closing the re-adoption loophole that would have occurred if the old manifest handling had been kept. | `internal/cli/upgrade.go:242-250` | — |

### Security / secrets / injection review

- No new credential-bearing code paths. `UnifiedDiff` is pure string manipulation over `[]byte`; it does not invoke any external process or shell.
- `showDiff` calls `os.ReadFile(filepath.Join(absDir, d.Path))`. `d.Path` originates from the embedded template FS walk (`fs.WalkDir` over `newFS`), not user input, and `absDir` was resolved via `filepath.Abs`. `fs.WalkDir` over `embed.FS` rejects `..` segments by construction, so path traversal from template paths is not exploitable. If the embed FS is ever replaced with a real OS directory source, this assumption should be revisited (noted as a repo-wide pattern in reviewer memory under `.claude/agent-memory/reviewer/`).
- `fmt.Fprintf(&b, "--- %s\n", oldLabel)` etc. — labels come from the caller (`"local"`, `"template (<version>)"`). `version` flows from the package-level `Version` variable set via ldflags; it is not arbitrary user input. No format-string or injection risk.
- No hardcoded secrets, API keys, or credentials introduced.

### Null safety / error handling

- `ComputeDiffsWithManifest` branch at line 89-98 reads `mf.Hash` / `mf.Managed` only when `inManifest` is true — safe.
- `diskHash, diskErr := scaffold.HashFile(diskPath)` is computed up front; all consumers correctly consult `diskErr` before using `diskHash`.
- `os.ReadFile` error in `showDiff` is explicitly handled with a warning + hash-summary fallback — no abort.
- `bufio.NewReader(in).ReadString('\n')` correctly handles partial lines + EOF via the `err != nil && line == ""` guard.
- `d.NewContent` is `nil` for `ActionRemove` but the `ActionRemove` branch never dereferences it.

### Unnecessary changes

- Commit `e960ab2` ("silence errcheck on best-effort progress writes") explains the `writef` helper. This is a legitimate response to the CI lint rule rather than a drive-by change.
- Several comment blocks were rewritten (e.g. the pack-preservation commentary on upgrade.go L119-155 was trimmed). The trims preserve the load-bearing "preserve on transient error" + "remove vs. rename" semantics; no information was lost — just formatting. Acceptable.
- No formatting-only diffs, no unrelated churn in files outside the feature scope.

### Debug code / leftover markers

- No `TODO`, `FIXME`, `console.log`, `fmt.Println("debug...")`, or commented-out code introduced.
- The trailing `template hash: X  local hash: Y` summary in `showDiff` is intentional (plan line 85, 149) and useful for incident triage.

## Positive notes

- The `Managed=false` convergence contract is the right answer to the prompt-storm risk raised in Codex plan advisory (HIGH). The implementation backs the contract with three layered defenses: (1) `ComputeDiffsWithManifest` early-return at line 89, (2) `runUpgradeIO` ActionSkip branch preserving prior unmanaged state at line 246, and (3) `SetFileUnmanaged` only being callable from the skip resolution site.
- The I/O-injection refactor (`runUpgradeIO`) is small, targeted, and kept the public entry point (`runUpgrade`) as a thin shim — no cobra command signature churn.
- `TestRunUpgrade_NextRunAfterSkip_IsSilent` uses an empty stdin and asserts the non-interactive-skip warning does **not** appear. This is the exact behavioral contract that needed locking down; the test would fail loudly if the unmanaged branch regressed.
- `TestUnifiedDiff_OrderStability` asserts determinism — a cheap regression guard that costs almost nothing and catches a class of LCS-traceback ambiguity bugs.
- Commit messages follow conventional-commits and split naturally into reviewable pieces (utility, logic, CLI, tests, errcheck).

## Tech debt identified

| Debt item | Impact | Why deferred | Trigger to pay down | Related plan/report |
| --- | --- | --- | --- | --- |
| No `ralph upgrade --resync <path>` / `--adopt` escape hatch to bring `Managed=false` entries back under template management. | Users who chose `skip` cannot easily reverse the decision without editing `.ralph/manifest.toml` by hand. | Explicitly out of scope in the plan (Non-goals + Open questions) to keep the PR small and ship convergence first. | First user request to un-skip a file, OR when `ralph doctor` grows an unmanaged-entry audit. | `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md` (Open questions) |
| Plan AC #4 diff label ordering (`--- template / +++ local`) does not match the implemented order (`--- local / +++ template`). | Minor spec-doc drift; does not affect behavior but future readers of the plan may be confused. | Caught at self-review; either side can be updated but updating the plan/doc is the cheaper fix. | `/sync-docs` step, or immediate plan edit before PR. | `docs/plans/active/2026-04-22-upgrade-detect-local-edits.md:61` |

_Both rows will be appended to `docs/tech-debt/README.md` by the next flow step if not resolved in-PR._

## Recommendation

- Merge: **yes**, after fixing the `Reprompls` typo (trivial, 1 line). All other findings are LOW severity and appropriate as follow-ups.
- No CRITICAL or HIGH findings. Pipeline may continue to `/verify`.
- Follow-ups for the next step:
  - `/verify` should explicitly confirm whether the diff label ordering matches the plan (Acceptance Criterion #4) and, if not, decide which side to update.
  - `/test` should confirm coverage of the `Managed=false` branch and the disk-read-failure fallback (both have dedicated unit tests already).
  - Consider adding the two tech-debt rows to `docs/tech-debt/README.md` during `/sync-docs` if the typo/label items are not resolved in-PR.
