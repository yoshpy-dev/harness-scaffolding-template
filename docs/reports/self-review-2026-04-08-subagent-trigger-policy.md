# Self-review report: Subagent Trigger Policy

- Date: 2026-04-08
- Plan: docs/plans/active/2026-04-08-subagent-trigger-policy.md
- Reviewer: reviewer subagent (Claude Sonnet 4.6)
- Scope: Diff quality only — naming, readability, unnecessary changes, typos, null safety, debug code, secrets, exception handling, security, maintainability

## Evidence reviewed

- `git diff main...HEAD` — 5 files changed: `.claude/rules/subagent-policy.md` (new, 48 lines), `CLAUDE.md` (1 line changed), `.claude/skills/work/SKILL.md` (5 lines changed), `.claude/skills/loop/SKILL.md` (5 lines changed), `docs/plans/active/2026-04-08-subagent-trigger-policy.md` (new, plan file)
- `.claude/agents/reviewer.md`, `verifier.md`, `tester.md` — confirmed agent names match the `subagent_type` values used in the diff
- `.claude/agents/planner.md`, `doc-maintainer.md` — confirmed the "Other subagents" table in `subagent-policy.md` is consistent with actual agent definitions
- `CLAUDE.md` line 14 — pre-existing text mentioning `/self-review`, `/verify`, `/test` in the pipeline (no conflict with the new line 21)

## Findings

| Severity | Area | Finding | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| MEDIUM | maintainability | `subagent-policy.md` のExecutionコードブロックは `prompt=` 引数を含む完全な呼び出し例を示しているが、`work/SKILL.md` と `loop/SKILL.md` のステップ記述では `prompt=` が省略されている。参照する側と参照される側で呼び出しの詳細度が一致しておらず、実装者がどちらを正とすべきか迷う可能性がある。 | `subagent-policy.md:20-29` に `prompt="..."` あり。`work/SKILL.md:29-31` と `loop/SKILL.md:94-96` には `prompt=` なし。 | SKILL.md 側でも `prompt` の例を短縮形で添えるか、またはポリシーファイルへの参照を強調して「詳細はポリシーを見よ」と明記する。どちらかに統一する。 |
| MEDIUM | maintainability | CLAUDE.md の line 14 に「After /work or /loop, proceed through /self-review, /verify, /test...」という旧来の記述が残っており、line 21 の新ポリシー（subagent経由）と表面上矛盾する。"proceed" は直接実行のニュアンスを持つ。 | `CLAUDE.md:14` — "proceed through /self-review, /verify, /test, then /codex-review (optional), then /pr automatically" / `CLAUDE.md:21` — "always runs via subagents" | Line 14 の "proceed through" を "delegate" などsubagent委譲を示す語に更新するか、"via subagents per subagent-policy.md" を追記する。今回のdiffでは line 14 は変更されていない。 |
| LOW | naming | `subagent-policy.md` の "Execution" セクション内コードブロックにフェンス言語タグがない（バッククォート3つのみ）。擬似コードとして意図的だが、Markdownビューアで構文ハイライトが当たらずリーダビリティがやや下がる。 | `.claude/rules/subagent-policy.md:19` — ` ``` ` のみ | `text` または `sh` (擬似コードなら `text` が適切) を追記する。 |
| LOW | readability | `work/SKILL.md` Step 9 と `loop/SKILL.md` Step 3 の (d) 項「`/codex-review` (optional, inline) → `/pr`」は、前の (a)-(c) とスタイルが異なる（`Task(...)` 呼び出し形式ではなく、スキル名のみ）。inline実行であることは意図的だが、読者が混同する可能性がある。 | `work/SKILL.md:32`, `loop/SKILL.md:97` | "(optional, inline)" の注記は残しつつ、`codex-review` と `/pr` を分けて別行にする、またはなぜ inline なのかの一言コメントを添えると明確になる。 |
| LOW | readability | `subagent-policy.md` の "Other subagents" 表の `planner` と `doc-maintainer` の Trigger 列に「Optional — inline is also acceptable.」が両エントリに重複している。表の脚注または列ヘッダで一括説明できる。 | `.claude/rules/subagent-policy.md:41-42` | 重複フレーズを表外の脚注 `_* Optional. Inline execution is also acceptable._` に移す。 |

## Positive notes

- **変更が宣言された4ファイルのみに限定されている。** 計画外のファイルへのサイドエフェクトなし。`git diff` で確認済み。
- **subagent名がエージェント定義と一致している。** `reviewer`, `verifier`, `tester` はいずれも `.claude/agents/` に対応するファイルが存在し、ポリシーと実装の間に不整合がない。
- **フォールバック規定が明示されている。** `subagent-policy.md` の "Fallback" セクションが tool error 時のインライン実行を明記しており、ポリシーが単一障害点にならないよう配慮されている。
- **`planner` と `doc-maintainer` の扱いを "Optional" として明示的に区別している。** 後段3スキルとの温度差が読者に伝わりやすい。
- **デバッグコード・秘密情報・不要な変更なし。** console.log、ハードコードされたトークン、フォーマットのみの差分は検出されなかった。

## Tech debt identified

| Debt item | Impact | Why deferred | Trigger to pay down | Related plan/report |
| --- | --- | --- | --- | --- |
| CLAUDE.md line 14 の "proceed through" 表現がsubagent委譲を明示していない | 新規読者がline 14とline 21を別のフローと解釈するリスク | 今回の変更スコープがline 21のみであり、line 14の修正は計画の非ゴール行に相当する | CLAUDE.md 次回編集時、または混乱報告が発生したとき | 本レポート |

_(上記エントリは `docs/tech-debt/README.md` にも追記すること。)_

## Recommendation

- Merge: **条件付き可** — CRITICAL / HIGH の発見なし。マージをブロックする品質上の問題はない。
- Follow-ups:
  1. (MEDIUM) `subagent-policy.md` の Execution ブロックと SKILL.md の呼び出し記述の詳細度を統一する。
  2. (MEDIUM) CLAUDE.md line 14 の "proceed through" をsubagent委譲に合わせた表現に更新する — `docs/tech-debt/README.md` に記録済み。
  3. (LOW) コードブロックにフェンス言語タグを追加する。
  4. (LOW) "Other subagents" 表の重複フレーズをリファクタリングする。
