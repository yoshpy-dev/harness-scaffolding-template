# Walkthrough: Ralph Loop v2 — 完全自律開発パイプライン

Date: 2026-04-09
Plan: docs/plans/active/2026-04-09-ralph-loop-v2.md

## 変更概観

33ファイル、+4082/-25行。4つのフェーズで構成。

## Phase 1: フルパイプラインオーケストレータ

### `scripts/ralph-pipeline.sh` (新規, 783行)
Inner/Outer Loop アーキテクチャの中核。

- **Inner Loop** (line 300-489): `implement → self-review → verify → test` サイクル
  - `run_claude()` で `claude -p` を呼び出し、実装エージェントを起動
  - テスト失敗時は `failure_triage` に仮説を記録して再試行
  - `MAX_REPAIR_ATTEMPTS` (default 5) で修復上限
- **Outer Loop** (line 495-600): `sync-docs → codex-review → PR`
  - codex トリアージで ACTION_REQUIRED があれば Inner Loop に差し戻し
  - 全件 DISMISSED で自動 PR 作成
- **Preflight probe** (line 100-215): `claude -p` の動作を事前検証
- **Hook parity** (line 132-178): `claude -p` で hooks が動かない問題の代替チェック
- **Stuck detection** (line 180-199): HEAD コミットハッシュ比較で進捗検出（Codex 修正後）
- **Checkpoint** (line 60-95): `checkpoint.json` で構造化状態管理

### `scripts/ralph-loop-init.sh` (変更)
`--pipeline` フラグを追加。パイプラインモード時は `.harness/state/pipeline/` にテンプレートをコピーし、`pipeline.json` メタデータを生成。

### `.claude/skills/loop/prompts/` (新規, 3ファイル)
- `pipeline-inner.md`: 実装エージェント用プロンプト（`__OBJECTIVE__`, `__PLAN_PATH__` テンプレート変数）
- `pipeline-review.md`: レビュー/検証/テスト用プロンプト
- `pipeline-outer.md`: ドキュメント同期/codex-review/PR 用プロンプト

## Phase 2: コンテキスト戦略

`ralph-pipeline.sh` 内に統合:
- Preflight probe が `claude -p` の capabilities を検証（CLAUDE.md 読み込み、`--continue`、`--append-system-prompt`）
- セッション ID をキャプチャし `--resume` で前イテレーションを継続
- `checkpoint.json` で phase transitions、failure triage、codex triage を構造化保存

## Phase 3: マルチエージェント並列開発

### `scripts/ralph-orchestrator.sh` (新規, 589行)
- **Plan parsing** (line 72-165): スライス定義、locklist、共有ファイル自動検出
- **Worktree management** (line 200-280): スライスごとの Git worktree 作成/削除
- **Dependency-aware execution** (line 455-534): 依存グラフに基づく順序制御
- **Locklist conflict detection** (line 495-501): 共有ファイルのロック管理（Codex 修正でクリーンアップ追加）
- **Integration merge check** (line 330-370): 全スライス完了後のマージ衝突検出

### `docs/plans/templates/ralph-loop-plan.md` (新規)
垂直スライス定義、共有ファイル locklist、依存グラフを含む Ralph Loop 専用計画テンプレート。

## Phase 4: CLI 統合

### `scripts/ralph` (新規, 360行)
サブコマンド:
- `plan`: アクティブプランの一覧表示
- `run`: プラン自動検出 → パイプラインまたはオーケストレータに委譲
- `status`: checkpoint.json、orchestrator 状態、worktree 一覧を表示
- `abort`: プロセス停止 → 状態アーカイブ → worktree 削除 → 監査ログ生成

## ドキュメント・ルール更新

- `CLAUDE.md`, `AGENTS.md`: パイプラインモードと ralph CLI の参照追加
- `.claude/skills/loop/SKILL.md`: パイプラインモード選択ステップ追加
- `.claude/rules/subagent-policy.md`: パイプライン/オーケストレータモードのポリシー追加
- `.claude/rules/git-commit-strategy.md`: パイプラインモードのコミット戦略追加
- `README.md`, `docs/recipes/ralph-loop.md`, `docs/architecture/repo-map.md`: 更新

## Codex レビュー修正 (2ラウンド)

### Round 1 (self-review)
- テンプレートプレースホルダーリーク修正（raw → substituted テンプレート優先）
- POSIX pipe-subshell 変数スコープバグ修正（3箇所、temp file ベースに変更）

### Round 2 (Codex review)
- `--resume` ロジック修正（OR → AND 条件）
- stuck 検出改善（`git diff HEAD` → `git rev-parse HEAD` 比較）
- locklist `.running_files` クリーンアップ（毎サイクル再構築）
- COMPLETE シグナルが verify/test をバイパスしない修正
- `log_error` 関数未定義の修正

## 既知の tech debt

- `ralph-orchestrator.sh` の pipe-subshell 残存箇所（abort worktree リスト）
- CRITICAL self-review 発見を無視するポリシーの AGENTS.md 契約との矛盾
