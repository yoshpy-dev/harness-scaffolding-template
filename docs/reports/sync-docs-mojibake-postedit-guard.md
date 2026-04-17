# Sync-docs report: mojibake-postedit-guard

- Date: 2026-04-17
- Plan: `docs/plans/active/2026-04-17-mojibake-postedit-guard.md`
- Branch: `chore/mojibake-postedit-guard`
- Author: `doc-maintainer` subagent
- Upstream reference: Claude Code Issue #43746 (SSE chunk-boundary U+FFFD injection)

## Scope of this diff

Additive, hook-only change. New files:

- `.claude/hooks/check_mojibake.sh` (+ `templates/base/` mirror)
- `.claude/hooks/mojibake-allowlist` (+ `templates/base/` mirror)
- `scripts/verify.local.sh`
- `tests/test-check-mojibake.sh`
- `tests/fixtures/payloads/{edit,write,multiedit}.json`

Modified files:

- `.claude/settings.json` and `templates/base/.claude/settings.json` — PostToolUse matcher expanded from `Edit|Write` to `Edit|Write|MultiEdit`, and `check_mojibake.sh` added as a second entry alongside the existing `post_edit_verify.sh`.
- `scripts/check-sync.sh` — `ROOT_ONLY_EXCLUSIONS` extended with repo-only paths (`scripts/verify.local.sh`, `tests/`).
- `AGENTS.md` — one-line nested bullet under the `.claude/hooks/` entry describing the temporary mitigation and retirement trigger (already covered by `/self-review` and `/verify`).

No skills, no rules, no language packs, no CI workflows, no script entrypoints, and no public contracts were changed by this diff.

## Files updated in this sync pass

| File | Change | Why |
| --- | --- | --- |
| `docs/plans/active/2026-04-17-mojibake-postedit-guard.md` | Progress checklist: "Review artifact created", "Verification artifact created", "Test artifact created" flipped from `[ ]` to `[x]` with the corresponding report paths appended. PR checkbox left unchecked (handled by `/pr`). | Plan checklist was stale; all three artifacts exist in `docs/reports/` with PASS verdicts. Matches the pattern used by `sync-docs-2026-04-17-allow-go-and-repo-commands.md`. |
| `docs/tech-debt/README.md` | New row added for the mojibake mitigation bundle (hook + allowlist + tests + fixtures + settings entry + AGENTS.md note + check-sync.sh exclusions). | Captures the retirement trigger: "Upstream Issue #43746 closes in a released Claude Code version AND no local recurrences observed for 1 week." Keeps the removal contract in the same place as other deferred work so a future reader finds it without re-reading the plan. |

## Files checked and left unchanged

| Doc / contract | Result | Evidence |
| --- | --- | --- |
| `AGENTS.md` Repo map | Already synced | `AGENTS.md:66` carries the one-line `check_mojibake.sh` + `mojibake-allowlist` note. Per user instruction, no further edits. `/verify` explicitly flagged this as "PASS (1-line consolidated form)". |
| `CLAUDE.md` | No change needed | Scoped to skill orchestration and always-on defaults; does not enumerate individual hooks. Per user instruction, not edited. |
| `templates/base/AGENTS.md` | No change needed | KNOWN_DIFF per `scripts/check-sync.sh:83`. The template intentionally omits repo-specific hook notes; this matches the plan's scope ("scaffolded projects get the hook; the scaffolded AGENTS.md stays generic"). |
| `templates/base/CLAUDE.md` | No change needed | Scoped to skill defaults; no hook enumeration. |
| `README.md` — "Hook configuration" section (L178-190) | No change needed | Describes hooks shipped in `settings.json` at a behavior level (session start, prompt gate, bash guard, edit/write verification reminders, tool failure feedback, compaction checkpoints, session end). Adding a "mojibake guard" bullet would expand scope beyond the plan and would need to be torn down when the hook retires. The existing "Edit/write verification reminders" bullet is generic enough to accommodate both hooks under the shared matcher. |
| `README.md` — Operating loop (L127-176) | No change needed | Pipeline order and skill roster unchanged; no drift. |
| `docs/architecture/repo-map.md` | No change needed | References `.claude/hooks/` generically as "deterministic hook scripts" and `.claude/settings.json` generically as "hook and permission configuration". Accurate at that granularity for an additive hook. |
| `docs/architecture/design-principles.md` | No change needed | `grep -n 'PostToolUse\|check_mojibake\|mojibake\|hooks/'` returns 0 hits. High-level principles file; no hook enumeration. |
| `docs/quality/definition-of-done.md` | No change needed | DoD checklist is pipeline-shaped (artifacts, plans, pipeline order). A new PostToolUse hook is not a DoD item. |
| `docs/quality/quality-gates.md` | No change needed | Lists gate policy (must-pass scripts, CI workflows, pipeline-mode gates). `scripts/verify.local.sh` is auto-invoked by `run-verify.sh` (the file is already under the "must pass locally" gate "`./scripts/run-verify.sh`") — no new verifier needs listing. |
| `.claude/rules/architecture.md` | No change needed | Grep-ability rules unchanged; new hook names are grep-able. |
| `.claude/rules/documentation.md` | No change needed | No new doc types introduced. |
| `.claude/rules/planning.md` | No change needed | Plan structure unchanged. |
| `.claude/rules/testing.md` | No change needed | Tests were added (`tests/test-check-mojibake.sh`, 11/11 PASS); rule is already satisfied. |
| `.claude/rules/git-commit-strategy.md` | No change needed | 5-commit slicing discipline respected; no new pattern. |
| `.claude/rules/post-implementation-pipeline.md` | No change needed | Pipeline order unchanged. |
| `.claude/rules/subagent-policy.md` | No change needed | Subagent set unchanged. |
| `.claude/rules/<lang>.md` (python, typescript, golang, rust, dart) | No change needed | No language-pack changes in this diff. |
| `.claude/skills/audit-harness/SKILL.md` | No change needed | Audit prompt already includes `.claude/hooks/` as an inspect target; the new hook will be surfaced in future audits without any SKILL.md change. |
| `.claude/skills/sync-docs/SKILL.md` | No change needed | Skill scope covers "hooks added/removed"; the additions are now reflected in settings.json + AGENTS.md + this report. |
| `scripts/check-sync.sh` | Already synced | `ROOT_ONLY_EXCLUSIONS` now covers `scripts/verify.local.sh` and the `tests/` prefix. `check-sync.sh` itself is also covered by the existing `docs/reports/sync-docs-` prefix exclusion, so this report is excluded from ROOT_ONLY detection. Verified via `/verify`'s PASS row (`IDENTICAL: 107, DRIFTED: 0, ROOT_ONLY: 0`). |
| `scripts/run-verify.sh` | No change needed | Auto-invokes `verify.local.sh` as documented. |

