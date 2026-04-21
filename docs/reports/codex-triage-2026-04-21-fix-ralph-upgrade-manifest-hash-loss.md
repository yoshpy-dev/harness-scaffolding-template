# Codex triage report: fix-ralph-upgrade-manifest-hash-loss

- Date: 2026-04-21
- Plan: `docs/plans/archive/2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md`
- Base branch: main
- Triager: Claude Code (main context)
- Self-review cross-ref: yes
- Total Codex findings: 2 (both P2)
- After triage: ACTION_REQUIRED=2, WORTH_CONSIDERING=0, DISMISSED=0

> 注記: 初回 `/codex-review` は usage limit により中断。リセット後のリトライで本レポートを生成。

## Triage context

- Active plan: `docs/plans/archive/2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md`
- Self-review report: `docs/reports/self-review-2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md`
- Verify report: `docs/reports/verify-2026-04-21-fix-ralph-upgrade-manifest-hash-loss.md`
- Implementation context summary: base と pack の diff sweep を `splitManifestForBase` / `splitManifestForPack` でマニフェスト subset 化して分離。pack 側は `ComputeDiffsWithManifest(..., false)` で removal sweep を無効化。`preservePackEntries` で PackFS / diff 失敗時に旧エントリを保持。

## ACTION_REQUIRED

| # | Codex finding | Triage rationale | Affected file(s) |
|---|---------------|------------------|-------------------|
| 1 | [P2] Restore removal detection for files deleted from an existing pack. `internal/cli/upgrade.go:122-124` の `ComputeDiffsWithManifest(packManifest, packDir, packFS, false)` は pack FS にもう存在しないマニフェストエントリを `ActionRemove` として報告しない。base sweep は `splitManifestForBase` で `packs/languages/*` を除外済みなので、結果として "pack ファイルがテンプレートから削除された" 通知パス（以前は base sweep 経由で発火していた副作用的動作）が完全に消失。新マニフェスト再構築で該当エントリが静かに脱落、ディスク上のファイルは残る。| リグレッション。user が fix した元のバグ (pack を毎回 Remove と誤判定) は base sweep 側で既に防げているので、pack 側で `checkRemovals=true` にしても二重分類は起きない（base 側は pack prefix を完全に除外、pack 側はファイルが双方に同時に存在しないのでAdd と Remove が同一 path に発火しない）。Axis1=Yes (real regression), Axis2=Yes (small diff, high signal value)。 | `internal/cli/upgrade.go:124` |
| 2 | [P2] Don't preserve packs that disappeared from the release. `upgrade.go:116-119` の `PackFS` エラーは `unknown language pack`（新リリースで削除/改名された正常ケース）にも発火。結果として削除された pack のエントリが永遠に残り、以降の upgrade で毎回 "Warning: pack X" を出し続け、ユーザに「この pack は消えました」という signal を渡せない。| 真の regression。`preservePackEntries` は "transient エラー" 用として plan で設計したが、`scaffold.PackFS` の error 種別を区別しておらず、永続的な削除ケースにも発火。修正方針: `scaffold.AvailablePacks()` で事前チェックし、現リリースに存在しない pack は preserve 対象外（drop + `Meta.Packs` からも除外）。Axis1=Yes, Axis2=Yes。| `internal/cli/upgrade.go:114-128` |

## WORTH_CONSIDERING

| # | Codex finding | Triage rationale | Affected file(s) |
|---|---------------|------------------|-------------------|

（なし）

## DISMISSED

| # | Codex finding | Dismissal reason | Category |
|---|---------------|------------------|----------|

（なし）

Categories: false-positive, already-addressed, style-preference, out-of-scope, context-aware-safe

---

## Round 2 (post-d16cb4d)

- Codex findings: 2 (both P2)
- After triage: ACTION_REQUIRED=1, WORTH_CONSIDERING=1, DISMISSED=0

### ACTION_REQUIRED

| # | Codex finding | Triage rationale | Affected file(s) |
|---|---------------|------------------|-------------------|
| 3 | [P2] Avoid repeating pack-removal notices on every upgrade — `internal/cli/upgrade.go:143-147`. `checkRemovals=true` にしたことで削除された pack ファイルが `ActionRemove` で通知されるが、現在の ActionRemove 分岐は `manifest.SetFile(d.Path, d.OldHash)` でエントリを保持するため、次回 upgrade でも同じファイルが再通知され続ける。idempotency 契約を破る。| 真の regression（pre-existing バグを私の pack-removal 復活で顕在化）。base ファイルにも同じロジックが効いているため、過去も "removed from template" が永続警告として出続けていた可能性が高い。修正方針: ActionRemove で manifest エントリをドロップする（"review and delete manually" とユーザに伝えた通り、次回以降 manifest からも外す）。Axis1=Yes, Axis2=Yes。| `internal/cli/upgrade.go:225-229`, `internal/upgrade/diff.go:171-183` |

