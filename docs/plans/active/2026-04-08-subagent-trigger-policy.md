# Subagent Trigger Policy

- Status: Draft
- Owner: Claude Code
- Date: 2026-04-08
- Related request: 後段パイプライン（/self-review, /verify, /test）を常にsubagentで実行するようにトリガー条件を明確化する
- Related issue: N/A
- Branch: refactor/subagent-trigger-policy

## Objective

後段パイプラインの3スキル（`/self-review`, `/verify`, `/test`）を、対応するsubagent（`reviewer`, `verifier`, `tester`）経由で常に実行するよう明確なポリシーを導入する。現在の「裁量ベース」から「デフォルトsubagent委譲」へ移行する。

## Scope

- CLAUDE.md のsubagentガイダンスを明確化
- `/work` SKILL.md の後段パイプライン呼び出し指示を更新
- `/loop` SKILL.md の「After the loop」セクションを更新
- 新規ルールファイル `.claude/rules/subagent-policy.md` を作成

## Non-goals

- subagent定義ファイル（`.claude/agents/*.md`）の変更（現在の定義は適切）
- 各スキルのSKILL.md内のロジック変更（スキル自体の振る舞いは変えない）
- `/plan` や `/pr` のsubagent化（これらはメインコンテキストで実行すべき）
- doc-maintainer subagentのトリガー条件（sync-docsは明示的に呼ばれる性質のため今回はスコープ外）

## Assumptions

- Claude Code の Task tool が `.claude/agents/*.md` のカスタムagent定義を `subagent_type` として利用できる
- subagent実行はメインコンテキストのトークンを節約する効果がある
- 後段パイプラインの3ステップは互いに独立しているわけではなく、順序依存がある（self-review → verify → test）

## Affected areas

| ファイル | 変更内容 |
|---------|---------|
| `CLAUDE.md` | subagentガイダンス行を明確なポリシーに書き換え |
| `.claude/rules/subagent-policy.md` | 新規：subagent委譲ポリシーの単一参照元 |
| `.claude/skills/work/SKILL.md` | Step 9 の後段パイプライン指示にsubagent委譲を明記 |
| `.claude/skills/loop/SKILL.md` | 「After the loop」セクションにsubagent委譲を明記 |

## Acceptance criteria

- [ ] AC1: `.claude/rules/subagent-policy.md` が存在し、後段3スキルのsubagent委譲ルールが明文化されている
- [ ] AC2: CLAUDE.md のsubagent行が新ポリシーを参照する形に更新されている
- [ ] AC3: `/work` SKILL.md のStep 9が `reviewer`, `verifier`, `tester` subagentの利用を指示している
- [ ] AC4: `/loop` SKILL.md の「After the loop」が同様にsubagent利用を指示している
- [ ] AC5: 各subagent定義（`.claude/agents/*.md`）は変更されていない

## Implementation outline

1. `.claude/rules/subagent-policy.md` を新規作成
   - 後段パイプラインのsubagent委譲ルールを定義
   - インライン実行が許容されるケース（もしあれば）を明記
2. `CLAUDE.md` のLine 21を更新
   - 曖昧な「when they clearly reduce context pressure」を具体的なポリシー参照に変更
3. `.claude/skills/work/SKILL.md` のStep 9を更新
   - 「proceed to /self-review, /verify, /test」を「delegate to reviewer, verifier, tester subagents」に変更
4. `.claude/skills/loop/SKILL.md` の「After the loop」セクションを更新
   - 同様にsubagent委譲を明記

## Verify plan

- Static analysis checks: ShellCheck on any modified shell scripts (なし — .md のみ)
- Spec compliance criteria to confirm:
  - 全ACが充足されている
  - subagent定義ファイルが未変更
  - CLAUDE.md → subagent-policy.md → skills の参照チェーンが一貫している
- Documentation drift to check:
  - AGENTS.md の「Primary loop」セクションとの整合性
  - `docs/quality/definition-of-done.md` との整合性
- Evidence to capture: git diff showing only the expected files changed

## Test plan

- Unit tests: N/A（設定ファイルのみの変更）
- Integration tests: N/A
- Regression tests: 既存のスキル/エージェント定義が破壊されていないことを確認
- Edge cases: N/A
- Evidence to capture: `run-verify.sh` 実行結果

## Risks and mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| subagent実行が失敗した場合のフォールバックがない | 後段パイプラインが止まる | ポリシーに「subagent失敗時はインラインで実行」のフォールバック規定を追加 |
| 小さな変更でもsubagent起動のオーバーヘッドがかかる | 軽微な変更での非効率 | ポリシーに「trivial changes（1ファイル・10行以下）はインライン可」の除外規定を検討 |

## Rollout or rollback notes

- .md ファイルのみの変更なので即座にロールバック可能
- git revert で1コミットで戻せる

## Open questions

- trivial changesの除外規定を設けるか、それとも常にsubagentにするか → シンプルさ優先で「常にsubagent」とし、問題が出たら除外規定を追加する方針

## Progress checklist

- [x] Plan reviewed
- [x] Branch created
- [x] Implementation started
- [x] Review artifact created
- [x] Verification artifact created
- [x] Test artifact created
- [ ] PR created
