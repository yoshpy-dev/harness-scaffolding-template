# Verify report: pipeline-quality-parity

- Date: 2026-04-10
- Plan: (acceptance criteria supplied inline — no archived plan file)
- Verifier: verifier subagent (claude-sonnet-4-6)
- Scope: spec compliance + static analysis + documentation drift
- Evidence: `docs/evidence/verify-2026-04-10-pipeline-quality-parity.log`

## Spec compliance

| Acceptance criterion | Status | Evidence |
| --- | --- | --- |
| AC1: `pipeline-review.md` が削除されている | met | `ls .claude/skills/loop/prompts/pipeline-review.md` → "No such file or directory"; 他の9ファイルは存在する |
| AC2: `pipeline-self-review.md` が10項目チェックリスト + テンプレート構造を含む | met | 行15–28に10項目チェックリスト; 行41–71に `## Report format` テンプレート構造 (findings table, tech debt table, recommendation) |
| AC3: `pipeline-verify.md` がspec complianceテーブル + doc driftチェック + `run-static-verify.sh` 実行を含む | met | 行16–18: spec compliance table; 行43–51: doc drift check; 行29: `./scripts/run-static-verify.sh` 実行指示 |
| AC4: `pipeline-test.md` がtest plan参照 + `run-test.sh` 実行 + root cause analysis テーブルを含む | met | 行11: `The plan file referenced in checkpoint.json — especially the test plan section`; 行16: `./scripts/run-test.sh`; 行44–47: `\| Test \| Error \| Root cause \| Proposed fix \|` table |
| AC5: 3つの新プロンプトすべてが dual-write 指示を含む（`.harness/state/pipeline/` + `docs/reports/`） | met | self-review.md 行79–81; verify.md 行109–113; test.md 行110–114; pipeline-outer.md 行41–43でも dual-write 記載 |
| AC6: 3つの新プロンプトすべてが sidecar signal file の書き込み指示を含む | partially met | self-review.md 行85–88 (`.self-review-result`); verify.md 行118–122 (`.verify-result`); test.md 行119–123 (`.test-result`) — Inner Loop 3プロンプト全てが sidecar を含む。ただし `pipeline-outer.md` には sidecar 指示がない (Outer Loop エージェントは sidecar 対象外なら問題なし) |
| AC7: `ralph-pipeline.sh` の Inner Loop が3つの個別 claude -p 呼び出しを使用 | met | 行497: `run_claude "$_review_prompt"` (self-review); 行537: `run_claude "$_verify_prompt"` (verify); 行571: `run_claude "$_test_prompt"` (test) — implement (行414) に加え計4回の個別 `run_claude()` 呼び出し |
| AC8: `ralph-pipeline.sh` から shell-direct の `run-static-verify.sh` / `run-test.sh` 実行が削除 | met | メインパス（行473–609）に shell-direct 呼び出しなし。行529–534 と行563–568 の inline fallback テキストはエージェントへの指示文であり shell 直接実行ではない |
| AC9: checkpoint.json に `self_review_result` と `verify_result` フィールドが追加 | met | 初期化テンプレート (行814): `"self_review_result": null`; (行815): `"verify_result": null`; 実行時更新: 行517 `ckpt_update ".self_review_result = ..."`; 行550 `ckpt_update --arg v "$_verify_verdict" '.verify_result = $v'` |
| AC10: `pipeline-outer.md` が harness-internal sync の7カテゴリを含む | met | 行28–38: 1.Skills 2.Hooks 3.Rules 4.Language packs 5.Scripts 6.Quality gates 7.PR skill — 全7カテゴリ確認 |
| AC11: `pipeline-outer.md` が dual-write 指示を含む | met | 行40–43: `Write your sync report to BOTH locations:` — `.harness/state/pipeline/sync-docs.md` + `docs/reports/sync-docs-<date>-<slug>.md` |
| AC12: `loop/SKILL.md` の Additional resources が新3プロンプトを参照 | met | 行110: `pipeline-self-review.md — Self-review agent (diff quality, 10-item checklist)` ; 行111: `pipeline-verify.md`; 行112: `pipeline-test.md`; 行113: `pipeline-outer.md` |
| AC13: `quality-gates.md` の Pipeline mode gates が agent-driven を反映 | met | 行54: `Self-review \| claude -p with pipeline-self-review.md (agent-driven, 10-item checklist)`; 行55–56: verify, test も同様 |
| AC14: `definition-of-done.md` に pipeline レポート出力の注記がある | met | 行40–41: `Pipeline report output:` パラグラフ — dual-write とオーケストレーター利用の説明を含む |
| AC15: `ralph-loop.md` の Inner Loop 記述が agent-driven | met | 行200–205: `implement (claude -p) → self-review (claude -p) → verify (claude -p) → test (claude -p)` ; 行207–209: 散文でエージェント駆動・デュアルライト説明 |
| AC16: `post-implementation-pipeline.md` にパリティ注記がある | met | 行13: `Pipeline parity:` パラグラフ — "each post-implementation step runs as a dedicated claude -p agent" + dual-write 記述 |
| AC17: `sh -n scripts/ralph-pipeline.sh` PASS | met | `bash -n scripts/ralph-pipeline.sh` → 出力なし、終了コード 0 |

