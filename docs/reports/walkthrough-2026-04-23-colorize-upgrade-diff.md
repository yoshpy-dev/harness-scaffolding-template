# Walkthrough: colorize-upgrade-diff

- Date: 2026-04-23
- Branch: `feat/colorize-upgrade-diff`
- Diff size: 1043 lines (16 files) — most are documentation; **~250 lines of actual code+test changes**
- Plan: `docs/plans/archive/2026-04-23-colorize-upgrade-diff.md` (archived at PR time)

## How to read this PR (in 5 minutes)

The PR makes the `ralph upgrade` interactive `[d]iff` view human-readable: each line gets a right-aligned `<old> <new> │ <prefix>content` gutter, and the cryptic `@@ -10,7 +10,8 @@` hunk header becomes `@@ 旧 L10–16  →  新 L10–17 @@`. ANSI colors are applied when stdout is a TTY and `NO_COLOR` is unset.

### Suggested review order

1. **`internal/upgrade/unified_diff.go`** (rendering rewrite) — core of the change. The `lcsDiff` / `groupHunks` algorithm is unchanged; only the rendering loop is rewritten to walk each op with running line-number counters and emit the gutter. New helpers: `formatRange` (range header), `gutterWidth` (dynamic column width).
2. **`internal/upgrade/colorize.go`** (new, 87 lines) — pure function. `Colorize(diff string) string` walks lines, classifies each by prefix, and wraps with ANSI escapes. Unrecognized lines pass through untouched (degrades safely).
3. **`internal/cli/upgrade.go`** (~25 line delta) — adds `shouldColorize(*os.File)` that gates on `NO_COLOR` + `term.IsTerminal`. The `colorize bool` flag threads through `runUpgradeIO → resolveConflict → showDiff`. The 6-argument `runUpgradeIO` is flagged as LOW maintainability tech-debt (see `docs/tech-debt/README.md`).
4. **Tests** — `internal/upgrade/colorize_test.go` (new, 9 cases), `internal/upgrade/unified_diff_test.go` (existing assertions migrated to new format + 3 new cases incl. 5-digit gutter), `internal/cli/cli_test.go` (TTY on/off assertions, `NO_COLOR` unit test, all `runUpgradeIO` call sites updated).
5. **Docs** — `README.md` adds a new "ralph upgrade interactive diff" subsection. `docs/specs/2026-04-16-ralph-cli-tool.md` regenerates the diff sample and extends the user-owned-convergence bullet with the gutter / color / `NO_COLOR` contract.

### Doc-only files (skim)

- `docs/plans/active/...` (will be archived at merge) — original plan with progress checklist
- `docs/reports/{self-review,verify,test,sync-docs,codex-triage}-2026-04-23-colorize-upgrade-diff.md` — pipeline outputs
- `docs/evidence/colorize-upgrade-diff-2026-04-23-nocolor.txt` — captured CLI output

### What is NOT changed

- `lcsDiff` / `groupHunks` algorithm (intentional — keeps decision trace identical so any diff shape regression points at rendering, not semantics)
- TUI (`cmd/ralph-tui`) — out of scope
- Windows console virtual-terminal mode — relies on standard PowerShell / Windows Terminal support; legacy CMD users can `NO_COLOR=1`
- Syntax highlighting per language — out of scope

## Risks (recap from plan)

- **Downstream parsers of old format**: verified absent via `grep -rn "@@ -"` — only documentation matches, which we updated.
- **Wide line numbers**: `gutterWidth` scales dynamically; covered by `TestUnifiedDiff_GutterWidth_FiveDigitLineNumbers` (10k-line file).
- **Terminal-injection**: ANSI escapes come from constants only; user input never reaches SGR codes (called out in self-review).

## Rollback

Single revert: `git revert <merge-commit>`. No data migration, no manifest schema change.
