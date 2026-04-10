# Harness Audit Memo — 2026-04-10

**Scope:** Full harness audit (CLAUDE.md, AGENTS.md, rules, skills, scripts, hooks, quality docs)
**Branch:** feat/ralph-loop-v2
**Method:** 5 parallel Explore agents covering non-overlapping areas

---

## Strengths

1. **Script robustness** — All 18 scripts pass `bash -n`, have correct shebangs, `set -eu`, and executable permissions. Error handling is thorough (`status_file` pattern, repair cycles, stuck detection).
2. **Pipeline flow integrity** — `ralph` CLI → `ralph-orchestrator.sh` → `ralph-pipeline.sh` chain is fully integrated with no broken references. Preflight probe validates dependencies before execution.
3. **Quality parity achieved** — Ralph Loop pipeline prompts (`pipeline-*.md`) mirror standard-flow subagent responsibilities. Both flows produce reports in `docs/reports/` with identical format.
4. **Clear skill boundaries** — `/self-review`, `/verify`, `/test` each have explicit "What X does NOT do" sections. Zero overlap detected.
5. **Quality docs alignment at 95%** — `definition-of-done.md`, `quality-gates.md`, CI workflows, and scripts are mutually consistent. All defined gates are implemented.
6. **State management** — Checkpoint JSON + sidecar files + status files provide robust inter-process communication for parallel slice execution.
7. **Hook coverage** — 8 hooks covering security (bash guard, commit-msg guard), lifecycle (session start/end, precompact), and verification (post-edit).

---

## Pain Points

### P1 — Must Fix

| # | Issue | Location | Impact |
|---|-------|----------|--------|
| 1 | **AGENTS.md primary loop missing `/sync-docs`** | `AGENTS.md` lines 20-31 | Steps 4-8 skip sync-docs entirely. Readers get an incomplete pipeline picture. |
| 2 | **`check_uncommitted` utility referenced but never implemented** | `git-commit-strategy.md` line 27 | Rule references a function that doesn't exist. Actual implementation uses `git diff-index --quiet HEAD` inline. |
| 3 | **Two files claim "Single source of truth" for overlapping content** | `post-implementation-pipeline.md` + `subagent-policy.md` | Step responsibilities table duplicated. Pipeline order defined in both. Maintenance risk. |

### P2 — Should Fix

| # | Issue | Location | Impact |
|---|-------|----------|--------|
| 4 | **`progress.log` append rule doesn't match implementation** | `git-commit-strategy.md` line 24 | Rule says "append summary to progress.log" but ralph-loop.sh only appends warnings. |
| 5 | **AGENTS.md claims "short" but is 121 lines** | `AGENTS.md` lines 6, 104 | Hard rules say "Keep this file short." Verification/Test contract sections (lines 79-100) duplicate content from `definition-of-done.md`. |
| 6 | **Loop SKILL.md Step 3.5 worktree logic is ambiguous** | `.claude/skills/loop/SKILL.md` | Timing of worktree creation vs. plan confirmation unclear. In-place branch detection criteria underspecified. |
| 7 | **Pipeline prompts verbose for `claude -p`** | `pipeline-verify.md`, `pipeline-test.md` (146 lines each) | Self-contained by design, but checklist/table format instructions duplicate standard-flow SKILL.md content. Template references could reduce size. |

### P3 — Nice to Have

| # | Issue | Location | Impact |
|---|-------|----------|--------|
| 8 | **`ralph-loop-init.sh` vs `/loop` skill positioning unclear** | `docs/recipes/ralph-loop.md` | Recipe references old init script flow alongside new `/loop` skill. Relationship needs one sentence of clarification. |
| 9 | **`.harness/state/pipeline/` vs `docs/reports/` dual-write not documented** | Quality docs | Which reports go where is implicit. A table would help. |
| 10 | **`post-implementation-pipeline.md` update map incomplete** | Lines 36-44 | `loop/SKILL.md` entry lacks specific line/section reference. |

---

## Missing Guardrails

| Gap | Current State | Proposed Action |
|-----|--------------|-----------------|
| No automated check that AGENTS.md primary loop matches `post-implementation-pipeline.md` | Manual sync only | Add a CI check or script that greps both files for pipeline step names |
| No lint for "Single source of truth" conflicts | Two files claim it for overlapping content | Consolidate: one file owns the order, the other references it |
| Hook failure log rotation | `.harness/logs/hook-failures.log` is append-only | Add rotation or size check (low priority) |

---

## Proposed Promotions: Prose to Code

| Rule (prose) | Target (code) | Effort |
|--------------|---------------|--------|
| `check_uncommitted` utility (git-commit-strategy.md) | Shell function in `ralph-pipeline.sh` or shared lib | Small — already implemented inline, just needs extraction |
| "Update all of these locations" checklist (post-implementation-pipeline.md lines 36-44) | CI script that greps for pipeline order consistency | Medium — cross-file grep + diff |
| Language-specific lint rules (typescript.md, python.md, rust.md) | Pre-commit hook or `run-verify.sh` integration | Medium — per-language linter config |

---

## Simplifications Worth Trying

1. **Merge pipeline order into one canonical file.** Keep `post-implementation-pipeline.md` as the single owner. Remove the duplicated table from `subagent-policy.md` and replace with a one-line reference: `> Pipeline order: see post-implementation-pipeline.md`.

2. **Trim AGENTS.md by ~30 lines.** Move Verification contract (lines 79-89) and Test contract (lines 91-100) to `definition-of-done.md` (where they already exist in fuller form). Keep AGENTS.md as a map, not a manual.

3. **Add `/sync-docs` to AGENTS.md primary loop.** One-line fix that eliminates the most visible inconsistency.

4. **Replace `check_uncommitted` prose with actual function.** Either extract the inline `git diff-index` pattern into a named function in `ralph-pipeline.sh`, or remove the reference from the rule.

5. **Reduce pipeline prompt size with template references.** Replace inline checklist/table format instructions in `pipeline-verify.md` and `pipeline-test.md` with references to `docs/reports/templates/` (which already exist).

---

## Overall Assessment

| Area | Grade | Notes |
|------|-------|-------|
| Script execution | A | All scripts work, error handling solid |
| Flow integration | A | Orchestrator → Pipeline → PR chain verified |
| Quality parity | A | Standard flow and Ralph Loop produce equivalent outputs |
| Skill boundaries | A | Clear, non-overlapping, well-documented |
| Documentation alignment | B+ | 95% match, 5% drift in AGENTS.md and rule files |
| Always-on context efficiency | B | Rules total 291 lines — acceptable but `subagent-policy.md` could shed ~20 lines |
| Consistency across sources | B- | Pipeline order defined in 4+ places, two "Single source of truth" conflicts |

**Verdict:** The harness is **operationally ready**. No blocking issues. The main risk is documentation drift from having pipeline order defined in multiple places — consolidation would reduce future maintenance burden.
