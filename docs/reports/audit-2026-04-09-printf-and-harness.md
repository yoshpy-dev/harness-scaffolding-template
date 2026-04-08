# Harness audit — 2026-04-09

## Trigger

`session_end_summary.sh` が `printf: - : invalid option` で失敗。
同様のバグが他にないか、またハーネス全体の健全性を監査。

## Findings

### BUG-01: printf leading-dash (CRITICAL — fixed)

**影響範囲:** `session_end_summary.sh`, `precompact_checkpoint.sh`

`printf '- Timestamp: %s\n' "$ts"` のようなフォーマット文字列が `-` で始まると、
一部シェルの printf ビルトインがオプションフラグとして解釈しエラーになる。

**修正:** `printf '%s\n' "- Timestamp: $ts"` パターンに統一。
- `session_end_summary.sh` — 前セッションで修正済み (8a57503)
- `precompact_checkpoint.sh` — 本セッションで修正

**他のスクリプト:** 問題なし。`ralph-loop.sh:148` の `printf '\n>'` は `\n` で始まるため安全。

### BUG-02: ralph-loop-init.sh の sed インジェクション (LOW)

`ralph-loop-init.sh:80` で `sed -e "s|__OBJECTIVE__|${objective}|g"` を使っている。
`$objective` に `|` を含むとパターンが壊れる。影響は自己利用のみのため LOW。

### OBS-01: check-template.sh の find が for-loop で直接使用 (LOW)

`check-template.sh:30,37,44` で `for script in $(find ...)` を使用。
ファイル名にスペースがあると壊れるが、このリポジトリではスペース入りファイル名は使わない前提のため問題なし。

### OBS-02: lib_json.sh の sed フォールバックが脆弱 (INFO)

`jq` 未インストール時の sed ベース JSON パースは、値にエスケープされた引用符 `\"` があると壊れる。
ヘッダーコメントに記載済みなので INFO 扱い。

## Strengths

- **フック体系が整合的:** settings.json に定義されたフック全てに対応するスクリプトが存在し、逆もまた真
- **check-template.sh が設定ファイルとフック実体の整合性を検証:** フック参照先の欠落を検出できる
- **pre_bash_guard.sh がセーフティネットとして機能:** force push, hard reset, sudo をブロック
- **quality docs が実態と一致:** `definition-of-done.md` はスキルフロー (/work → /self-review → /verify → /test → /pr) と整合、`quality-gates.md` は `scripts/` のエントリポイントと一致
- **スクリプトが小さく単責:** 最大のスクリプト（ralph-loop.sh）でも 188 行

## Pain points

- `printf` 問題のように、POSIX sh の方言差がフックを壊すリスクがある。全フックの基本動作テストがない
- `lib_json.sh` の sed フォールバックは jq 未インストール環境で不安定

## Missing guardrails

- **フックの smoke test がない:** `check-template.sh` は構造のみ検証し、フックの実行可能性は未検証
- **ralph-loop-init.sh の入力サニタイズ:** objective に特殊文字が含まれると sed が壊れる可能性

## Proposed promotions (prose → code)

| Item | Current | Proposed |
|------|---------|----------|
| フック smoke test | なし | `check-template.sh` に `sh -n` (syntax check) を追加 |
| ralph-loop-init.sh 入力 | sed 直接展開 | awk またはヒアドキュメントで安全に置換 |

## Simplifications worth trying

- `precompact_checkpoint.sh` と `session_end_summary.sh` はほぼ同じ構造。共通関数を `lib_report.sh` に抽出すれば重複排除できるが、現時点では各ファイル 30 行以下なので急がない

## Verdict

CRITICAL バグ (BUG-01) は2ファイルとも修正済み。残りは LOW/INFO レベルのみ。
ハーネス全体の健全性は良好。
