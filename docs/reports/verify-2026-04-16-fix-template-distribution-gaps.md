# Verify report: fix-template-distribution-gaps (re-verify after Codex fixes)

- Date: 2026-04-16
- Plan: docs/plans/active/2026-04-16-fix-template-distribution-gaps.md
- Verifier: verifier subagent (re-run)
- Scope: All 7 ACs + 3 Codex WORTH_CONSIDERING fixes + source/template parity
- Evidence: `docs/evidence/verify-2026-04-16-fix-template-distribution-gaps.log`

## Spec compliance

| Acceptance criterion | Status | Evidence |
| --- | --- | --- |
| AC1: templates/base/scripts/ has 16 scripts | PASS | `ls` count = 16; all 16 names confirmed |
| AC2: commit-msg-guard.sh exists and git-commit-strategy.md reference correct | PASS | File exists; L69 references it correctly |
| AC3: quality-gates.md has no repo-specific script or nonexistent CI workflow refs | PASS | No matches for check-template/build-tui/etc.; .github/workflows/ mention is a suggestion, not a hard reference |
| AC4: `go build ./cmd/ralph/` succeeds | PASS | Exit 0 |
| AC5: TestTemplateBaseScriptsExist in embed_test.go | PASS | Function present (L52-93); checks all 16 names + non-empty content |
| AC6: `go test ./...` all pass | PASS | `run-static-verify.sh` exit 0; all packages ok (cached) |
| AC7: upgrade.go writes .sh files with 0755 permission | PASS | `filePerm()` function (L20-29); all 4 WriteFile sites use `filePerm(d.Path)`; also covers extensionless "ralph" |

## Codex fix compliance

| Fix | Status | Evidence |
| --- | --- | --- |
| ralph-pipeline.sh: commit-msg-guard.sh invocation via temp file | PASS | L185-194: mktemp, printf, pass file path, rm cleanup. Source and template identical. |
| new-ralph-plan.sh: removed invalid `--slices` flag, prints valid `--plan` + `--unified-pr` | PASS | L92: `./scripts/ralph run --plan ${plan_dir} --unified-pr`. Flags verified against scripts/ralph usage. Source and template identical. |
| ralph: plan detection uses `sort -r` for deterministic newest-first | PASS | L113-115: `sort -r | head -1`. Source and template identical. |

## Static analysis

| Command | Result | Notes |
| --- | --- | --- |
| `go vet ./...` | EXIT 0, 0 issues | Clean |
| `go build ./cmd/ralph/` | EXIT 0 | Embed includes all 16 template scripts |
| `HARNESS_VERIFY_MODE=static ./scripts/run-static-verify.sh` | EXIT 0 | gofmt ok, go vet clean, all test packages ok |
| `sh -n scripts/ralph-pipeline.sh` | SYNTAX OK | Shell syntax valid |
| `sh -n scripts/new-ralph-plan.sh` | SYNTAX OK | Shell syntax valid |
| `sh -n scripts/ralph` | SYNTAX OK | Shell syntax valid |

## Documentation drift

| Doc / contract | In sync? | Notes |
| --- | --- | --- |
| templates/base/.claude/rules/git-commit-strategy.md | Yes | commit-msg-guard.sh reference matches distributed file |
| templates/base/docs/quality/quality-gates.md | Yes | Repo-specific scripts removed; CI workflow mention is suggestive, not assertive |
| templates/base/scripts/ralph L182 | LOW drift | References "scripts/build-tui.sh" which is not distributed; unreachable in practice (guard at L178 requires bin/ralph-tui to exist) |
| Source-to-template script parity (16 scripts) | Yes | All 16 scripts identical between scripts/ and templates/base/scripts/ |
| docs/tech-debt/README.md | Yes | filePerm() duplication entry committed in f14f925 |

## Observational checks

- All 3 Codex fixes applied to both source scripts and template copies, keeping parity
- upgrade.go `filePerm()` covers both `.sh` suffix and extensionless "ralph" in `scripts/` path
- render.go uses FS metadata for permission (L86) with `.sh` suffix fallback (L88); the extensionless "ralph" is handled only via FS metadata path -- known pre-existing gap, tracked in tech-debt
- Uncommitted change: `docs/reports/test-*.md` updated by tester re-run (updated test counts, Codex fix regression check). Must be committed before PR.

## Coverage gaps

1. **AC5/AC6 test results are cached**: The static verify run showed `(cached)` for all test packages. Fresh execution confirmed by /test re-run (263 tests, 260 pass, 3 pre-existing skips).

2. **Codex shell fixes lack automated shell tests**: The 3 Codex fixes are verified by grep/inspection and shell syntax checks (`sh -n`). No automated behavior tests exist for these shell code paths. LOW risk for this branch.

3. **render.go "ralph" permission gap** (pre-existing, not this branch): render.go relies on `d.Info()` execute bit for extensionless `ralph`. `go:embed` may not preserve this bit. upgrade.go handles it correctly via explicit name check. Pre-existing gap, not introduced by this branch.

4. **Uncommitted test report**: `docs/reports/test-2026-04-16-fix-template-distribution-gaps.md` has uncommitted changes from the tester re-run. Must be committed before PR creation.

## Verdict

- **Verified**: AC1, AC2, AC3, AC4, AC7 (fully verified with evidence). All 3 Codex fixes verified with evidence and source/template parity confirmed.
- **Verified (static, confirmed by /test)**: AC5, AC6 (test code correct; cached in static verify; fresh execution confirmed by /test re-run: 260 pass, 0 fail, 3 skip)
- **Not verified (out of scope, pre-existing)**: render.go extensionless "ralph" permission handling via go:embed

**Overall: PASS** -- All 7 acceptance criteria met. All 3 Codex fixes verified and in sync between source and template. One uncommitted test report update must be committed before PR.