## Static analysis

| Command | Result | Notes |
| --- | --- | --- |
| `bash -n scripts/ralph-pipeline.sh` | PASS (exit 0) | AC17 直接確認 |
| `bash -n scripts/ralph-orchestrator.sh` | PASS (exit 0) | — |
| `bash -n scripts/ralph` | PASS (exit 0) | — |
| `bash -n scripts/ralph-loop-init.sh` | PASS (exit 0) | — |
| `bash -n scripts/new-ralph-plan.sh` | PASS (exit 0) | — |
| `./scripts/run-static-verify.sh` | exit 2 | scripts/ に変更があるため "code-like changes" と判定、言語パック verifier 未インストールのため exit 2。スキャフォールド固有の挙動であり検証失敗ではない（MEMORY.md に記録済み） |
| shellcheck | 未実行 | shellcheck が未インストール。既知の INFO ギャップ — 毎回フラグを立てる |

## Documentation drift

| Doc / contract | In sync? | Notes |
| --- | --- | --- |
| `.claude/skills/loop/SKILL.md` | yes | Additional resources が4プロンプト全て + 各説明を参照 |
| `docs/quality/quality-gates.md` | yes | Pipeline mode gates テーブルが agent-driven と claude -p を明示 |
| `docs/quality/definition-of-done.md` | yes | `Pipeline report output:` 注記追加済み |
| `.claude/rules/post-implementation-pipeline.md` | yes | `Pipeline parity:` パラグラフ追加済み |
| `docs/recipes/ralph-loop.md` | yes | Inner/Outer Loop architecture ブロックが agent-driven を示す |
| `AGENTS.md` / `CLAUDE.md` | yes (no change needed) | Ralph Loop のパイプライン内部動作への言及は変わっていない — 既存記述と整合 |

## Observational checks

**AC6 の境界確認**: ACは「3つの新プロンプトすべてが sidecar signal file の書き込み指示を含む」と定義されている。Inner Loop の3プロンプト (self-review, verify, test) はすべて sidecar を含む。`pipeline-outer.md` は Outer Loop エージェントであり「3つの新プロンプト」の定義外。よって AC6 は met と判定する。

**fallback inline テキスト (AC8 補足)**: `run-static-verify.sh` / `run-test.sh` の文字列は行529と行565の inline fallback ヒアドキュメント内に存在するが、これらはエージェントへの指示テキストであり `./scripts/run-static-verify.sh` を shell から直接実行するコードではない。メインパスは常に `run_claude()` を使用。AC8 met 判定は正しい。

**checkpoint.json の `self_review_result` 型の注意点**: 初期値は `null` (スカラー) だが、更新時は `{"critical":<N>}` (オブジェクト) に変わる (行517)。`verify_result` は `"pass"/"partial"/"fail"` (文字列) に変わる (行550)。型が非対称だが機能上は問題ない。

## Coverage gaps

- **shellcheck 未インストール**: 全スクリプトの shellcheck 検証ができていない。既知のギャップ。
- **pipeline-outer.md の sidecar**: Outer Loop エージェント (sync-docs) には sidecar signal file の機構がない。オーケストレーターが `.sync-docs-result` を参照するコードも存在しない。これは機能上の問題ではないが、将来 Outer Loop の self-healing を追加する際は sidecar が必要になる。LOW priority gap。
- **ランタイム動作未検証**: `run_inner_loop()` が実際に3つの独立した `claude -p` プロセスを起動することはコード検査で確認したが、ランタイム実行は未検証（テスター担当）。

## Verdict

- Verified: AC1, AC2, AC3, AC4, AC5, AC6, AC7, AC8, AC9, AC10, AC11, AC12, AC13, AC14, AC15, AC16, AC17 (17/17)
- Partially verified: なし
- Not verified: ランタイム動作（テスター担当）

**Overall verdict: PASS**

全17 AC がコード検査・ファイル内容確認により met 判定。静的解析 (bash -n) 全スクリプト通過。ドキュメントドリフトなし。
