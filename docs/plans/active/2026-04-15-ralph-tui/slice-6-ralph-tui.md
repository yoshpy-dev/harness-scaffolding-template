# Slice: integration — CLI integration + build + main + new subcommands

- Slice number: 6
- Parent plan: docs/plans/active/2026-04-15-ralph-tui/_manifest.md
- Status: Draft

## Objective

`cmd/ralph-tui/main.go` エントリポイントを作成し、全コンポーネント (state reader, watcher, UI, actions) を統合する。`scripts/ralph` に TUI 起動ロジック・`retry` サブコマンド・`abort --slice` フラグを追加し、`scripts/build-tui.sh` ビルドスクリプトを提供する。バイナリにバージョン情報を埋め込み、古いバイナリの暗黙的使用を防止する。

## Acceptance criteria

- [ ] `cmd/ralph-tui/main.go` が全コンポーネントを初期化し `tea.NewProgram` で TUI を起動すること
- [ ] `go build -o bin/ralph-tui ./cmd/ralph-tui` で単一バイナリが生成されること
- [ ] バイナリサイズが 30MB 以下であること (`-ldflags="-s -w"` 適用)
- [ ] バイナリに `--version` フラグがあり、ビルド時の git commit hash を表示すること
- [ ] `scripts/ralph` の `cmd_status()` に `--no-tui` フラグが追加されていること
- [ ] TTY 検出: TTY + バイナリ存在 + `--no-tui` 未指定 → TUI 起動
- [ ] 非 TTY または `--no-tui` → 既存テーブル出力
- [ ] `--json` → 既存 JSON 出力 (TUI に影響しない)
- [ ] TUI バイナリが存在しない場合に既存出力にフォールバックすること
- [ ] TUI バイナリが Go ソースより古い場合に警告を表示してからフォールバックすること
- [ ] `scripts/ralph retry <slice-name>` サブコマンドが新設されていること
- [ ] `retry` がオーケストレータの PID/status/locklist/並列制限を検証してから `ralph-pipeline.sh --resume` を実行すること
- [ ] `scripts/ralph abort --slice <slice-name>` フラグが追加されていること
- [ ] `abort --slice` が既存の abort フロー（アーカイブ・監査ログ）を単一スライスに限定して実行すること
- [ ] `scripts/build-tui.sh` が `go build` を実行し `bin/ralph-tui` にバイナリを配置すること
- [ ] `.gitignore` に `bin/` が追加されていること

## Affected files

- `cmd/ralph-tui/main.go` (新規)
- `cmd/ralph-tui/version.go` (新規)
- `scripts/ralph` (修正: cmd_status に TUI 分岐、cmd_retry 新設、cmd_abort に --slice 追加)
- `scripts/build-tui.sh` (新規)
- `.gitignore` (修正: bin/ 追加)

## Dependencies

slice-2, slice-4, slice-5

## Implementation outline

1. `cmd/ralph-tui/version.go`:
   - `var Version, GitCommit, BuildDate string` — `ldflags` で注入
   - `--version` フラグで `ralph-tui vX.Y.Z (commit: abc1234, built: 2026-04-15)` を表示
2. `cmd/ralph-tui/main.go`:
   - フラグパース: `--orch-dir`, `--worktree-base`, `--plan-dir`, `--version`
   - `state.ReadFullStatus()` で初期データ読み込み
   - `watcher.New()` でファイル監視開始
   - `action.NewExecutor()` でコマンド実行者初期化
   - `ui.NewModel()` に state, watcher, executor を注入
   - `tea.NewProgram(model, tea.WithAltScreen())` で起動
   - 終了時に `watcher.Stop()` でクリーンアップ
3. `scripts/ralph` の `cmd_status()` 修正:
   - `--no-tui` フラグを追加
   - **Codex 指摘対応 — 古いバイナリの検出**:
     ```
     if [ "$_json_mode" -eq 1 ]; then → 既存 JSON 出力
     elif [ "$_no_tui" -eq 1 ]; then → 既存テーブル出力
     elif [ -t 1 ] && [ -x "${SCRIPT_DIR}/../bin/ralph-tui" ]; then
       # ソースファイルがバイナリより新しければ警告してフォールバック
       _newest_src="$(find "${SCRIPT_DIR}/../cmd" "${SCRIPT_DIR}/../internal" -name '*.go' -newer "${SCRIPT_DIR}/../bin/ralph-tui" 2>/dev/null | head -1)"
       if [ -n "$_newest_src" ]; then
         echo "Warning: bin/ralph-tui is outdated. Run scripts/build-tui.sh to rebuild." >&2
         → 既存テーブル出力
       else
         → TUI 起動
       fi
     else → 既存テーブル出力
     fi
     ```
   - TUI 起動: `exec "${SCRIPT_DIR}/../bin/ralph-tui" --orch-dir "$ORCH_STATE" --worktree-base "$WORKTREE_BASE"`
   - `--watch` は TUI モード時は無視 (TUI 自体がリアルタイム)
