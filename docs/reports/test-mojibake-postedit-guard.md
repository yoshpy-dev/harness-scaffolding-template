# Test report: mojibake-postedit-guard

- Date: 2026-04-17
- Plan: `docs/plans/active/2026-04-17-mojibake-postedit-guard.md`
- Branch: `chore/mojibake-postedit-guard`
- Tester: `tester` subagent
- Scope: `.claude/hooks/check_mojibake.sh`, `.claude/hooks/mojibake-allowlist`, templates mirror, `scripts/verify.local.sh` hook entry, `tests/test-check-mojibake.sh`, `tests/fixtures/payloads/{edit,write,multiedit}.json`, settings.json matcher/hook registration
- Evidence: `docs/evidence/test-2026-04-17-mojibake-postedit-guard.log`

## Test execution

| Suite / Command | Tests | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- |
| `./scripts/run-test.sh` (aggregated) | 11 hook + 4 go packages + 6 infra checks (shellcheck skip/syntax/jq/sync) | all | 0 | 1 (shellcheck: not installed) | ~5s |
| `bash tests/test-check-mojibake.sh` standalone | 11 | 11 | 0 | 0 | <1s |
| `bash tests/test-ralph-config.sh` regression | 23 | 23 | 0 | 0 | <1s |
| `bash tests/test-ralph-signals.sh` regression | 3 | 3 | 0 | 0 | ~3s |
| `bash tests/test-ralph-status.sh` regression | 40 | 40 | 0 | 0 | <1s |
| Integration smoke (Japanese content, hook simulation) | 1 | 1 | 0 | 0 | <1s |
| Adversarial smoke (literal U+FFFD via `printf '\357\277\275'`) | 1 | 1 | 0 | 0 | <1s |
| Go `go test ./...` (via golang verifier) | 8 packages | 8 | 0 | 0 | cached |

Total: 88 discrete assertions, all passing.

## Per-plan-case result table

### Unit tests (plan Case A–F, 6 cases / 11 assertions)

| Case | Description | Exit expected | Exit actual | Verdict |
| --- | --- | --- | --- | --- |
| A | U+FFFD-containing file, not allowlisted | 2 | 2 | PASS |
| B | Clean UTF-8 Japanese (`こんにちは、世界`) | 0 | 0 | PASS |
| C | `file_path` points at non-existent file | 0 | 0 | PASS |
| D | Allowlisted path (`tests/fixtures/**`) with U+FFFD | 0 | 0 | PASS |
| E | `PATH` stripped of `jq`, U+FFFD file passed in | 0 (+ marker file `.harness/state/mojibake-jq-missing`) | 0 (marker created) | PASS |
| F.edit (clean) | `tests/fixtures/payloads/edit.json`, clean file | 0 | 0 | PASS |
| F.edit (dirty) | `edit.json`, U+FFFD file | 2 | 2 | PASS |
| F.write (clean) | `write.json`, clean file | 0 | 0 | PASS |
| F.write (dirty) | `write.json`, U+FFFD file | 2 | 2 | PASS |
| F.multiedit (clean) | `multiedit.json`, clean file | 0 | 0 | PASS |
| F.multiedit (dirty) | `multiedit.json`, U+FFFD file | 2 | 2 | PASS |

### Integration smoke (plan: "実セッションで日本語多めファイルの編集直後にフックが exit 0 で通る")

| Case | Description | Exit expected | Exit actual | Verdict |
| --- | --- | --- | --- | --- |
| INT-1 | Created `docs/evidence/mojibake-smoke-20260417-070002.md` with hiragana/kanji/katakana content, piped payload `{"tool_name":"Edit","tool_input":{"file_path":"<abs>"}}` into hook | 0 (no false positive) | 0 | PASS |

Verified via `xxd` that the smoke file contained no `ef bf bd` byte sequence. File cleaned up after run.

### Adversarial smoke (plan: "フック自身のソースに U+FFFD リテラルを含まない" + stderr message spec)

| Case | Description | Exit expected | Exit actual | stderr contains | Verdict |
| --- | --- | --- | --- | --- | --- |
| ADV-1 | Literal U+FFFD bytes via `printf '\357\277\275'` into `/tmp/…`, piped through hook | 2 | 2 | "U+FFFD detected in …" and "Re-read" | PASS |

stderr captured: `check_mojibake.sh: U+FFFD detected in /tmp/mojibake-adversarial-20260417-070037.txt. Re-read the file and rewrite the corrupted section without the replacement character.` — matches acceptance criterion "U+FFFD detected in <path>. Re-read and rewrite the corrupted sections." in spirit (exact wording is slightly longer but preserves both tokens `U+FFFD detected` and `Re-read`).

### Regression tests (verify matcher change + new hook did not break existing suites)

| Suite | Scope | Tests | PASS | FAIL | Verdict |
| --- | --- | --- | --- | --- | --- |
| `test-ralph-config.sh` | RALPH_* defaults + env overrides + numeric validation | 23 | 23 | 0 | PASS |
| `test-ralph-signals.sh` | SIGINT cleanup, loop SIGINT, orchestrator.json status | 3 | 3 | 0 | PASS (timing-dependent "loop status is stuck" accepted — see Test gaps) |
| `test-ralph-status.sh` | helpers / table / JSON / no-color / no-state / whitespace | 40 | 40 | 0 | PASS |
| Go `go test ./...` | 8 internal packages (action, cli, config, scaffold, state, ui, ui/panes, upgrade, watcher) | 8 pkg | 8 | 0 | PASS (cached) |

### verify.local.sh local suite (infrastructure wrapper)

