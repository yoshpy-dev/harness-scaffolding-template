# Slice: layout — TUI framework + pane management + keybindings

- Slice number: 3
- Parent plan: docs/plans/active/2026-04-15-ralph-tui/_manifest.md
- Status: Draft

## Objective

Bubble Tea + Lip Gloss で4ペインレイアウトのフレームワークを構築する。ペイン間のフォーカス管理 (h/l/Tab)、キーバインド定義、ヘルプオーバーレイ、ターミナルリサイズ対応を実装する。各ペインの中身はプレースホルダーとし、Slice 4/5 で実装する。

## Acceptance criteria

- [ ] `internal/ui/model.go` に Bubble Tea の `Model` (Init/Update/View) が定義されていること
- [ ] Lip Gloss で4ペイン + プログレスバーのレイアウトが描画されること
- [ ] h/l キーでペイン間のフォーカスが移動すること
- [ ] Tab/Shift+Tab でペインの順送り/逆送りが動作すること
- [ ] フォーカス中のペインにボーダーハイライトが適用されること
- [ ] `?` キーでヘルプオーバーレイが表示/非表示されること
- [ ] ターミナルリサイズ時にレイアウトが再計算されること
- [ ] `q` キーで TUI が終了すること
- [ ] テストカバレッジが 80% 以上であること

## Affected files

- `internal/ui/model.go` (新規)
- `internal/ui/layout.go` (新規)
- `internal/ui/pane.go` (新規)
- `internal/ui/keys.go` (新規)
- `internal/ui/help.go` (新規)
- `internal/ui/styles.go` (新規)
- `internal/ui/model_test.go` (新規)

## Dependencies

slice-1

## Implementation outline

1. `internal/ui/pane.go` — ペイン管理:
   - `type Pane int` 列挙: `PaneSlices`, `PaneDetail`, `PaneDeps`, `PaneActions`, `PaneLogs`
   - `func NextPane(current Pane) Pane` / `PrevPane(current Pane) Pane`
   - `func RightPane(current Pane) Pane` / `LeftPane(current Pane) Pane` (h/l 用)
2. `internal/ui/keys.go` — キーバインド定義:
   - `type KeyMap struct` に全キーバインドを定義 (bubbles/key パッケージ使用)
   - h, l, j, k, Tab, Shift+Tab, Space, r, a, A, L, e, d, ?, /, q, Enter
   - `DefaultKeyMap()` で初期値を返す
3. `internal/ui/styles.go` — Lip Gloss スタイル定義:
   - ペインボーダー (通常/フォーカス)
   - ステータスアイコンの色
   - プログレスバーのスタイル
   - ヘルプオーバーレイのスタイル
4. `internal/ui/layout.go` — レイアウトエンジン:
   - `func RenderLayout(width, height int, panes PaneContents, focused Pane) string`
   - Lip Gloss の `lipgloss.JoinHorizontal` / `JoinVertical` で4ペイン配置
   - 上段: スライス一覧 (30%) | 詳細 (35%) | 依存関係 (35%)
   - 下段: アクション (30%) | ログ (70%)
   - 最下段: プログレスバー (100%)
5. `internal/ui/help.go` — ヘルプオーバーレイ:
   - 全キーバインドのテーブル表示
   - `?` でトグル
6. `internal/ui/model.go` — ルートモデル:
   - `type Model struct` (state, focused pane, dimensions, help visible, sub-models)
   - `Init()` → ウィンドウサイズ取得
   - `Update(msg)` → キー入力処理、ペイン切り替え、リサイズ処理
   - `View()` → layout.RenderLayout を呼び出し
   - 各ペインの中身はプレースホルダー文字列 (Slice 4/5 で置き換え)

## Verify plan

- Static analysis checks: `go vet ./internal/ui/...`
- Spec compliance criteria to confirm: 4ペイン配置、h/l/Tab でペイン移動、? でヘルプ、q で終了
- Evidence to capture: `go vet` 出力

## Test plan

- Unit tests: `go test ./internal/ui/...`
  - ペインフォーカス遷移 (h/l/Tab/Shift+Tab)
  - レイアウト計算 (異なるターミナルサイズ)
  - キーバインドマッピング
- Integration tests: `teatest` で起動→キー入力→View 出力を検証
- Edge cases: 極小ターミナル (40x10)、極大ターミナル (300x80)
- Evidence to capture: `go test -cover` レポート

## Notes

- 各ペインの中身は `PaneContents` インターフェースで抽象化し、Slice 4/5 が差し替え可能にする
- Lip Gloss v2 の flex レイアウトを活用する
