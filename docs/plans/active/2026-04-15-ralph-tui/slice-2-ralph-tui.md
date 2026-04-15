# Slice: watcher — File watcher + real-time updates

- Slice number: 2
- Parent plan: docs/plans/active/2026-04-15-ralph-tui/_manifest.md
- Status: Draft

## Objective

fsnotify を使用して `.harness/state/` ディレクトリのファイル変更を監視し、Bubble Tea の `tea.Cmd` / `tea.Msg` として非同期にステータス更新を配信する仕組みを実装する。選択スライスのログファイルの末尾追従 (tail -f 相当) も提供する。

## Acceptance criteria

- [ ] `internal/watcher/watcher.go` が `.harness/state/orchestrator/` と worktree 内の `checkpoint.json` を監視できること
- [ ] ファイル変更時に `StateChangedMsg` が Bubble Tea のメッセージチャネルに送信されること
- [ ] ログファイルの末尾追従が動作し、新しい行が追加されると `LogLineMsg` として配信されること
- [ ] 監視対象ファイルが存在しない場合にパニックせず graceful にスキップすること
- [ ] `watcher.Stop()` でクリーンアップが行われること
- [ ] ポーリングフォールバック (5秒間隔) が利用可能なこと
- [ ] テストカバレッジが 80% 以上であること

## Affected files

- `internal/watcher/watcher.go` (新規)
- `internal/watcher/tailer.go` (新規)
- `internal/watcher/messages.go` (新規)
- `internal/watcher/watcher_test.go` (新規)

## Dependencies

slice-1

## Implementation outline

1. `internal/watcher/messages.go` — Bubble Tea メッセージ型を定義:
   - `StateChangedMsg` (変更されたファイルパス、変更種別)
   - `LogLineMsg` (スライス名、行内容)
   - `WatcherErrorMsg` (エラー内容)
2. `internal/watcher/watcher.go`:
   - `type Watcher struct` — fsnotify.Watcher のラッパー
   - `New(orchDir, worktreeBase string) (*Watcher, error)` — 監視ディレクトリを設定
   - `Watch() tea.Cmd` — fsnotify イベントを tea.Msg に変換する Cmd を返す
   - `Stop() error` — リソースクリーンアップ
   - fsnotify 失敗時は time.Ticker ベースのポーリングにフォールバック
3. `internal/watcher/tailer.go`:
   - `type Tailer struct` — ログファイル末尾追従
   - `NewTailer(filepath string) (*Tailer, error)` — ファイルオープン + seek to end
   - `Tail() tea.Cmd` — 新しい行を LogLineMsg として配信
   - `SwitchFile(filepath string) error` — 監視対象ログファイルを切り替え
   - `Stop()` — クリーンアップ
4. テスト: 一時ファイルを作成→変更→メッセージ受信を確認

## Verify plan

- Static analysis checks: `go vet ./internal/watcher/...`
- Spec compliance criteria to confirm: fsnotify + ポーリングフォールバックが仕様通り
- Evidence to capture: `go vet` 出力

## Test plan

- Unit tests: `go test ./internal/watcher/...`
- Integration tests: 一時ディレクトリでファイル作成→変更→watcher がメッセージを生成
- Edge cases: 監視対象ディレクトリ不在、ファイル削除、高速な連続書き込み
- Evidence to capture: `go test -cover` レポート

## Notes

- ポーリングフォールバックは macOS での fsnotify の制限に備える安全策
- tailer は内部バッファ (4KB) で改行区切りで行を配信する
