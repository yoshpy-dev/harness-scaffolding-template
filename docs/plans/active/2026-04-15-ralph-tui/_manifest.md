# ralph-tui

- Status: Draft
- Owner: Claude Code
- Date: 2026-04-15
- Related request: docs/specs/2026-04-15-ralph-tui.md
- Related issue: N/A
- Branch: feat/ralph-tui
- Integration branch: integration/ralph-tui
- Execution: Ralph Loop (parallel slices)

## Objective

`ralph status` コマンドを Lazygit 風の4ペイン TUI に拡張する。Go + Bubble Tea で実装し、スライスの状態確認・ログ追跡・再試行/アボート操作をひとつの画面で完結させる。

## Scope

- Go バイナリ `ralph-tui` の新規作成 (`cmd/ralph-tui/`)
- 内部パッケージ: `internal/state/`, `internal/watcher/`, `internal/ui/`, `internal/action/`
- `scripts/ralph` の `cmd_status()` への TUI 起動ロジック追加
- `scripts/build-tui.sh` ビルドスクリプト
- `go.mod` / `go.sum`

## Non-goals

- Web UI
- パイプラインロジックの変更
- `ralph run` / `ralph abort` の Go 完全移植
- カスタムテーマ / カラースキーム設定
- CI/CD 環境での TUI 実行

## Assumptions

- Go 1.22+ がビルド環境で利用可能
- 既存の `.harness/state/` ディレクトリ構造は変更しない
- TUI は既存シェルスクリプトを `exec.Command` で呼び出す（新規コマンド実装はしない）
- macOS と Linux を主要ターゲットとする

## Affected areas

- `cmd/ralph-tui/` (新規)
- `internal/state/` (新規)
- `internal/watcher/` (新規)
- `internal/ui/` (新規)
- `internal/action/` (新規)
- `scripts/ralph` (status サブコマンド修正)
- `scripts/build-tui.sh` (新規)
- `go.mod` / `go.sum` (新規)

## Shared-file locklist

Files that must not be modified by parallel slices simultaneously.

- `go.mod` (slice-1 で全依存を追加。他スライスは修正不要)
- `go.sum` (slice-1 で生成。他スライスは修正不要)
- `scripts/ralph` (slice-6 のみ修正)

## Dependency graph

```
slice-1 (foundation) ──→ slice-2 (watcher)
slice-1 (foundation) ──→ slice-3 (layout)
slice-3 (layout)     ──→ slice-4 (panes)
slice-3 (layout)     ──→ slice-5 (actions)
slice-2, slice-4, slice-5 ──→ slice-6 (integration)
```

Parallel waves:
- Wave 1: slice-1
- Wave 2: slice-2, slice-3 (parallel)
- Wave 3: slice-4, slice-5 (parallel)
- Wave 4: slice-6

## Integration-level verify plan

- Static analysis checks: `go vet ./...`, `go build ./...` が成功すること
- Spec compliance criteria to confirm:
  - 4ペインレイアウトが仕様通りの配置であること
  - 全キーバインド (h/j/k/l/Space/Tab/r/a/A/L/e/d/?//) が実装されていること
  - `--no-tui`, `--json` フラグが既存動作を壊さないこと
  - TTY 検出フォールバックが動作すること
- Documentation drift to check: AGENTS.md, CLAUDE.md に TUI 関連の記述追加は不要（スコープ外のため）
- Evidence to capture: `go vet` 出力、`go build` 成功ログ、バイナリサイズ

## Integration-level test plan

- Unit tests: `go test ./...` — state parser, watcher, pane models, action executor
- Integration tests: TUI 起動→キー入力→画面遷移のシナリオ（`teatest` 使用）
- Regression tests: `ralph status --json` の出力が変更前と同一であること
- Edge cases:
  - `.harness/state/orchestrator/` が存在しない場合の graceful エラー
  - 0 スライスの場合の空表示
  - 巨大ログファイル (>10MB) のメモリ制限
  - ターミナルサイズが極小 (e.g., 40x10) の場合のレイアウト崩壊防止
- Evidence to capture: `go test -cover` カバレッジレポート、テスト通過ログ

## Risks and mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Bubble Tea v2 API が不安定 | HIGH | v2 の安定リリースを確認、v1 フォールバックプランを用意 |
| fsnotify が macOS で大量 watch に弱い | MEDIUM | ポーリングフォールバック (5秒間隔) を実装 |
| Go バイナリサイズが大きい | LOW | `go build -ldflags="-s -w"` でストリップ、UPX は不要 |
| 既存 `ralph status` のリグレッション | HIGH | `--no-tui` / `--json` パスを変更前と同一に保つ |
| retry がオーケストレータを迂回する (Codex #1) | HIGH | TUI は `scripts/ralph retry` CLI 経由で実行。CLI 側で PID/status/locklist/並列制限を検証 |
| abort が二重実装になる (Codex #2) | HIGH | TUI は `scripts/ralph abort --slice` CLI 経由で実行。既存フロー（アーカイブ・監査ログ）を完全再利用 |
| 古いバイナリが暗黙的にデフォルトになる (Codex #3) | MEDIUM | ソースファイルの mtime がバイナリより新しい場合は警告を表示してテーブル出力にフォールバック |

## Rollout or rollback notes

- ロールアウト: Go バイナリが存在しなければ既存シェル出力にフォールバック。段階的導入可能。
- ロールバック: `scripts/ralph` の TUI 分岐を削除するだけで完全に元に戻る。

## Open questions

1. Go バイナリの配布方法（`go install` / プリビルド / ソースビルド）— 初期は `scripts/build-tui.sh` でソースビルドとする
2. `teatest` によるインテグレーションテストの深度 — 基本シナリオのみ (起動、ペイン移動、終了)

## Progress checklist

- [ ] Plan reviewed
- [ ] Slices defined and dependencies mapped
- [ ] Shared-file locklist finalized
- [ ] Integration branch created
- [ ] Pipeline execution started
- [ ] All slices complete
- [ ] Sequential merge to integration branch passed
- [ ] Integration-level verification passed
- [ ] Unified PR created
