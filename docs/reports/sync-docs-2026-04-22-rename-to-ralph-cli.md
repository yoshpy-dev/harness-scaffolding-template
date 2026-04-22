# Sync-docs report: rename-to-ralph-cli

- Date: 2026-04-22
- Plan: `docs/plans/active/2026-04-22-rename-to-ralph-cli.md`
- Branch: `refactor/rename-to-ralph-cli`
- Agent: doc-maintainer subagent (Claude Opus 4.7)
- Verdict: **drift-fixed**

## Scope

Scan the following surfaces for staleness introduced by the repo rename (`harness-engineering-scaffolding-template` → `ralph`) and the rebrand (repository-as-template → CLI that scaffolds):

- `README.md`, `AGENTS.md`, `CLAUDE.md`
- `.claude/skills/*/SKILL.md`
- `.claude/rules/*.md`
- `docs/quality/{definition-of-done,quality-gates}.md`
- `docs/recipes/*.md`
- `docs/architecture/*.md`
- `docs/research/*.md`
- `docs/roadmap/*.md`
- `docs/tech-debt/README.md`
- Cross-references between README ↔ AGENTS.md ↔ CLAUDE.md ↔ rules/skills

Out of scope per plan §Non-goals (left untouched):

- `docs/plans/archive/` (historical plans)
- `docs/reports/` (historical artifacts — this report is new)
- `docs/specs/` (historical specs, including `2026-04-16-ralph-cli-tool.md`)
- `docs/plans/active/2026-04-22-rename-to-ralph-cli.md` (the active plan itself)
- `templates/base/*` (already repo-name-agnostic)

## Evidence gathered

| Check | Command | Result |
| --- | --- | --- |
| Old repo name references | `grep -rn "harness-engineering-scaffolding-template"` (full repo) | 8 hits — all in excluded paths (`docs/plans/archive/` ×3, `docs/plans/active/2026-04-22-rename-to-ralph-cli.md` ×1, `docs/reports/*rename-to-ralph-cli*` ×3, `docs/specs/2026-04-16-ralph-cli-tool.md` ×1). Zero hits in in-scope paths. |
| Old name in `.github/` | `grep -rn "harness-engineering"` under `.github/` | 0 hits |
| Old name in `scripts/` | `grep -rn "harness-engineering"` under `scripts/` | 0 hits |
| Old name in `.claude/` | `grep -rn "harness-engineering"` under `.claude/` | 0 hits |
| `"this scaffold"` self-reference (stale framing post-rename) | `grep -in "this scaffold"` (full repo) | 5 hits before edit, 0 hits after — all in `docs/research/approach-comparison.md` and `docs/architecture/design-principles.md` |
| `"scaffolding template"` / `"template repository"` framing | `grep -in` (full repo, in-scope paths) | 0 hits in in-scope paths |
| Cross-reference paths in README | Verified presence of `scripts/new-feature-plan.sh`, `scripts/new-ralph-plan.sh`, `scripts/build-tui.sh`, `scripts/ralph`, `scripts/run-verify.sh`, `docs/recipes/ralph-loop.md`, `docs/roadmap/harness-maturity-model.md` | All exist |
| `./scripts/run-verify.sh` after edits | Full pipeline (gofmt, gofumpt, staticcheck/vet, go tests, check-sync, check-mojibake, golang verifier) | PASS (`docs/evidence/verify-2026-04-22-104043.log`) |

## Changes applied

### 1. `docs/architecture/design-principles.md`

| Line | Before | After | Reason |
| --- | --- | --- | --- |
| 1 (H1 title) | `# Design principles for the scaffold` | `# Design principles for ralph` | Post-rename the repo is a CLI; "the scaffold" as a self-reference is ambiguous. "ralph" names the product. |
| 62 | `The scaffold should support:` | `The harness ralph emits should support:` | Disambiguates "scaffold" from repo-self-reference to "the harness ralph generates". |

### 2. `docs/research/approach-comparison.md`

| Line | Before | After |
| --- | --- | --- |
| 3 | `This document distills the main approach families that informed this scaffold.` | `This document distills the main approach families that informed \`ralph\` and the harness it ships.` |
| 16 | `This scaffold therefore chooses a **hybrid default**:` | `` `ralph` therefore chooses a **hybrid default**: `` |
| 26 | `... | Borrowed into this scaffold |` (table header) | `... | Borrowed into ralph |` |
| 31 | `... | core control plane of this scaffold |` | `... | core control plane of ralph |` |
| 105 | `## What this scaffold intentionally does not do by default` | `## What ralph intentionally does not do by default` |

Rationale: each "this scaffold" was a project-self-reference that made sense when the repo was framed as "a scaffolding template." Post-rename, `ralph` is the product name and self-references should use it. "Scaffold" as a common noun (e.g., "the harness ralph emits") is preserved where it refers to the artifacts emitted by `ralph init`.

## Surfaces confirmed already aligned (no edits needed)

