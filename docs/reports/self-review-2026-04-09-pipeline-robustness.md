# Self-review report: Pipeline robustness improvements

- Date: 2026-04-09
- Plan: docs/plans/active/2026-04-09-pipeline-robustness.md
- Reviewer: reviewer subagent (claude-sonnet-4-6)
- Scope: Diff quality only — naming, readability, unnecessary changes, typos, null safety, debug code, secrets, exception handling, security, maintainability

## Evidence reviewed

- `git diff main...HEAD` covering 41 files, 4803 insertions
- Focus files per task specification:
  - `scripts/ralph-pipeline.sh` (881 lines, new file)
  - `.claude/skills/loop/prompts/pipeline-inner.md` (new file)
  - `.claude/skills/loop/prompts/pipeline-outer.md` (new file)
  - `.claude/skills/loop/prompts/pipeline-review.md` (new file)
  - `docs/quality/definition-of-done.md` (diff)
  - `docs/plans/active/2026-04-09-pipeline-robustness.md` (progress checklist)
- `docs/tech-debt/README.md` for existing debt context
- `.claude/agent-memory/reviewer/MEMORY.md` for recurring patterns

---

## Findings

| Severity | Area | Finding | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| HIGH | security | `_pr_url` (外部ソースから取得) が `--arg` を使わずjqフィルタ文字列に直接埋め込まれている。URLに `"` や `\` が含まれるとjqのフィルタが壊れる。`_new_session` (claude出力) も同様。 | `ralph-pipeline.sh:699` `ckpt_update ".pr_created = true | .pr_url = \"${_pr_url}\" | .status = \"complete\""` / `ralph-pipeline.sh:422` `ckpt_update ".session_id = \"${_new_session}\""` | `ckpt_update` の呼び出しを `jq --arg url "$_pr_url" '.pr_url = $url | .pr_created = true | .status = "complete"'` のように `--arg` を使うパターンへ移行する。プロジェクトメモリに記録済みの推奨パターン。 |
| HIGH | security | `report_event` の `_pr_url` も文字列連結でJSONに埋め込まれている。不正なJSONがJSONLファイルに書き込まれる。 | `ralph-pipeline.sh:700` `report_event "pr-created" "{\"cycle\":${_cycle},\"url\":\"${_pr_url}\"}"`  | `jq -n --arg url "$_pr_url" --argjson cycle "$_cycle" '{"cycle":$cycle,"url":$url}'` で生成してから `report_event` に渡す。 |
| HIGH | maintainability | `run_inner_loop()` でphaseを "inner" に更新した直後に `ckpt_read 'phase'` を "from" フィールドとして読んでいる。更新後の値を読むため、遷移レコードに常に "inner→inner" が記録される。前回のphaseが失われる。 | `ralph-pipeline.sh:349-350` `ckpt_update ".phase = \"inner\" | ..."` → `ckpt_transition "$(ckpt_read 'phase' || echo 'start')" "inner"` | `ckpt_read` を `ckpt_update` より前に実行する。`_prev_phase="$(ckpt_read 'phase' || echo 'start')"` → `ckpt_update ...` → `ckpt_transition "$_prev_phase" "inner"` の順に変更する。この問題は前回レビュー（self-review-2026-04-09-ralph-loop-v2-r2.md）で記録済みだがこのファイルでも再現している。 |
| MEDIUM | maintainability | `pipeline-outer.md` のサイドカーファイル指示でハードコードされた例URLが示されている。エージェントが例URLをそのまま書き込む可能性がある。 | `.claude/skills/loop/prompts/pipeline-outer.md:55` `echo "https://github.com/owner/repo/pull/123" > .harness/state/pipeline/.pr-url` | 例を `<実際のPR URL>` などのプレースホルダーに変えるか、`gh pr view --json url --jq '.url'` で取得して書き込む例に変更する。 |
| MEDIUM | maintainability | `run_inner_loop` の inline fallback プロンプト (line 476-486) は `docs/reports/` へのレポート出力を指示しているが、`pipeline-review.md` は `.harness/state/pipeline/` を指示している。フォールバック時とメインパス時で出力先が異なる。 | `ralph-pipeline.sh:484` `Write findings to docs/reports/ following the self-review template.` vs `pipeline-review.md:28` `Write findings to .harness/state/pipeline/self-review.md.` | `ralph-pipeline.sh` の inline fallback プロンプトを `pipeline-review.md` と一致させる。出力先を `.harness/state/pipeline/self-review.md` に統一する。 |
| MEDIUM | null-safety | `run_claude()` のtext fallbackモードで `${_log_file}.json` を空ファイルとして作成している (``: > "${_log_file}.json"`)。その後 `session_id` 抽出で `[ -s "${_impl_log}.json" ]` を確認しているため問題ないが、コードex(line 416-418)と text modeが混在するパスで `.json` ファイルの内容が一致しない状態になる。 | `ralph-pipeline.sh:136` `: > "${_log_file}.json"` / `ralph-pipeline.sh:416` `[ -s "${_impl_log}.json" ]` | 現状は `-s` チェックで防御されており実害なし。コメントを追加してtext modeでは `.json` は空であることを明記する。 |
| LOW | readability | `ckpt_update` 関数がjqフィルタ式をそのまま受け取る汎用インターフェースになっており、呼び出し側が任意のjqフィルタを構築して渡す。これはsecurity findingの根本原因でもある。 | `ralph-pipeline.sh:76-83` `ckpt_update()` / 多数の呼び出し箇所 | より安全で読みやすくするため、`ckpt_set_field <field> <value>` のような専用ヘルパーを導入し、`--arg` を内部で使う設計にする。ただし、今回スコープ外のリファクタリング。tech-debt に記録する。 |
| LOW | readability | `run_outer_loop` の codex triage parsing（line 621-625）が markdown ファイルの `grep -c` で行数を数えている。同じ行に複数のキーワードが登場する（例: テーブルの行ヘッダー）と過大カウントになる。 | `ralph-pipeline.sh:622` `_action_required="$(grep -c 'ACTION_REQUIRED' "$_triage_report" ..."` | 過大カウントは安全方向（より多くの regression を引き起こす）なため実害は低い。ただし精度が低い。コメントで既知の制限を記述する。 |
| LOW | typo | `pipeline-review.md` のmarkdown inline fallback内 "Readability" の重複なし、問題なし。ただし `pipeline-review.md:35` の指示 `./scripts/run-static-verify.sh` は `ralph-pipeline.sh:508` の実行パスと一致しているが、スクリプトが存在しない環境では fallback が `run-verify.sh` になる。プロンプト内ではフォールバックの説明がない。 | `pipeline-review.md:35` `Run: ./scripts/run-static-verify.sh` | プロンプトに `(or HARNESS_VERIFY_MODE=static ./scripts/run-verify.sh if run-static-verify.sh is not available)` を追加する。 |