### WORTH_CONSIDERING

| # | Codex finding | Triage rationale | Affected file(s) |
|---|---------------|------------------|-------------------|
| 4 | [P2] Normalize pack manifest keys in tests for Windows — `internal/cli/cli_test.go:181-182`. テストが `"packs/languages/golang/README.md"` のようにスラッシュで直書きしているが、`executeInit` は `filepath.Join` で manifest キーを作るので Windows では `\` 区切りになり lookup が失敗する。| 実装側は `splitManifestForPack` が `filepath.ToSlash` で正規化済みで正しく動作する。テストの portability だけの問題。CI が Linux/macOS しか回っていない現状で regression 相当ではなく WORTH_CONSIDERING。ただし `filepath.Join` へ書き換えるのは 5 行・低リスクなので同時に直しても良い。Axis1=Debatable, Axis2=Debatable。| `internal/cli/cli_test.go:182, 265, 269, 282, 298, 319, 323` |

---

## Round 3 (post-6f038de)

- Codex findings: 1 (P2)
- After triage: ACTION_REQUIRED=1, WORTH_CONSIDERING=0, DISMISSED=0

### ACTION_REQUIRED

| # | Codex finding | Triage rationale | Affected file(s) |
|---|---------------|------------------|-------------------|
| 5 | [P2] Don't abort the whole upgrade when pack listing fails — `internal/cli/upgrade.go:109-111`. `scaffold.AvailablePacks()` が error を返すと `runUpgrade` が base 差分を書き込まずに即 return。以前はどんな pack 関連エラーも warning 降格で base upgrade は継続していた。私の Finding 2 fix で新たに導入した abort パス。| 真の regression（Round 2 で新規に導入したもの）。production では `embed.FS.ReadDir` が失敗する可能性は極小だが、テスト注入 FS や将来の embed 構造変更で発火し得る。修正方針: error を warn に降格し、availablePacks が得られない場合は全 pack エントリを preservation 扱いにして base upgrade を継続する（transient fallback 相当）。Axis1=Yes, Axis2=Yes。修正は 5 行程度。| `internal/cli/upgrade.go:109-116` |

---

## Round 4 (post-0d1c4b0)

- Codex findings: 2 (both P2)
- After triage: ACTION_REQUIRED=2, WORTH_CONSIDERING=0, DISMISSED=0

### ACTION_REQUIRED

| # | Codex finding | Triage rationale | Affected file(s) |
|---|---------------|------------------|-------------------|
| 6 | [P2] Preserve hash provenance for edited empty-hash repairs — `internal/upgrade/diff.go:118-124`. 破損マニフェスト (`hash=""`) × ユーザ編集で `ActionConflict` が発火するが `OldHash="" ` のまま返る。`runUpgrade` の skip 分岐は `manifest.SetFile(d.Path, d.OldHash)` で空文字を書き戻すので、非対話モードや skip 選択時に heal が完了せず同じファイルが永遠に conflict する。| 真の regression。heal は「壊れたマニフェストを無風で直す」契約のはずが、user-edited ケースで無限 loop。修正方針: heal 時の `ActionConflict` で `OldHash: newHash` を詰める（template を新しい baseline として採用）。skip 選択で newHash が書き戻され、次回 upgrade は `newHash == mf.Hash` で ActionSkip に落ちる。Axis1=Yes, Axis2=Yes。1行変更。| `internal/upgrade/diff.go:118-124` |
| 7 | [P2] Keep removed-file provenance after the first warning — `internal/cli/upgrade.go:235-241`. `ActionRemove` 後にマニフェストエントリを drop すると最後の template hash が失われる。ユーザが "review and delete manually" 通知後もファイルを残し、後のリリースで同じ path が復活した場合、`ComputeDiffsWithManifest` はマニフェストにエントリが無いので `ActionAdd` と分類し、disk を無警告で上書きする → silent data loss。| 本当の data-loss path。edge case だが serious。修正方針: `ActionAdd` 側で disk 存在 + 内容差を検出し、`ActionConflict` に格上げする（disk 無し or 同一内容なら従来通り Add）。これで reintroduction でも user に conflict prompt が出る。Axis1=Yes, Axis2=Yes。約10行の変更。| `internal/upgrade/diff.go:69-77` (ActionAdd path), `internal/cli/upgrade.go:210-219` |