| File | Evidence |
| --- | --- |
| `README.md` | Title `# ralph`, lead "`ralph` is a CLI for harness engineering...", no "scaffolding template" framing. `scaffold` appears only as a verb or as a noun referring to what `ralph init` emits. |
| `AGENTS.md` | Line 3 already reads `This repository hosts \`ralph\`, a CLI for harness engineering. Run \`ralph init\` to scaffold a new project from this source.` Primary loop, repo map, contracts all current. |
| `CLAUDE.md` | Line 9 already refers to `ralph` CLI for the `/release` skill. No stale repo-name or template-repo framing. |
| `.claude/skills/release/SKILL.md` | Already references `brew upgrade ralph`, `yoshpy-dev/homebrew-tap`, and `yoshpy-dev/ralph` consistently. "not distributed via template" wording refers to the embedded `templates/base/` — correct in context (the skill is repo-maintainer only; `ralph init` does not emit it). |
| `.claude/skills/loop/SKILL.md` | References `ralph run`, `ralph status`, `ralph-orchestrator.sh` — all current. |
| `.claude/skills/work/SKILL.md` | Uses `template` only to mean `[template.md]` plan templates — unchanged semantics. |
| `.claude/skills/plan/SKILL.md` | Same — `[template.md]` references are plan-template file references, not repo-as-template framing. |
| `.claude/skills/spec/SKILL.md`, `verify/SKILL.md`, `test/SKILL.md`, `self-review/SKILL.md`, `pr/SKILL.md`, `codex-review/SKILL.md`, `audit-harness/SKILL.md`, `sync-docs/SKILL.md` | All `template` / `scaffold` mentions refer to report/plan template files or are scope-neutral. No stale self-references. |
| `.claude/rules/*.md` | Scanned all 13 files. Only hit is `documentation.md:14` "Prefer concrete examples, checklists, and templates over long essays." — generic noun, not self-reference. |
| `docs/quality/definition-of-done.md` | Pipeline order and checklists reference `/work`, `/loop`, `ralph status`, `integration/<slug>`, etc. All current. |
| `docs/quality/quality-gates.md` | References `check-template.sh`, `check-sync.sh`, `check-template.yml` — all refer to existing CI scripts/workflows, not to repo-as-template framing. |
| `docs/recipes/ralph-loop.md` | No stale "scaffolding template" framing. Uses `ralph run`, `ralph status`, `RALPH_*` config vars. |
| `docs/recipes/{adding-a-language-pack,agent-teams,worktrees}.md` | No `template`/`scaffold` self-reference. |
| `docs/architecture/repo-map.md` | Line 41 "repo-only, not distributed via template" is correct: distinguishes repo-only skills from those embedded in `templates/base/`. Line 47 references CI workflow filenames as-is. No stale framing. |
| `docs/roadmap/harness-maturity-model.md` | Line 14 "Level 2: Workflow scaffold" is a generic maturity-level label, not a claim about this repo. Line 16 "report templates" is a generic noun. Both stay. |
| `docs/tech-debt/README.md` | All "template" mentions are either `templates/` directory references or `fix-template-distribution-gaps` PR names — historically correct. No staleness. |
| `docs/research/approach-comparison.md` (remaining `template` mentions after edits) | Line 32 "workflow skills, support templates, harness audit skill" — generic. Line 101 "Task-specific prompt templates" — refers to Ralph Loop prompt templates, correct. |
| `.github/workflows/` | 0 hits for old repo name (plan predicted `${{ github.repository }}` usage; confirmed). |
| `scripts/` | 0 hits for old repo name. |

## Cross-reference consistency

| Cross-reference | Status |
| --- | --- |
| README "Operating loop" ↔ AGENTS.md "Primary loop" ↔ CLAUDE.md "Default behavior" | Aligned — all reference the same 10-step canonical sequence with `/sync-docs` before `/codex-review`. |
| README `Quick start` commands ↔ `scripts/` | Verified: `new-feature-plan.sh`, `new-ralph-plan.sh`, `run-verify.sh`, `scripts/ralph` all exist. |
| README "Ralph Loop" section ↔ `docs/recipes/ralph-loop.md` ↔ `.claude/skills/loop/SKILL.md` | All consistent (config env-vars, `ralph run`/`status`/`retry`/`abort` commands, safety rails list). |
| README "Language packs" ↔ `templates/packs/` ↔ `internal/scaffold/embed.go` | `ralph pack add golang` uses the correct pack name (`golang`, not `go`). Self-review MEDIUM finding already corrected in the rename PR. |
| AGENTS.md "Repo map" ↔ filesystem | All listed paths exist: `cmd/ralph/`, `cmd/ralph-tui/`, `internal/{cli,scaffold,upgrade,config,state,watcher,ui,action}/`, `templates/`, `docs/*`, `.claude/*`, `packs/languages/`, `scripts/` (including `ralph-config.sh`, `ralph-pipeline.sh`, `ralph-orchestrator.sh`, `install.sh`). |
| `.claude/rules/post-implementation-pipeline.md` "Where this order is referenced" list | All 8 referenced files still contain the canonical pipeline order. |
| CLAUDE.md "Manual-trigger skills" description of `/release` | Matches `.claude/skills/release/SKILL.md` frontmatter `description` — both note `repo-only, not distributed via template`. |

## Known gaps / follow-ups

- **Testdata PR URLs are string-literal-coupled** across `internal/state/testdata/*.json` and `internal/state/reader_test.go` (already recorded in the self-review report LOW finding, deferred — not promoted to `docs/tech-debt/README.md` because it has not recurred yet).
- No other drift found.

## Commands run

```
grep -rn "harness-engineering-scaffolding-template" .
grep -rin "scaffolding template" .
grep -rin "template repository" .
grep -rin "this scaffold" .
grep -rn "template\|scaffold" .claude/skills
grep -rn "template\|scaffold" .claude/rules
grep -rn "template\|scaffold" docs/{quality,architecture,recipes,research,roadmap,tech-debt}
./scripts/run-verify.sh
```

## Evidence log

- `docs/evidence/verify-2026-04-22-104043.log` — `run-verify.sh` PASS after edits

## Verdict

**drift-fixed.** Two documentation files had project-self-references that became ambiguous after the rename ("this scaffold" used to mean "this repo"; post-rename, the repo is a CLI named `ralph` and its output is the scaffold). Edits were minimal, semantics-preserving, and verified with `run-verify.sh`. All other in-scope surfaces — README, AGENTS.md, CLAUDE.md, skills, rules, quality docs, recipes, architecture, tech-debt — were already aligned by the rename PR itself.