---

## Positive notes

- `run_claude()` の JSON/text モード分岐が明確で、stdout/stderr 分離の設計は堅牢。
- サイドカーファイルのライフサイクル管理（Inner Loop開始時のクリア）は AC4 を正確に実装している。
- PR URL の3層検出（gh CLI → sidecar → log grep）の優先度順序は適切。
- `check_stuck()` がworking tree差分ではなくHEAD commitハッシュで判定するよう改善されており、「コミット済みの変化」を正しく検出できる。
- `usage()` が `exit 0` を返す修正（AC7）は正しく実装されている。
- `pipeline-inner.md` と `pipeline-outer.md` の safety rules セクションはプロジェクトの `.claude/rules/git-commit-strategy.md` と一致している。
- CRITICAL self-review 発見が非ブロッキング（tech-debt に記録済み）であることが `ralph-pipeline.sh:496` のコメントで明示されており、設計意図が読み取れる。
- `definition-of-done.md` のパイプラインモードセクション追加は簡潔で正確。

---

## Tech debt identified

| Debt item | Impact | Why deferred | Trigger to pay down | Related plan/report |
| --- | --- | --- | --- | --- |
| `ckpt_update()` が生のjqフィルタ式を受け取る汎用インターフェースのため、呼び出し側が外部値を文字列連結で埋め込みやすい。`_pr_url` と `_new_session` が `--arg` なしで渡されている（HIGH: security）。 | 不正なJSONまたはjq injection。本番では github.com の URL のみのため現実的リスクは低いが、構造的に脆弱。 | 今回のスコープはjsonパース改善のみ。`ckpt_update` インターフェース変更は大きなリファクタリング。 | `ralph-pipeline.sh` の次回リファクタリング時、またはURLソースが外部エンティティに拡張されるとき | docs/reports/self-review-2026-04-09-pipeline-robustness.md |
| `run_inner_loop` の phase更新後に旧phaseを読む順序バグ（HIGH: maintainability）。前回レビューと同じパターンが本ファイルでも再現している。 | `phase_transitions` の `from` フィールドが常に "inner" を記録する。デバッグ情報の精度低下。 | 機能的影響は監査ログの精度のみ。パイプライン動作には影響しない。 | `ckpt_transition` の呼び出しパターンをリファクタリングするとき | docs/reports/self-review-2026-04-09-pipeline-robustness.md |

_(上記エントリは `docs/tech-debt/README.md` にも追記する。)_

---

## Recommendation

- **Merge: NO — 2件のHIGH findingを先に修正することを推奨**
- HIGH-1 (`_pr_url`/`_new_session` の jq injection): `ckpt_update` と `report_event` の呼び出しを `--arg` パターンに変更する（`ralph-pipeline.sh:422`, `ralph-pipeline.sh:699-700`）
- HIGH-2 (phase update/read 順序): `ralph-pipeline.sh:349-350` を `_prev_phase` 先読みパターンに変更する
- MEDIUM findings は次のイテレーションで対処可能（パイプライン動作への影響なし）
- Follow-ups:
  - `pipeline-outer.md:55` のハードコード例URL を修正する
  - inline fallback プロンプトのレポート出力先を `pipeline-review.md` に合わせる
  - tech-debt に `ckpt_update` インターフェース改善を記録する（上記）
