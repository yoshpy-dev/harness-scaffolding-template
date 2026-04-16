# Self-review report: fix-template-distribution-gaps (re-run)

- Date: 2026-04-16
- Plan: docs/plans/active/2026-04-16-fix-template-distribution-gaps.md
- Reviewer: reviewer subagent
- Scope: 9 commits, 29 files changed (+4295 / -13), branch fix/template-distribution-gaps
- Re-run reason: 3 Codex WORTH_CONSIDERING findings fixed in commit 7cd1bca

## Evidence reviewed

- `git diff main...HEAD` -- full diff (29 files)
- Byte-for-byte comparison of all 16 template scripts against their `scripts/` source -- all identical (verified with `diff` for every file pair)
- `internal/cli/upgrade.go` -- `filePerm()` function and 4 call sites
- `internal/scaffold/render.go` L84-90 -- existing permission logic for comparison
- `internal/scaffold/embed_test.go` -- `TestTemplateBaseScriptsExist` (16 scripts + perm check)
- `templates/base/docs/quality/quality-gates.md` -- quality-gates cleanup
- `templates/base/scripts/commit-msg-guard.sh` -- new script (identical to `scripts/commit-msg-guard.sh`)
- `scripts/ralph-pipeline.sh` L185-194 -- Codex fix: commit-msg-guard invocation via temp file
- `scripts/new-ralph-plan.sh` L92 -- Codex fix: `--slices` replaced with `--unified-pr`
- `scripts/ralph` L112-115 -- Codex fix: plan auto-detect sort by name descending
- `docs/tech-debt/README.md` -- checked for stale/missing entries
- `docs/reports/codex-triage-*.md` -- Codex triage report reviewed for completeness
- Previous self-review, verify, test, and docs-sync reports in `docs/reports/`

## Codex fix review (new in this re-run)

| Fix | Correctness | Sync with template | Notes |
| --- | --- | --- | --- |
| ralph-pipeline.sh: commit-msg-guard.sh invocation via temp file | Correct. commit-msg-guard.sh expects `$1` (file path), not stdin. `mktemp` + `rm -f` is the right pattern. `rm -f` runs after the `if` block regardless of pass/fail. `set -eu` at script top does not interfere because `if !` suppresses `set -e`. | Synced -- `diff` confirms source and template are identical | No temp file leak on error: the `rm -f` is at the same nesting level as `mktemp`, outside the `if` body |
| new-ralph-plan.sh: `--slices` replaced with `--unified-pr` | Correct. `--unified-pr` is a valid flag in `scripts/ralph` (L47, L62, L102). `--slices` does not exist. Also fixed the bare `ralph run` to `./scripts/ralph run` for portability. | Synced | -- |
| ralph: plan auto-detect with `sort -r` | Correct. `find | sort -r | head -1` selects the lexicographically latest directory name. Since plan directories are date-prefixed (`2026-04-16-slug`), this picks the newest plan. Previous code used `find | head -1` which has non-deterministic order. | Synced | `sort -r` sorts by full path including the `docs/plans/active/` prefix, but since the prefix is constant, only the directory name varies -- sorting works correctly |

## Findings

| Severity | Area | Finding | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| MEDIUM | maintainability | `filePerm()` in upgrade.go diverges from `render.go` permission logic. `render.go` (L86) checks FS metadata (`d.Info().Mode().Perm()&0111`), then falls back to `.sh` suffix. `filePerm()` uses only name-based heuristics (`.sh` suffix + hardcoded `"ralph"` check). A new extensionless executable added to templates would need updates in `filePerm()` but not in `render.go`. | `render.go:84-90` vs `upgrade.go:20-29` | Extract a shared `IsExecutable(path string) bool` function, or make `filePerm()` check the embedded FS metadata. Low urgency -- `ralph` is the only extensionless script today. |
| MEDIUM | maintainability | `strings.Contains(path, "scripts")` in `filePerm()` (L25) is a loose substring match. A hypothetical template file at path `descriptions/ralph` or `my-scripts-backup/ralph` would falsely trigger. No such paths exist in the current template tree. | `upgrade.go:25` | Tighten to `strings.Contains(path, "scripts/")` (trailing slash) or use `filepath.Dir` to match directory segments. Trivial fix. |
| LOW | readability | Comment on `filePerm()` (L17-18) says "shebang-bearing extensionless files" but the function hardcodes the filename `"ralph"` -- it does not inspect file content for shebangs. The comment oversells generality. | `upgrade.go:17-18` | Narrow to: "the extensionless `ralph` CLI script in scripts/". |
| LOW | maintainability | No unit test for `filePerm()`. 3 branches (`.sh`, `ralph` in scripts, default 0644), 4 call sites. `embed_test.go` verifies on-disk permissions but does not exercise upgrade-path logic. | No test references to `filePerm` in codebase | Add a table-driven test in `internal/cli/upgrade_test.go`. Not blocking. |
| LOW | maintainability | Template `scripts/ralph` L182 references `scripts/build-tui.sh` which is not distributed. Unreachable in practice -- guarded by `[ -x "$_tui_bin" ]` (L178) and no scaffolded project has `bin/ralph-tui`. | `templates/base/scripts/ralph:178-182` | Pre-existing, not introduced by this branch. No action needed in this PR. |

## Positive notes

- All 16 template scripts are byte-identical to their source in `scripts/`. No accidental modifications, no stale copies. Verified with `diff` for every file pair.
- The 3 Codex fixes are correct, minimal, and properly synced to both source and template. Each fix addresses a real bug without unnecessary scope expansion.
- `commit-msg-guard.sh` is a clean POSIX sh script with appropriate secret-detection patterns (AWS keys, GitHub tokens, private key headers, env dumps) and conventional-commit validation.
- The `quality-gates.md` cleanup correctly removes 3 repo-specific references (`check-template.sh`, `check-coverage.sh`, `check-pipeline-sync.sh`) and hardcoded CI workflow paths, replacing them with actionable guidance.
- The test in `embed_test.go` guards against future regressions by verifying both existence and executable permissions on Unix, with a `runtime.GOOS` guard for Windows.
- Permission fix in `upgrade.go` is applied consistently across all 4 `os.WriteFile` call sites.
- No secrets, debug code, or commented-out code found in the diff.
- No unnecessary changes -- diff is tightly scoped to the plan's objectives plus the 3 approved Codex fixes.
- Tech debt entry for `filePerm()` divergence was already added to `docs/tech-debt/README.md`.

## Tech debt identified

| Debt item | Impact | Why deferred | Trigger to pay down | Related plan/report |
| --- | --- | --- | --- | --- |
| `filePerm()` in upgrade.go duplicates permission logic from render.go with different strategy (name-based vs FS-metadata-based) | A new extensionless executable in templates needs updates in two places with different fix patterns | Scope of this PR is distribution gaps, not refactoring permissions | Adding a second extensionless executable to templates | self-review-2026-04-16-fix-template-distribution-gaps.md |

_(Already recorded in `docs/tech-debt/README.md`.)_

## Recommendation

- Merge: YES -- no CRITICAL or HIGH findings. The two MEDIUM findings are maintainability concerns about the `filePerm()` implementation that work correctly today. The Codex fixes are correct and properly synced. No regressions introduced.
- Follow-ups:
  - Tighten `strings.Contains(path, "scripts")` to include trailing slash (trivial, can be done in this PR or a follow-up)
  - Consider extracting shared permission logic between `render.go` and `upgrade.go` in a future refactor
  - Add a unit test for `filePerm()` in a follow-up PR