## Drift analysis: none of the sync-docs checklist items triggered a doc edit

Cross-referenced against `.claude/skills/sync-docs/SKILL.md`'s checklist:

- **Skills added/removed/renamed**: none.
- **Hooks added/removed**: one hook added; settings.json entries match (both root and template); audit-harness target already includes `.claude/hooks/`; AGENTS.md note already present.
- **Rules added/removed**: none.
- **Language packs added/removed**: none.
- **Scripts added/removed**: `scripts/verify.local.sh` added. README Quick Start still lists `./scripts/run-verify.sh` which transitively runs `verify.local.sh`; `docs/architecture/repo-map.md` lists scripts at a role level ("verification (`run-verify.sh`, `run-static-verify.sh`, `run-test.sh`), CI checks, commit safety, language detection...") — `verify.local.sh` fits under the existing "verification" umbrella and does not warrant a separate enumeration, since it is a repo-local inner ring not present in scaffolded projects (by design per `check-sync.sh` exclusions). **No change.**
- **Quality gates changed**: none (see unchanged table above).
- **PR skill consistency**: `/pr` pre-checks read `docs/reports/self-review-*.md`, `verify-*.md`, `test-*.md` — all present and PASS. No drift.

## Residual doc drift

| Item | Severity | Disposition |
| --- | --- | --- |
| Plan's acceptance-criteria checklist (plan L60-72) is still `- [ ]` on every row. | Low | Out of scope for `/sync-docs`. `/verify` flagged the same drift as advisory ("Recommendation: `/sync-docs` or `/pr` flips the AC checkboxes to `[x]` based on this verify report"). We updated only the pipeline-stage "Progress checklist" section (L167-175) per the task instructions; the AC list is a separate historical record and is not the canonical pipeline progress tracker. `/pr` archives the plan as-is; the AC checkbox state will be frozen in archive. Leaving it is acceptable because `/verify`'s PASS row already records AC satisfaction authoritatively. |
| Hook stderr wording differs from plan AC3 text ("Re-read the file and rewrite the corrupted section without the replacement character." vs. "Re-read and rewrite the corrupted sections."). | Low | Self-review LOW-7 and verify "text deviation noted" both captured this. Meaning preserved; plan wording was illustrative, not normative. Not worth churning either side. |
| Plan mentions "2 行注記" for AGENTS.md; implementation landed one bullet line. | Low | Self-review LOW-7 captured this. The one-line form fits AGENTS.md's "keep short" rule. Not a drift to fix. |

## Conclusion

Two files updated in this pass:

- `docs/plans/active/2026-04-17-mojibake-postedit-guard.md` — progress checklist flipped for the three post-implementation artifacts.
- `docs/tech-debt/README.md` — new row for the mojibake-hook bundle with the Issue #43746 retirement trigger.

Everything else in the repo (product docs, harness docs, templates, rules, skills, scripts, quality gates) was already in sync because this diff is a narrow, additive, well-scoped mitigation. AGENTS.md and CLAUDE.md were intentionally not touched (per user instruction); the AGENTS.md one-line note was in place before `/sync-docs` ran.

Proceed to `/codex-review` (optional) then `/pr`.
