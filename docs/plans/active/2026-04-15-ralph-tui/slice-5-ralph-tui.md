# Slice: actions — Actions + command execution + confirmation dialogs

- Slice number: 5
- Parent plan: docs/plans/active/2026-04-15-ralph-tui/_manifest.md
- Status: Draft

## Objective

アクションパネルのコンポーネントと、各アクション (retry, abort, log pager, editor open) のコマンド実行ロジックを実装する。破壊的操作には確認ダイアログを表示する。全操作は既存の `scripts/ralph` CLI 経由で実行し、オーケストレータのコントロールプレーンを迂回しない。

## Acceptance criteria

- [ ] アクションパネルに利用可能なアクションがキーバインド付きで表示されること
- [ ] `r` で stuck/failed スライスの再試行が `scripts/ralph retry <slice-name>` 経由で実行されること
- [ ] running/complete スライスに対して `r` が無効化されていること
- [ ] `a` で選択スライスのアボートが `scripts/ralph abort --slice <slice-name>` 経由で確認ダイアログ付きで実行されること
- [ ] `A` で全スライスのアボートが `scripts/ralph abort` 経由で確認ダイアログ付きで実行されること
- [ ] `L` で `$PAGER` (or `less`) にログファイルパスを渡してページャーが起動すること
- [ ] `e` で `$EDITOR` に worktree パスを渡してエディタが起動すること
- [ ] 確認ダイアログで `y`/`Enter` で承認、`n`/`Esc` でキャンセルが動作すること
- [ ] コマンド実行の成功/失敗がステータスバーに表示されること
- [ ] テストカバレッジが 80% 以上であること

## Affected files

- `internal/action/executor.go` (新規)
- `internal/action/retry.go` (新規)
- `internal/action/abort.go` (新規)
- `internal/action/external.go` (新規)
- `internal/ui/panes/actions.go` (新規)
- `internal/ui/confirm.go` (新規)
- `internal/action/executor_test.go` (新規)
- `internal/ui/panes/actions_test.go` (新規)
- `internal/ui/confirm_test.go` (新規)

## Dependencies

slice-3

## Implementation outline

1. `internal/action/executor.go` — コマンド実行の共通ロジック:
   - `type Executor struct` (repoRoot, ralphPath string)
   - `NewExecutor(repoRoot string) *Executor` — `scripts/ralph` のパスを解決
   - `RunRalph(args ...string) tea.Cmd` — `scripts/ralph` サブコマンドを非同期実行し結果を `tea.Msg` で返す
   - 引数サニタイズ: パストラバーサル防止
   - **Codex 指摘対応**: 直接 `ralph-pipeline.sh` を呼ばず、必ず `scripts/ralph` CLI 経由にすることでオーケストレータの状態管理を維持
2. `internal/action/retry.go`:
   - `func (e *Executor) RetrySlice(sliceName string) tea.Cmd`
   - `scripts/ralph retry <slice-name>` を呼び出す（slice-6 で新設する CLI サブコマンド）
   - オーケストレータが PID/status/locklist/並列制限を管理する
   - 結果を `RetryResultMsg` として送信
3. `internal/action/abort.go`:
   - `func (e *Executor) AbortSlice(sliceName string) tea.Cmd` — `scripts/ralph abort --slice <slice-name>` を呼び出す
   - `func (e *Executor) AbortAll() tea.Cmd` — `scripts/ralph abort` を呼び出す
   - **Codex 指摘対応**: 独自の SIGTERM/status 更新ロジックを持たない。既存の abort フロー（アーカイブ・worktree 削除・監査ログ）を完全に再利用
   - 結果を `AbortResultMsg` として送信
4. `internal/action/external.go`:
   - `func (e *Executor) OpenPager(logPath string) tea.Cmd` — `tea.ExecProcess` で $PAGER を起動
   - `func (e *Executor) OpenEditor(worktreePath string) tea.Cmd` — `tea.ExecProcess` で $EDITOR を起動
5. `internal/ui/confirm.go` — 確認ダイアログ:
   - `type ConfirmModel struct` (message, confirmed, visible)
   - `y`/`Enter` → `ConfirmYesMsg`、`n`/`Esc` → `ConfirmNoMsg`
   - 半透明オーバーレイ風にレンダリング
6. `internal/ui/panes/actions.go`:
   - `type ActionsModel struct` — アクションパネル
   - 選択スライスのステータスに応じて利用可能なアクションを動的に表示
   - stuck/failed: `[r] Retry  [a] Abort  [L] Logs  [e] Editor`
   - running: `[a] Abort  [L] Logs  [e] Editor`
   - complete: `[L] Logs  [e] Editor`
   - pending: `(no actions available)`

## Verify plan

- Static analysis checks: `go vet ./internal/action/... ./internal/ui/...`
- Spec compliance criteria to confirm:
  - 全操作が `scripts/ralph` CLI 経由であること（直接 `ralph-pipeline.sh` を呼ばない）
  - 破壊的操作 (retry, abort) に必ず確認ダイアログがあること
  - `$EDITOR` / `$PAGER` のコマンドインジェクション対策
- Evidence to capture: `go vet` 出力

## Test plan

- Unit tests:
  - executor: コマンド構築テスト (実際のコマンド実行はモック)
  - retry: RetrySlice が `scripts/ralph retry <name>` を呼ぶこと
  - abort: AbortSlice が `scripts/ralph abort --slice <name>` を呼ぶこと、AbortAll が `scripts/ralph abort` を呼ぶこと
  - confirm: y/n/Enter/Esc の遷移テスト
  - actions: ステータスに応じたアクション表示テスト
- Edge cases: $EDITOR 未設定、$PAGER 未設定 (less フォールバック)、scripts/ralph が見つからない
- Evidence to capture: `go test -cover` レポート

## Notes

- `tea.ExecProcess` で外部コマンドを起動すると TUI が一時サスペンドされ、コマンド終了後に復帰する
- コマンドインジェクション対策: `exec.Command` に直接引数を渡す (シェル経由しない)
- **Codex advisory 反映**: retry/abort の両方とも既存 CLI のサブコマンドとして実装（slice-6 で新設）し、TUI はそれを呼ぶだけの薄いラッパーとする
