# Slice: foundation — Go project + core types + state reader

- Slice number: 1
- Parent plan: docs/plans/active/2026-04-15-ralph-tui/_manifest.md
- Status: Draft

## Objective

Go プロジェクトを初期化し、全依存関係を含む `go.mod` を作成する。`.harness/state/` のステートファイル (orchestrator.json, checkpoint.json, slice-*.status, slice-*.log) を読み取るパーサーとコアデータ型を実装する。

## Acceptance criteria

- [ ] `go.mod` に bubbletea v2, lipgloss v2, bubbles, fsnotify の全依存が含まれること
- [ ] `go build ./...` が成功すること
- [ ] `internal/state/types.go` に OrchestratorState, SliceState, PipelineCheckpoint, SliceDependency の型が定義されていること
- [ ] `internal/state/reader.go` が orchestrator.json を正しくパースし OrchestratorState を返すこと
- [ ] `internal/state/reader.go` が各 worktree の checkpoint.json を読み取り PipelineCheckpoint を返すこと
- [ ] `internal/state/reader.go` がスライスの依存関係をプランファイルからパースできること
- [ ] 存在しないファイルや不正な JSON に対してエラーハンドリングが機能すること
- [ ] テストカバレッジが 80% 以上であること

## Affected files

- `go.mod` (新規)
- `go.sum` (新規)
- `internal/state/types.go` (新規)
- `internal/state/reader.go` (新規)
- `internal/state/reader_test.go` (新規)
- `internal/state/testdata/` (テスト用フィクスチャ)

## Dependencies

none

## Implementation outline

1. リポジトリルートで `go mod init github.com/yoshpy-dev/harness-engineering-scaffolding-template` を実行
2. `go get` で全依存を追加: bubbletea v2, lipgloss v2, bubbles, fsnotify v1
3. `internal/state/types.go` — コアデータ型を定義:
   - `OrchestratorState` (plan, status, started, ended, slices, integration_branch)
   - `SliceState` (name, status, phase, cycle, elapsed, test_result, pr_url, pid)
   - `PipelineCheckpoint` (phase, status, inner_cycle, outer_cycle, iteration, self_review_result, verify_result, last_test_result, failure_triage, codex_triage)
   - `SliceDependency` (from, to)
   - `FullStatus` (orchestrator state + per-slice pipeline checkpoints + dependencies)
4. `internal/state/reader.go` — ステートリーダー:
   - `ReadOrchestratorState(orchDir string) (*OrchestratorState, error)`
   - `ReadSliceStatus(orchDir, sliceName string) (*SliceState, error)`
   - `ReadPipelineCheckpoint(worktreeBase, sliceName string) (*PipelineCheckpoint, error)`
   - `ReadSliceDependencies(planDir string) ([]SliceDependency, error)`
   - `ReadFullStatus(orchDir, worktreeBase, planDir string) (*FullStatus, error)`
5. `internal/state/reader_test.go` — テスト:
   - `testdata/` に orchestrator.json, checkpoint.json のサンプルを配置
   - 正常ケース、ファイル不存在、不正 JSON のテスト

## Verify plan

- Static analysis checks: `go vet ./internal/state/...`
- Spec compliance criteria to confirm: 既存の `ralph-status-helpers.sh` の JSON 出力 (455-536行) と型定義が対応していること
- Evidence to capture: `go vet` 出力

## Test plan

- Unit tests: `go test ./internal/state/...`
- Integration tests: N/A (pure data parsing)
- Edge cases: ファイル不在、空 JSON、不正フィールド、巨大ログファイルパス
- Evidence to capture: `go test -cover` レポート

## Notes

- `go.mod` に全依存を前もって追加することで、他スライスが `go.mod` を修正する必要をなくす
- 既存の `ralph-status-helpers.sh` の JSON 出力構造を正確にマッピングする
