---
name: audit-harness
description: Audit the harness itself for drift, weak spots, overgrown instructions, missing deterministic checks, or language-pack gaps. Invoke automatically when harness-level changes accumulate and need consistency review.
---
Audit the harness, not the product code alone.

## Inspect

- `AGENTS.md` and `CLAUDE.md`
- `.claude/rules/`
- `.claude/skills/` (including `/test` skill)
- `.claude/hooks/`
- `scripts/run-verify.sh`, `scripts/run-static-verify.sh`, `scripts/run-test.sh`
- `packs/languages/`
- CI and report templates

## Questions

- Is always-on context too large?
- Are there rules that should become scripts, tests, or hooks?
- Are there repeated review comments that justify automation?
- Are there missing language packs or pack-specific verifiers?
- Are reports and plans actually helping, or only adding ceremony?
- Is the harness complexity still justified by the current task and model quality?
- Do `/self-review`, `/verify`, and `/test` have clear non-overlapping responsibilities?

## Quality gate alignment

Check whether `docs/quality/` still matches reality:

- Does `docs/quality/definition-of-done.md` reflect the actual completion workflow? Compare against `/work`, `/self-review`, `/verify`, `/test`, and `/pr` skill steps.
- Does `docs/quality/quality-gates.md` list the verifiers and CI checks that actually exist in `scripts/` and `.github/workflows/`?
- Are there new verification tools, linters, or test frameworks in use that are not mentioned in the quality gates?
- Are there gates listed that no longer apply or have been removed?

If drift is found, update the quality docs or flag them in the audit memo.

## Output

Write a short audit memo with:
- strengths
- pain points
- missing guardrails
- proposed promotions from prose to code
- simplifications worth trying

## CLI 別実行ガイダンス

このスキルは Claude Code と Codex の両方で動作する。実行モードは AGENTS.md と
`.codex/AGENTS.override.md` の規約に従う。

| 観点 | Claude Code | Codex |
|------|-------------|-------|
| Skill 起動 | `/skill-name` slash command | `$skill-name` mention または `/skills` メニュー (`/skill-name` 形式は built-in 衝突のため使わない) |
| Skill 本体パス | `.claude/skills/<name>/SKILL.md` | `.agents/skills/<name>/SKILL.md` |
| サブエージェント | `Task(subagent_type=...)` で並列呼び出し可 | 順次 inline 実行 — 単一 agent 内で連続実行 |
| 構造化対話 | `AskUserQuestion` | 番号付き選択肢を stdout に出して数字を待機 |
| 成果物 | `docs/reports/`, `docs/plans/`, `docs/specs/` 共通 | 同左 (CLI 非依存) |

drift check (`./scripts/check-skill-sync.sh`) は両側の本文と起動メタデータを
照合する — 片側だけ編集すると CI で fail する。