4. `scripts/ralph` に `cmd_retry()` 新設:
   - **Codex 指摘対応**: オーケストレータの状態を経由する retry パス
   - 引数: スライス名
   - 処理:
     a. `slice-<name>.status` を確認 → stuck/failed/repair_limit/max_* 以外はエラー
     b. locklist 競合チェック (現在 running のスライスとの重複)
     c. 並列数チェック (`MAX_PARALLEL` 以下か)
     d. 依存関係チェック (全依存が complete か)
     e. status を `running` に更新、PID ファイルを作成
     f. worktree 内で `ralph-pipeline.sh --resume` をバックグラウンド実行
     g. PID をファイルに記録
5. `scripts/ralph` の `cmd_abort()` に `--slice <name>` フラグ追加:
   - **Codex 指摘対応**: 既存 abort フロー（アーカイブ・worktree 削除・監査ログ）を単一スライスに適用
   - `--slice` 未指定時は既存の全体 abort 動作を維持
   - 処理: PID 停止 → 状態アーカイブ → status 更新 → 監査ログ書き込み (既存ロジックの再利用)
6. `scripts/build-tui.sh`:
   - Go バージョン確認 (1.22+)
   - git commit hash を取得: `_commit="$(git rev-parse --short HEAD)"`
   - `go build -ldflags="-s -w -X main.GitCommit=${_commit} -X main.BuildDate=$(date -u +%Y-%m-%dT%H:%M:%SZ)" -o bin/ralph-tui ./cmd/ralph-tui`
   - ビルド成功/失敗のメッセージ表示
   - `chmod +x bin/ralph-tui`
7. `.gitignore` に `bin/` を追加

## Verify plan

- Static analysis checks: `go vet ./cmd/ralph-tui/...`, `go build ./...`
- Spec compliance criteria to confirm:
  - `ralph status` → TUI (TTY + バイナリ存在 + ソースより新しい)
  - `ralph status` → 警告 + テーブル出力 (バイナリがソースより古い)
  - `ralph status --json` → JSON 出力 (変更前と同一)
  - `ralph status --no-tui` → テーブル出力 (変更前と同一)
  - `ralph status` (非 TTY) → テーブル出力
  - バイナリ不在 → テーブル出力
  - `ralph retry <slice>` → オーケストレータ経由の retry
  - `ralph abort --slice <slice>` → 単一スライス abort
- Evidence to capture: バイナリサイズ、ビルドログ、`--version` 出力

## Test plan

- Unit tests: `go test ./cmd/ralph-tui/...` — フラグパース、初期化ロジック
- Integration tests:
  - `scripts/build-tui.sh` が正常にビルドを完了すること
  - `ralph status --json` の出力が変更前と同一であること (regression)
  - `ralph status --no-tui` が既存テーブル出力を返すこと
  - `ralph retry` が status 確認・locklist・並列数・依存関係をチェックすること
  - `ralph abort --slice <name>` が単一スライスのみをアボートすること
- Edge cases:
  - Go 未インストール環境での build-tui.sh エラーメッセージ
  - bin/ ディレクトリ不在
  - retry 対象が running の場合にエラーを返すこと
  - retry 時に locklist 競合がある場合にエラーを返すこと
- Evidence to capture: `go test -cover` レポート、regression 出力の diff

## Notes

- `scripts/ralph` の変更は3箇所: (1) cmd_status に TUI 分岐 (2) cmd_retry 新設 (3) cmd_abort に --slice 追加
- `--watch` + TUI は冗長なので、TUI モード時は `--watch` を無視してログに警告を出す
- **Codex advisory 反映**:
  - retry はオーケストレータの制御プレーン経由 (PID/status/locklist/並列制限を検証)
  - abort は既存フローを再利用 (アーカイブ・worktree 削除・監査ログ)
  - 古いバイナリの自動検出と警告
