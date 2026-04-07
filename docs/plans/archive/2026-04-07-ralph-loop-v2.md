# Ralph Loop v2: 拡張・強化

- Status: Draft
- Owner: Claude Code
- Date: 2026-04-07
- Related request: Ralph Loop フローの拡張・強化
- Related issue: N/A
- Branch: feat/ralph-loop-v2

## Objective

Ralph Loop を「実装のみの自律反復」から「実装→self-review→verify→test の品質サイクルを含む自律反復」へ進化させる。併せてコンテキスト戦略の改善とマルチエージェント並列実行の基盤を導入する。

## Scope

### Phase 1: Loop 範囲の拡張（品質サイクル内包）
- ralph-loop.sh の反復ロジックに review→verify→test フェーズを統合
- プロンプトテンプレートに品質サイクル契約を追加
- 全フェーズ完遂時にのみ COMPLETE シグナルを許可
- PR 作成はループ外（ユーザーが戻ってから /pr）に維持

### Phase 2: コンテキスト戦略の改善
- progress.log のトリミング機構（最新 N 反復のみ保持）
- 構造化ステートファイル（phase-state.json）の導入
- --allowedTools による安全なツール制限
- コスト追跡（--output-format json でトークン使用量記録）

### Phase 3: マルチエージェント並列実行
- Ralph Loop 専用のプラン分解テンプレート（スライス分解セクション付き）
- 並列ループオーケストレーター（ralph-swarm.sh）の新設
- 各スライスが独立した Worktree + Ralph Loop で実行
- 逐次マージ戦略

## Non-goals

- Agent SDK への移行（中期的方向性として記録するが scope 外）
- Agent Teams（CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS）の利用（実験的機能のため今回は使わない。claude -p ベースの独立ループで並列性を実現）
- 標準フロー（/work）の変更
- CI/CD パイプラインの変更
- Evaluator エージェント（Playwright MCP）の導入

## Assumptions

- `claude -p` は PreToolUse フックをサポートする（調査確認済み）
- Git Worktree は並列ループで安全に使用可能（各ループが独立ディレクトリで作業）
- 3-5 並列ループが現実的な上限（調整コストとディスク容量の制約）

## Affected areas

### 変更するファイル
- `scripts/ralph-loop.sh` — 品質サイクル統合、コスト追跡
- `scripts/ralph-loop-init.sh` — phase-state.json 生成追加
- `.claude/skills/loop/SKILL.md` — フロー説明更新
- `.claude/skills/loop/prompts/*.md` — 全テンプレートに品質サイクル契約追加

### 新規作成するファイル
- `scripts/ralph-swarm.sh` — 並列ループオーケストレーター
- `scripts/ralph-swarm-init.sh` — 並列ループ初期化
- `.claude/skills/loop/prompts/quality-cycle.md` — 品質サイクルのインクルード用テンプレート
- `.claude/skills/swarm/SKILL.md` — 並列ループスキル
- `docs/plans/templates/swarm-plan.md` — スライス分解用プランテンプレート

### 変更する可能性のあるファイル
- `.claude/skills/plan/SKILL.md` — フロー選択に /swarm を追加
- `CLAUDE.md` — /swarm フロー説明追加
- `AGENTS.md` — Primary loop 更新

## Acceptance criteria

### Phase 1: Loop 範囲の拡張
- [ ] ralph-loop.sh が各反復で implement → self-review → verify → test のサイクルを実行
- [ ] 品質チェック失敗時にエージェントが次反復で修正を試みる
- [ ] 全受入基準 + review pass + verify pass + test pass が揃った場合のみ COMPLETE 許可
- [ ] progress.log にフェーズごとの結果（implement/review/verify/test の pass/fail）を記録
- [ ] --no-quality-cycle フラグで旧動作に戻せる

