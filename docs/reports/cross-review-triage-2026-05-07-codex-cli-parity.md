# Cross-review triage report: codex-cli-parity

- Date: 2026-05-07
- Plan: docs/plans/active/2026-05-07-codex-cli-parity.md
- Base branch: main
- Driver: claude  Reviewer: codex
- Triager: Claude Code (main context)
- Self-review cross-ref: yes (`docs/reports/self-review-2026-05-07-codex-cli-parity.md`)
- Cycle: 1/2 (cap NOT reached)
- Total reviewer findings: 4
- After triage: ACTION_REQUIRED=3, WORTH_CONSIDERING=1, DISMISSED=0

## Triage context

- Active plan: `docs/plans/active/2026-05-07-codex-cli-parity.md`
- Self-review report: `docs/reports/self-review-2026-05-07-codex-cli-parity.md` (no CRITICAL findings; HIGH items already addressed in commit `82679f1`)
- Verify report: `docs/reports/verify-2026-05-07-codex-cli-parity.md` (PASS)
- Test report: `docs/reports/test-2026-05-07-codex-cli-parity.md` (PASS)
- Implementation context summary: 12 commits since main; standard-flow Codex parity. Loop driver scope-out tracked in #44.

## ACTION_REQUIRED

| # | Codex finding | Triage rationale | Affected file(s) |
|---|---------------|------------------|-------------------|
| 1 | Verify the Codex binary before passing doctor — `LookPath("codex")` succeeds on stale/broken shims; `ralph doctor` reports `pass` without confirming the binary actually runs. | Real defect against AC-6 ("ralph doctor が Codex CLI version 表示 + verify ステータス"). The repo already has `scripts/codex-check.sh` that runs `codex --version`; doctor should call/replicate it. Same gap exists in `checkClaudeCLI` so the symmetric fix lifts both. Small, surgical change. | `internal/cli/doctor.go:117-134` (`checkClaudeCLI`/`checkCodexCLI`) |
| 2 | Wire at least one Codex hook by default — every `[[hooks.*]]` entry in the shipped template is commented out, so `checkCodexEffectiveConfig` reports the no-hooks warning on every fresh `ralph init`. | Real contract drift. `.codex/README.md` already says hooks "shell out to the same `scripts/` used by `.claude/hooks/`" — but ships zero entries. Result: every new project trips the doctor warning despite intending to be hook-equipped. Fix: ship at least the `commit-msg-guard.sh` PostToolUse entry so Claude/Codex parity is real, not aspirational. | `templates/base/.codex/config.toml:74-76` |
| 3 | Make the cross-review report template bidirectional — header hard-codes `Triager: Claude Code` and column captions still say "Codex finding"; conflicts with the new `Driver: <…> Reviewer: <…>` requirement. | Real misalignment with Slice 3 bidirectional contract (AC-5). When Codex drives, the template captions misrepresent which side produced findings. Fix is text-only. | `docs/reports/templates/cross-review-triage-report.md:6,20,25,30` (and `templates/base/` mirror) |

## WORTH_CONSIDERING

| # | Codex finding | Triage rationale | Affected file(s) |
|---|---------------|------------------|-------------------|
| 1 | Treat dual-CLI Codex sessions as Codex-driven — fallback when both `codex` and `claude` are on PATH and `RALPH_PRIMARY_CLI` is unset resolves to `driver=claude / reviewer=codex`, so a Codex user who forgot to export the env var ends up running `codex` against `codex`. | Real concern, but already partially mitigated: `.codex/AGENTS.override.md` and `docs/recipes/codex-setup.md` instruct Codex users to export `RALPH_PRIMARY_CLI=codex`, and the same-model failure mode produces a same-model "review" rather than data corruption. The cleanest in-skill fix would be a runtime warning when both CLIs are present without the env var, but that overlaps with the broader detection problem (a skill cannot reliably know which CLI is invoking it). Worth keeping on the radar; not blocking. | `.claude/skills/cross-review/SKILL.md:39`, `.agents/skills/cross-review/SKILL.md:39` |

## DISMISSED

| # | Codex finding | Dismissal reason | Category |
|---|---------------|------------------|----------|
| — | — | — | — |

Categories: false-positive, already-addressed, style-preference, out-of-scope, context-aware-safe