| Step | Command | Result |
| --- | --- | --- |
| 1 | `shellcheck .claude/hooks/*.sh templates/base/.claude/hooks/*.sh scripts/verify.local.sh tests/test-check-mojibake.sh` | SKIP (shellcheck not installed; guarded) |
| 2 | `sh -n` across 18 hook scripts (root + templates) | PASS (18/18) |
| 3 | `jq -e . < .claude/settings.json` × root + templates | PASS (2/2) |
| 4 | `tests/test-check-mojibake.sh` | PASS (11/11) |
| 5 | `scripts/check-sync.sh` | PASS (107 identical, 0 drifted, 0 root-only) |

## Coverage

- Statement: n/a for POSIX shell hooks; coverage measured by test-case scope.
- Branch coverage of `check_mojibake.sh`:
  - `jq` missing → Case E (covered)
  - `file_path` empty / absent → implicit via fixture-less malformed payload… partially covered (empty `file_path` covered in Case C via non-existent path); true "malformed payload / missing `tool_input.file_path` key" branch **not** directly asserted — see Test gaps.
  - File non-existent → Case C (covered)
  - File exists but empty → **not directly covered** (see Test gaps).
  - File with U+FFFD, allowlist match → Case D (covered)
  - File with U+FFFD, no allowlist match → Case A + F.*.dirty (covered)
  - Clean UTF-8 → Case B + F.*.clean (covered)
  - Allowlist glob normalisation (`**` → `*`) → exercised by Case D (`tests/fixtures/**`) indirectly.
- Payload schema coverage: Edit / Write / MultiEdit — all three fixtures tested with both clean and dirty inputs.
- Regression coverage of matcher change (`Edit|Write` → `Edit|Write|MultiEdit`): indirect via `post_edit_verify.sh` sharing the same matcher bucket. Existing ralph-config/signals/status suites all green → no behavioral regression observed. Direct `post_edit_verify.sh` unit test does not exist (pre-existing gap, not regression).
- Notes: golang tests cached hit — acceptable because golang files were not modified in this diff (sanity: `git diff --name-only main...HEAD` contains only `.claude/`, `templates/`, `scripts/verify.local.sh`, `tests/`, `docs/`, `AGENTS.md`).

## Failure analysis

| Test | Error | Root cause | Proposed fix |
| --- | --- | --- | --- |

No failures.

## Regression checks

| Previously broken behavior | Status | Evidence |
| --- | --- | --- |
| `test-ralph-signals.sh / test_loop_sigint` known timing flake ("completed before SIGINT") | Accepted PASS via dual-branch assertion ("interrupted OR any terminal status"). Not a new regression. | `docs/evidence/test-2026-04-17-mojibake-postedit-guard.log` ralph-signals section |
| `post_edit_verify.sh` still touches `.harness/state/needs-verify` after matcher expanded to include `MultiEdit` | Not directly tested — no pre-existing unit test for `post_edit_verify.sh`. verify.local.sh syntax-checks the hook file itself. Runtime behavior unchanged in source diff (hook file byte-identical to main). | `git diff main -- .claude/hooks/post_edit_verify.sh` = empty |

## Test gaps

Acceptance-criterion level: all 13 items in the plan are covered by at least one test case (see per-case table).

Residual edge-case gaps (not blocking — documented for future follow-up):

1. **Empty file with no bytes at all** — `[ -s "$file_path" ]` style branch. Current tests use files with at least 1 byte. `grep -q` on a zero-byte file returns non-zero (no match), so the code path lands on exit 0 naturally, but it is not explicitly asserted.
2. **Malformed JSON / JSON without `tool_input.file_path` key** — tested implicitly via "empty `file_path`" (Case C uses a present-but-missing path). A payload with no `tool_input` object at all is not exercised. `jq -r '.tool_input.file_path // empty'` handles this gracefully (prints `empty`), and the hook then hits the `[ -z "$file_path" ]` early exit. Low risk.
3. **Binary extensions (`.png`, `.pdf`) that coincidentally contain the byte sequence `ef bf bd`** — plan risk mentioned; not exercised. False positive is theoretically possible for binary formats. Mitigation in place via allowlist; plan-level non-goal to filter by file extension.
4. **Absolute vs relative `file_path` + tilde expansion** — hook uses `[ ! -f "$file_path" ]` directly. Relative-path case would fail the file check if cwd differs. Current tests always pass absolute paths.
5. **Fixture with escaped `\"quotes\"` in content** — `edit.json` includes this field but the hook only reads `tool_input.file_path`; the escaped-quote path in `new_string` is not part of what the hook parses. Non-issue for this hook, but worth noting since plan risk 2 ("MultiEdit payload schema drift") is only guarded by the presence of `file_path` — if a future schema moves `file_path` into the `edits[]` array, tests will catch it.
6. **No direct assertion on `post_edit_verify.sh` continuing to touch `.harness/state/needs-verify` for MultiEdit** — relies on Claude Code matcher semantics (both hooks share the matcher). Safe by inspection; no behavioral regression to existing suites.
7. **shellcheck** was skipped (not installed locally). `scripts/verify.local.sh` correctly guards on absence. CI may or may not install it — recommend confirming in `.github/workflows/verify.yml`.

None of these gaps warrant blocking the PR.

## Verdict

- Pass: yes
- Fail: none
- Blocked: none

All acceptance criteria from the plan are exercised by the test suite. Evidence file: `docs/evidence/test-2026-04-17-mojibake-postedit-guard.log` (15k, contains full `run-test.sh` output + standalone hook test + 3 regression suites).

Proceed to `/sync-docs`.