### Phase 2: コンテキスト戦略の改善
- [ ] progress.log が最新10反復のみ保持、古いものは progress-archive.log に退避
- [ ] phase-state.json が各反復のフェーズ状態を追跡
- [ ] --output-format json によるトークン使用量が反復ログに含まれる
- [ ] --allowed-tools でエージェントのツール使用を制限可能

### Phase 3: マルチエージェント並列実行
- [ ] ralph-swarm.sh が複数 Worktree を作成し、各スライスで独立した ralph-loop.sh を並列実行
- [ ] swarm-plan.md テンプレートがスライス分解（ファイル所有権、依存関係、推定規模）を含む
- [ ] /plan のフロー選択に /swarm（並列ループ）が追加
- [ ] 各スライスの完了後に逐次マージ
- [ ] --max-parallel N（デフォルト3）で並列実行数を制限

## Implementation outline

### Phase 1: Loop 範囲の拡張

1. **品質サイクルテンプレート作成** — `.claude/skills/loop/prompts/quality-cycle.md`
   - 各反復の契約を「implement → self-review → verify → test」に拡張
   - self-review: diff を自己検査（命名、セキュリティ、不要変更）
   - verify: `./scripts/run-static-verify.sh` 実行 + 受入基準チェック
   - test: `./scripts/run-test.sh` 実行
   - 失敗時: progress.log に失敗理由を記録し、次反復で修正

2. **既存プロンプトテンプレート更新** — 全6テンプレートの Iteration contract を拡張
   - COMPLETE 条件に review/verify/test の全パスを追加

3. **ralph-loop.sh の拡張**
   - デフォルトで品質サイクルを有効化（`--no-quality-cycle` で無効化）
   - 反復後に phase-state.json を更新
   - 外部検証（run-verify.sh）の呼び出しはスクリプト側ではなくプロンプト側で制御
     （エージェント自身が review→verify→test を実行する設計）

4. **ralph-loop-init.sh の拡張**
   - phase-state.json の初期生成
   - progress-archive.log の初期化

### Phase 2: コンテキスト戦略の改善

5. **progress.log トリミング機構**
   - ralph-loop.sh 内で反復開始時に古いエントリをアーカイブ
   - 最新10反復のみ保持、それ以前は progress-archive.log へ
   - トリミング境界: `## Iteration N` ヘッダで分割

6. **phase-state.json の設計**
   ```json
   {
     "current_iteration": 5,
     "phase": "verify",
     "last_results": {
       "implement": "pass",
       "review": "pass",
       "verify": "fail",
       "test": "skipped"
     },
     "quality_cycle_complete": false,
     "total_tokens": 125000
   }
   ```

7. **コスト追跡**
   - `claude -p --output-format json` の出力から usage フィールドを抽出
   - phase-state.json の total_tokens を累積更新
   - `--max-cost` フラグで予算制限（超過時に自動停止）

8. **--allowed-tools 統合**
   - ralph-loop.sh に `--allowed-tools` オプション追加
   - デフォルト: `Read,Write,Edit,Bash,Grep,Glob`

### Phase 3: マルチエージェント並列実行

9. **swarm-plan.md テンプレート作成**
   - 標準 plan テンプレートを拡張
   - Slice decomposition セクション追加:
     ```
     | Slice | Files owned | Depends on | Size | Type |
     ```

10. **ralph-swarm-init.sh 作成**
    - swarm-plan から slice 一覧を読み取り（YAML front matter or テーブルパース）
    - 各スライスに Worktree 作成
    - 各 Worktree 内で ralph-loop-init.sh を実行
    - 依存グラフ（DAG）を解析し、実行順序を決定

11. **ralph-swarm.sh 作成**
    - DAG に基づき依存なしスライスを並列起動
    - `--max-parallel N` で同時実行数を制限
    - 各ループの status ファイルをポーリング監視
    - 完了したスライスから逐次マージ:
      1. `git checkout main && git merge <slice-branch>`
      2. 残り Worktree で `git pull --rebase origin main`
    - 全スライス完了後にサマリー出力

