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