12. **`.claude/skills/swarm/SKILL.md` 作成**
    - /loop と同様のインタラクティブセットアップ
    - スライス分解の確認・承認フロー
    - 実行コマンドの提示

13. **/plan のフロー選択拡張**
    - 3択: 標準フロー (/work) / Ralph Loop (/loop) / 並列ループ (/swarm)
    - 大規模タスクで独立スライスに分解可能な場合に /swarm を推奨

## Verify plan

- Static analysis checks:
  - shellcheck で全 .sh スクリプトを検証
  - 既存テンプレートの構文整合性
- Spec compliance criteria:
  - 全 Acceptance criteria の達成
  - 既存 /work フローに影響がないこと
  - --no-quality-cycle での旧動作互換
- Documentation drift:
  - CLAUDE.md の /loop, /swarm 説明
  - AGENTS.md の Primary loop
  - .claude/skills/loop/SKILL.md
- Evidence to capture:
  - ralph-loop.sh --dry-run の品質サイクル動作ログ
  - ralph-swarm.sh --dry-run の並列実行ログ
  - progress.log トリミング前後比較

## Test plan

- Unit tests:
  - ralph-loop.sh --dry-run で品質サイクルの各フェーズが呼ばれること
  - progress.log トリミングが10反復を正しく保持すること
  - phase-state.json の更新が正しいこと
- Integration tests:
  - init → loop --dry-run --max-iterations 3 のフルフロー
  - swarm-init → swarm --dry-run のフルフロー
- Regression tests:
  - --no-quality-cycle が旧動作と同等
  - /work フローが影響を受けない
- Edge cases:
  - 品質サイクル内で verify が連続失敗する場合のスタック検出
  - 並列ループで1スライスが stuck の場合の挙動
  - progress.log が空の場合のトリミング
- Evidence to capture:
  - ドライラン出力ログ
  - スタック検出シミュレーション結果

## Risks and mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| 品質サイクルで反復回数が爆発 | 高（コスト増） | 中 | --max-iterations 維持 + --max-cost 予算制限 |
| 並列ループでマージ衝突 | 中（手動介入） | 中 | スライス設計時のファイル所有権明確化 |
| progress.log トリミングで情報喪失 | 低 | 低 | archive ファイルに退避 |
| ディスク容量（Worktree 複数） | 低 | 中 | --max-parallel 制限 + 完了後の Worktree 自動削除 |

## Rollout or rollback notes

- Phase 1 → Phase 2 → Phase 3 の順で段階的リリース
- 各 Phase は独立してマージ可能
- Phase 1 の `--no-quality-cycle` で旧動作に戻せる
- Phase 3 は Phase 1, 2 の完了が前提

## Open questions

- [ ] --max-cost のデフォルト値はいくらが適切か？
- [ ] 並列ループの逐次マージは自動化 or ユーザー確認を挟むべきか？
- [ ] Phase 3 の /swarm を /plan のフロー選択に統合 or 別の手動トリガーとするか？
- [ ] Clash CLI の導入は Phase 3 で必須 or オプションか？

## Progress checklist

- [x] Plan reviewed
- [x] Branch created
- [x] Phase 1: 品質サイクルテンプレート作成
- [x] Phase 1: 既存プロンプトテンプレート更新
- [x] Phase 1: ralph-loop.sh 拡張
- [x] Phase 1: ralph-loop-init.sh 拡張
- [x] Phase 2: progress.log トリミング機構
- [x] Phase 2: phase-state.json 導入
- [x] Phase 2: コスト追跡
- [x] Phase 2: --allowed-tools 統合
- [x] Phase 3: swarm-plan.md テンプレート
- [x] Phase 3: ralph-swarm-init.sh
- [x] Phase 3: ralph-swarm.sh
- [x] Phase 3: /swarm スキル
- [x] Phase 3: /plan フロー選択拡張
- [x] Documentation updated
- [x] Review artifact created
- [x] Verification artifact created
- [x] Test artifact created
- [ ] PR created
