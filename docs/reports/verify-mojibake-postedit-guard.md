# Verify report: mojibake-postedit-guard

- Date: 2026-04-17
- Plan: `docs/plans/active/2026-04-17-mojibake-postedit-guard.md`
- Branch: `chore/mojibake-postedit-guard` (5 commits: 22642c9, 3311dc6, 911c5ac, 7c4cc9e, 1321cd0)
- Verifier: `verifier` subagent (Claude)
- Scope: Spec compliance (13 acceptance criteria) + static analysis. Behavioral test execution is deferred to `/test`.
- Evidence: `docs/evidence/verify-2026-04-17-mojibake-postedit-guard.log`

## Spec compliance

| # | Acceptance criterion | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Hook is POSIX sh, reads stdin JSON, extracts `tool_input.file_path` via `jq` (jq required; warn+exit 0 if missing) | PASS | `.claude/hooks/check_mojibake.sh:1` (`#!/usr/bin/env sh`); `set -eu` at L33; jq presence check L40–45; `jq -r '.tool_input.file_path // empty'` at L47. bash-ism scan: no hits (`[[`/`]]`/`<<<`/`$'...'`/`((`). |
| 2 | `jq` missing → exit 0 and `.harness/state/mojibake-jq-missing` marker created | PASS | Hook L40–45 writes marker via `: > "$REPO_ROOT/.harness/state/mojibake-jq-missing"` and emits stderr warning before `exit 0`. Test Case E exercised this path and passed (`docs/evidence/verify-2026-04-17-mojibake-postedit-guard.log` line `E. jq missing → exit 0 + marker  PASS`). |
| 3 | U+FFFD detected + not allowlisted → stderr actionable message + `exit 2` | PASS (text deviation noted) | Hook L88–91 emits `printf 'check_mojibake.sh: U+FFFD detected in %s. Re-read the file and rewrite the corrupted section without the replacement character.\n'` and `exit 2`. Wording is "Re-read the file and rewrite the corrupted section without the replacement character." vs. plan text "Re-read and rewrite the corrupted sections." — semantically equivalent, flagged as minor drift only. Tests A and F-dirty exercise exit 2. |
| 4 | Allowlist match, or empty / non-existent / clean file → `exit 0` | PASS | Non-existent at L53–55; allowlist loop L66–82 with `case` glob match; final clean path exits 0 at L93. Tests B, C, D, F-clean confirm behavior (log lines). |
| 5 | Hook itself and `tests/fixtures/**` allowlisted by default | PASS | `.claude/hooks/mojibake-allowlist:11–15` lists `.claude/hooks/check_mojibake.sh`, `tests/fixtures/**`, plus two mojibake-plan/report glob entries. Byte-identical in `templates/base/.claude/hooks/mojibake-allowlist`. |
| 6 | `.claude/settings.json` PostToolUse has both hooks; matcher is `Edit\|Write\|MultiEdit` | PASS | `.claude/settings.json:102–115` — matcher at L104, `post_edit_verify.sh` at L107–109 (first), `check_mojibake.sh` at L110–113 (second). Same shape in `templates/base/.claude/settings.json:102–115`. |
| 7 | `templates/base/` mirrors for hook, allowlist, settings.json are byte-for-byte identical; `check-sync.sh` PASS | PASS | `cmp` on all three pairs → exit 0 (HOOK_IDENTICAL, ALLOWLIST_IDENTICAL, SETTINGS_IDENTICAL). `./scripts/check-sync.sh` → `IDENTICAL: 107, DRIFTED: 0, ROOT_ONLY: 0`, final "PASS: all files in sync." |
| 8 | Test script covers 6 cases (U+FFFD / clean / missing / allowlisted / jq-missing / Edit+Write+MultiEdit fixtures) | PASS | `tests/test-check-mojibake.sh` implements A–F. The test expands Case F to 3 tools × 2 scenarios (clean + dirty) → 6 assertions, producing 11 total PASS lines. Logged 11/11 PASS in evidence. (Plan AC says "6 ケース" but test covers a stricter superset — Case F became 6 sub-asserts; this is strengthening, not a gap.) |
| 9 | `scripts/verify.local.sh` runs shellcheck → sh -n → jq -e → test-check-mojibake.sh | PASS | `scripts/verify.local.sh:28–65` runs (1) shellcheck when available, (2) `sh -n` for each hook, (3) `jq -e .` for root + template settings.json, (4) `tests/test-check-mojibake.sh`, (5) `scripts/check-sync.sh`. Execution order matches plan. Status aggregated via `status=1` on any fail. |
| 10 | `./scripts/run-verify.sh` invokes `verify.local.sh` and all checks pass | PASS | `scripts/run-verify.sh:32–38` auto-invokes `./scripts/verify.local.sh`. Static run (this verify): exit 0, all steps OK, evidence saved to `docs/evidence/verify-2026-04-17-mojibake-postedit-guard.log`. |
| 11 | `./scripts/check-sync.sh` PASS; repo-only files added to ROOT_ONLY_EXCLUSIONS | PASS (scope observation) | `scripts/check-sync.sh:37–39` adds `"scripts/verify.local.sh"` and `"tests/"` prefix. The `"tests/"` prefix covers both `tests/test-check-mojibake.sh` and `tests/fixtures/payloads/` in a single entry (prefix match, L94 `case "$path" in "${pattern}"*)`). Plan listed them as separate entries; implementation consolidated to one prefix. Functionally equivalent; documented in self-review LOW-6. |
| 12 | Hook source contains no U+FFFD literal (`EF BF BD`) | PASS | `LC_ALL=C grep` for `$(printf '\357\277\275')` across `.claude/hooks/check_mojibake.sh`, templates mirror, allowlist (both), `scripts/verify.local.sh`, `tests/test-check-mojibake.sh` → all CLEAN. Runtime-construction at L86 (`FFFD="$(printf '\357\277\275')"`) matches design intent. |
| 13 | AGENTS.md repo map note added, conveying intent + allowlist existence + retirement trigger | PASS | `AGENTS.md:66` — 1-line nested bullet: "`check_mojibake.sh` + `mojibake-allowlist` — temporary U+FFFD detection guard for Claude Code SSE mojibake (remove once upstream Issue #43746 ships)". Plan said "2 行注記" (two lines); implementation is 1 consolidated bullet. Semantically covers all three requirements (intent / allowlist / retirement trigger). Self-review already flagged this wording drift (LOW-7). |

## Static analysis

| Command | Result | Notes |
| --- | --- | --- |
| `sh -n .claude/hooks/check_mojibake.sh` | OK | POSIX syntax clean |
| `sh -n templates/base/.claude/hooks/check_mojibake.sh` | OK | Mirror clean |
| `sh -n scripts/verify.local.sh` | OK | POSIX syntax clean |
| `bash -n tests/test-check-mojibake.sh` | OK | bash header is deliberate (uses arrays and `local` — not a POSIX constraint) |
| `sh -n` on all other hooks (8 files × 2 locations) | OK | No regression to sibling hooks |
| `jq -e . < .claude/settings.json` | OK | Valid JSON |
| `jq -e . < templates/base/.claude/settings.json` | OK | Valid JSON |
| bash-ism scan on POSIX-declared scripts (`[[`, `]]`, `<<<`, `$'...'`, `((`, `))`) | CLEAN | No bash-isms in hook, template hook, `verify.local.sh` |
| `cmp` root vs template: hook / allowlist / settings.json | identical | 3 × exit 0 |
| U+FFFD byte scan across new files | CLEAN | 6 files, zero matches |
| `./scripts/check-sync.sh` | PASS | `IDENTICAL: 107, DRIFTED: 0, ROOT_ONLY: 0, TEMPLATE_ONLY: 9, KNOWN_DIFF: 3` |
| `HARNESS_VERIFY_MODE=static ./scripts/run-verify.sh` | EXIT 0 | Full chain: verify.local.sh → sh -n × 18 hooks → jq -e × 2 → tests/test-check-mojibake.sh (11/11 PASS — noted for tester, not re-run here) → check-sync.sh → golang verifier |
| `shellcheck` | SKIPPED | Not installed on macOS host; CI should cover. `verify.local.sh:29–39` already wires shellcheck when present. |

## Documentation drift

| Doc / contract | In sync? | Notes |
| --- | --- | --- |
| `AGENTS.md` Repo map | YES | L66 1-line annotation present. Plan text "2 行注記" drifted to a 1-line bullet; self-review LOW-7 already captured this. Fits AGENTS.md "keep short" rule, so no action required. |
| `templates/base/AGENTS.md` | Unchanged (KNOWN_DIFF) | Template intentionally does not carry repo-specific hook notes (`check-sync.sh:83` whitelists `AGENTS.md` as KNOWN_DIFF). The hook note is repo-scope only, matching plan Non-goals. |
| Message text in AC3 | Wording drift (minor) | Hook message reads "Re-read the file and rewrite the corrupted section without the replacement character." Plan spec says "Re-read and rewrite the corrupted sections." Meaning preserved; plan wording was non-normative example. Not a blocker; flagged so `/sync-docs` can choose whether to tighten the plan text. |
| Plan progress checklist (L60–72 acceptance criteria) | STALE | All 13 AC checkboxes remain `- [ ]` despite implementation being complete, tests green, and sync PASS. Plan's own L167-175 "Progress checklist" (pipeline-stage) is accurate (`- [x] Plan reviewed/Branch created/Implementation started`, rest unchecked until artifacts land). The AC list's unchecked state is a doc drift. Recommendation: `/sync-docs` or `/pr` flips the AC checkboxes to `[x]` based on this verify report. |
| `check-sync.sh` ROOT_ONLY_EXCLUSIONS | YES (consolidated form) | Adds `scripts/verify.local.sh` (L37) and `tests/` prefix (L39). `tests/` prefix subsumes `tests/test-check-mojibake.sh` and `tests/fixtures/payloads/` that the plan enumerated separately. Self-review LOW-6 flagged the loss of granularity; acceptable per plan's "add these repo-only files to exclusions" intent. |
| Hook header comment | In sync | Matches plan's "fail-open-with-warning" rationale; retirement trigger (Issue #43746) documented at L11–13. |
| `mojibake-allowlist` default entries | Superset of plan | Plan specified 3 defaults; implementation adds 2 more glob fallbacks (`docs/plans/**/*mojibake*.md`, `docs/reports/**/*mojibake*.md`). Strengthening, not drift. |

## Observational checks

- Commit slicing is coherent: 5 commits map to (a) hook+tests+fixtures, (b) settings registration, (c) AGENTS.md note, (d) plan status flip, (e) self-review LOW fix-up (cleanup scope + contract note). Matches `.claude/rules/git-commit-strategy.md` slice-then-commit discipline.
- `git status` is clean except for the pending `docs/reports/self-review-mojibake-postedit-guard.md` (expected for an active pipeline) and now this verify report + evidence log.
- Execute bits: `.claude/hooks/check_mojibake.sh` 0755 (root + mirror), `scripts/verify.local.sh` 0755, `tests/test-check-mojibake.sh` 0755 — all match existing house style. `mojibake-allowlist` 0644, correct.
- Hook defense-in-depth verified: runtime-constructed `FFFD` byte + `.claude/hooks/check_mojibake.sh` allowlist self-entry → two independent self-detection barriers.
- `HOOK_REPO_ROOT` override env is test-only (used 7× in test script) and header-documented at L30–31. Not a production contract.

## Coverage gaps

| Gap | Severity | Notes |
| --- | --- | --- |
| `shellcheck` not installed on verify host | LOW | `verify.local.sh` wires it in; CI should run a shellcheck-equipped runner. Verified syntax via `sh -n` + manual bash-ism scan; high confidence but no lint-level dead code / quoting analysis. |
| Behavioral tests (11/11 PASS observed in static chain but driven by `run-verify.sh`) | N/A | Out of /verify scope. `/test` subagent should treat `tests/test-check-mojibake.sh` as the authoritative test. |
| Hook behavior inside a real Claude Code session (actual PostToolUse dispatch) | UNVERIFIED | Plan Implementation-outline step 10 calls for manual session probe. Not a static-verify concern — tracked for the `/test` step's integration-case manual walkthrough. |
| Hook behavior with malformed JSON payloads (non-extractable file_path from non-empty payload) | LOW | Self-review LOW-2: silently maps to exit 0 with no log line. Intended fail-open, but narrows the mojibake detection slightly. No test case; could add one if upstream Claude Code ever emits partial JSON. |

## Verdict

- **PASS**.
- All 13 acceptance criteria satisfied (with 3 benign wording / consolidation drifts called out in `Documentation drift` — none block the pipeline).
- No CRITICAL, HIGH, or MEDIUM static-analysis finding.
- Pipeline may proceed to `/test`. `/test` should run `tests/test-check-mojibake.sh` as its authoritative suite and additionally attempt a real-session walkthrough per plan step 10.

### Verified

- POSIX sh shape of the hook (no bash-isms, `set -eu`, shebang)
- JSON validity of both settings.json files
- Byte-for-byte mirror parity (hook, allowlist, settings.json)
- `check-sync.sh` PASS with 0 DRIFTED / 0 ROOT_ONLY
- No U+FFFD literal in any new source file
- AGENTS.md repo map note present
- `run-verify.sh` → `verify.local.sh` → all checks OK (exit 0)
- 11/11 test assertions passed in the static chain (captured from evidence log; authoritative re-run belongs to `/test`)
- Commit history coherent and slice-aligned

### Likely but unverified (statically)

- Real Claude Code PostToolUse dispatch chain actually executes both hooks in order (plan assumes this from spec docs — no runtime probe in static mode)
- `exit 2` actually triggers Claude to re-read and rewrite the file (Claude Code spec-dependent — `/test` walkthrough should confirm)
- Allowlist glob matches at runtime under a real `$REPO_ROOT` with symlinks / weird paths (manual probes confirmed POSIX `case` semantics; full surface is tester territory)

### Not verified

- shellcheck (tool unavailable on verify host) — defer to CI
- Behavior with malformed JSON payloads (no test case yet) — optional follow-up

## Follow-ups

1. **Non-blocking doc cleanup**: in `/sync-docs` or `/pr`, flip the 13 AC checkboxes at plan L60–72 from `- [ ]` to `- [x]` based on this verify report.
2. **Non-blocking wording alignment**: optionally align hook stderr text with plan AC3 wording (or vice versa). Current wording is arguably clearer.
3. **LOW self-review items remain optional** — already captured in `docs/reports/self-review-mojibake-postedit-guard.md`. Of those, the cleanup-scope fix has already landed in commit `1321cd0` per the self-review report's recommendation #1.
4. **CI**: ensure the shellcheck runner on CI covers `.claude/hooks/*.sh`, `templates/base/.claude/hooks/*.sh`, `scripts/verify.local.sh`, and `tests/test-check-mojibake.sh` — `verify.local.sh` already selects them when the tool is present.

## Minimal additional check to raise confidence

A single real-session probe: edit any Japanese-heavy file in a fresh Claude Code session and confirm (a) `post_edit_verify.sh` fires first, (b) `check_mojibake.sh` fires second, (c) exit 0 (no false positive), and (d) `.harness/state/needs-verify` gets touched as before. This is a `/test` walkthrough concern, not a static check, but it is the single highest-value next step because everything else verified here is surface (POSIX shape, sync, wiring) while the end-to-end PostToolUse dispatch remains inferred.

## Re-verify after Codex fixes (commit 306b23a)

- Date: 2026-04-17 (UTC 07:22)
- Branch HEAD: `306b23a` (`fix: address Codex P3 (matcher symmetry), P2 (mode split), P1 hardening`)
- Verifier: `verifier` subagent (2nd pass)
- Scope: delta verification of the Codex fix slice. Static analysis only; behavioral test execution stays with `/test`.
- Working tree: clean except for pending `docs/reports/self-review-mojibake-postedit-guard.md` (prior pipeline artifact) and this report update. No other uncommitted drift — the fixes are in the committed tree, not just the working tree.
- Evidence: `docs/evidence/verify-2026-04-17-mojibake-postedit-guard-reverify-306b23a.log`

### Commit under test (`git show --stat 306b23a`)

| File | Change |
| --- | --- |
| `.claude/settings.json` | `PostToolUseFailure.matcher`: `Bash\|Edit\|Write` → `Bash\|Edit\|Write\|MultiEdit` (1 line) |
| `templates/base/.claude/settings.json` | same (mirrored) |
| `scripts/verify.local.sh` | `HARNESS_VERIFY_MODE` (static/test/all) dispatch + positional-parameter shellcheck-arg builder (replaces `# shellcheck disable=SC2086` word-split) |
| `tests/test-check-mojibake.sh` | Case E minimal PATH link set extended to include `dirname env ln test` |
| `docs/reports/codex-triage-mojibake-postedit-guard.md` | new triage artifact |

### Delta spec compliance — do the 13 plan AC still hold?

| # | Acceptance criterion | Status after 306b23a | Evidence |
| --- | --- | --- | --- |
| 1 | Hook POSIX sh, stdin JSON, jq extracts file_path | PASS (unchanged — fix does not touch hook) | `.claude/hooks/check_mojibake.sh` untouched in this commit; `sh -n` clean |
| 2 | jq missing → exit 0 + marker | PASS (hardened) | Case E still exits 0 + marker in mode=test/all runs. Link-set hardening (`dirname env ln test`) means the test now fails realistically if `dirname` is absent, so the jq-missing branch is exercised on its own merits rather than hiding behind `HOOK_REPO_ROOT` |
| 3 | U+FFFD + not allowlisted → exit 2 with message | PASS (unchanged) | Case A + Case F.{edit,write,multiedit}.dirty all still exit 2 (11/11 PASS in test/all modes) |
| 4 | Allowlist match / empty / missing → exit 0 | PASS (unchanged) | Cases B, C, D, F.*.clean all PASS |
| 5 | Hook self + `tests/fixtures/**` allowlisted | PASS (unchanged) | allowlist files unchanged; mirror `cmp` = 0 |
| 6 | `PostToolUse` matcher is `Edit\|Write\|MultiEdit`, both hooks registered | PASS (unchanged) | `.claude/settings.json:104` still `"Edit\|Write\|MultiEdit"`; both hooks on L107–113 |
| 7 | `templates/base/` byte-identical; `check-sync.sh` PASS | PASS | `cmp` on settings.json / hook / allowlist → 0/0/0. `./scripts/check-sync.sh` → `IDENTICAL: 107, DRIFTED: 0, ROOT_ONLY: 0, TEMPLATE_ONLY: 9, KNOWN_DIFF: 3`, final "PASS: all files in sync." |
| 8 | 6 test cases all green | PASS (strengthened) | `HARNESS_VERIFY_MODE=test ./scripts/verify.local.sh` → 11/11 PASS (Case F expands to 3 tools × {clean, dirty}). Case E now works under a link set that genuinely lacks jq and has only the tools the hook needs — no more "accidentally passing because dirname was a shell builtin" risk |
| 9 | `scripts/verify.local.sh` runs shellcheck → sh -n → jq -e → tests | PASS (reclassified, equivalent) | Execution order under `static`: shellcheck → `sh -n` (18 hooks) → `jq -e` × 2 → `check-sync.sh`. Under `test`: `tests/test-check-mojibake.sh`. Under `all`: static-block then test-block. Plan specified aggregation order; implementation now partitions it by mode per `docs/quality/quality-gates.md:26-27`. Order change: `check-sync.sh` is now classified as static (runs before hook tests in `all` mode). No coverage regression |
| 10 | `./scripts/run-verify.sh` invokes `verify.local.sh`; all pass | PASS | `run-verify.sh:32–38` still invokes `./scripts/verify.local.sh`; exports `HARNESS_VERIFY_MODE`. `./scripts/run-static-verify.sh` → exit 0 (evidence saved to `docs/evidence/verify-2026-04-17-072117.log`) |
| 11 | `check-sync.sh` PASS; repo-only files excluded | PASS (unchanged) | `IDENTICAL: 107, DRIFTED: 0, ROOT_ONLY: 0` |
| 12 | Hook source has no U+FFFD literal | PASS (unchanged) | `printf '\357\277\275'` at runtime only; grep scan clean |
| 13 | AGENTS.md repo map note | PASS (unchanged) | `AGENTS.md:66` still present; this commit does not touch AGENTS.md |

**Delta verdict: 13/13 still PASS.** No acceptance criterion regresses. AC8 and AC9 are strengthened (Case E hardening + mode split alignment).

### Delta static analysis

| Command | Result | Notes |
| --- | --- | --- |
| `sh -n scripts/verify.local.sh` | OK | POSIX clean |
| bash-ism scan on `verify.local.sh` (`[[`, `]]`, `<<<`, `$'...'`, `((`, `))`) | CLEAN | positional-parameter builder replaces the SC2086-disabled word-split; no bash syntax introduced |
| `jq -e . < .claude/settings.json` | OK | matcher L119 now `"Bash\|Edit\|Write\|MultiEdit"` |
| `jq -e . < templates/base/.claude/settings.json` | OK | mirror |
| `cmp .claude/settings.json templates/base/.claude/settings.json` | exit 0 | byte identical |
| `cmp` on hook + allowlist (root vs template) | exit 0, exit 0 | unchanged, still identical |
| `./scripts/check-sync.sh` | PASS | `IDENTICAL: 107, DRIFTED: 0, ROOT_ONLY: 0, TEMPLATE_ONLY: 9, KNOWN_DIFF: 3` |
| `HARNESS_VERIFY_MODE=static ./scripts/verify.local.sh` | exit 0 | shellcheck-skip + 18 `sh -n` + 2 `jq -e` + `check-sync.sh`. Does NOT run `tests/test-check-mojibake.sh` |
| `HARNESS_VERIFY_MODE=test ./scripts/verify.local.sh` | exit 0 | runs ONLY `tests/test-check-mojibake.sh`. Output ends with `PASS: 11 / FAIL: 0` |
| `HARNESS_VERIFY_MODE=all ./scripts/verify.local.sh` | exit 0 | static-block then test-block; same 11/11 PASS |
| `HARNESS_VERIFY_MODE=bogus ./scripts/verify.local.sh` | exit 2 | stderr: `verify.local.sh: unknown HARNESS_VERIFY_MODE=bogus (expected static\|test\|all)` |
| `./scripts/run-static-verify.sh` | exit 0 | full chain via `HARNESS_VERIFY_MODE=static exec ./scripts/run-verify.sh` |
| `./scripts/run-test.sh` | exit 0 | sibling wrapper; test-scope and language `go test` (cached) all PASS. `/test` will re-run authoritatively |
| Matcher symmetry probe | CLEAN | `grep -n matcher` on both settings files shows: `PostToolUse=Edit\|Write\|MultiEdit`, `PostToolUseFailure=Bash\|Edit\|Write\|MultiEdit`. Asymmetry (Codex P3) is closed |
| Case E realistic-PATH probe | JQ_UNREACHABLE_IN_MINIMAL_PATH | Reproduced the link loop in a scratch dir: `jq` is NOT present; `dirname env ln test` are added without introducing `jq`. The jq-missing branch is still exercised |

### Delta documentation drift

| Doc / contract | In sync? | Notes |
| --- | --- | --- |
| `docs/quality/quality-gates.md:26-27` mode split contract | Now honored | `verify.local.sh` joins `packs/languages/_template/verify.sh` as a mode-aware verifier. `packs/languages/golang/verify.sh` still ignores mode (pre-existing repo-wide debt, out of this plan's scope per Non-goals) |
| Plan AC list (L60–72) | STALE (same as prior verify) | Still `- [ ]`. Known item for `/sync-docs` or `/pr`. Not a blocker per `.claude/agent-memory/verifier/feedback_plan_ac_checklist_drift.md` — plan AC checkboxes routinely lag behind implementation |
| Hook message text | unchanged | wording drift flagged in initial verify still applies; optional follow-up |
| Triage report factual accuracy | Minor imprecision noted by re-self-review | The DISMISSED rationale in `docs/reports/codex-triage-mojibake-postedit-guard.md` undersells the value of the `dirname` hardening. Not a verify blocker; `/sync-docs` can consider rewording |
| Commit message claims vs reality | Verified | Commit states "verify.local.sh all modes PASS, test-check-mojibake.sh 11/11 PASS, run-verify.sh all/static/test PASS." Re-run confirms all of these on 2026-04-17T07:22Z |

### Delta observational checks

- Matcher change is symmetric and minimal: 1-line diff × 2 files, mirror preserved. No JSON shape change.
- `verify.local.sh` refactor is structural (function extraction + case dispatch) but preserves command coverage under `all`. Only the internal ordering of `check-sync.sh` vs `tests/test-check-mojibake.sh` has changed (check-sync now runs in the static block, tests in the test block). This is consistent with the documented split.
- The positional-parameter refactor removes the `# shellcheck disable=SC2086` suppression, so once CI runs shellcheck again this file will lint clean without disables — a genuine quality improvement.
- Case E link set extension cannot accidentally re-enable `jq`: `jq` is not in `dirname env ln test sh bash dash cat grep sed mkdir rm cd command pwd printf`, and the test still relies on `PATH="$minimal_path"` absence of `jq`. Verified by probe (see evidence log).

### Delta coverage gaps (no new blockers)

| Gap | Severity | Notes |
| --- | --- | --- |
| shellcheck (still not installed on verify host) | LOW | unchanged from prior verify. `verify.local.sh` wires shellcheck when present; CI remains the authoritative lint runner |
| `packs/languages/golang/verify.sh` ignores `HARNESS_VERIFY_MODE` | LOW | pre-existing repo-wide debt, out of scope per plan Non-goals. Current `run-test.sh` therefore still runs the golang static checks AND go test as one bundle. Not a regression of this PR |
| Real-session PostToolUse dispatch | UNVERIFIED | same as prior verify; belongs to `/test` walkthrough |

### Re-verify verdict

- **PASS (delta).**
- All 13 plan acceptance criteria remain satisfied after 306b23a.
- Codex ACTION_REQUIRED (P3 matcher symmetry) closed by a 1-line × 2-file change; symmetry verified by grep.
- Codex WORTH_CONSIDERING (P2 mode split) implemented; all four mode paths (static / test / all / bogus) produce the documented exit codes.
- Codex DISMISSED (P1) hardened rather than left false-positive; Case E now uses a minimal PATH that genuinely lacks `jq` and has only the tools the hook needs, so the test fails realistically if `dirname` is ever unavailable.
- No CRITICAL, HIGH, or MEDIUM static-analysis finding. Only pre-existing LOW items remain (shellcheck-host-availability, plan AC checkbox drift, golang pack mode-ignoring), none blocking.
- Re-self-review (appended to `docs/reports/self-review-mojibake-postedit-guard.md`) concurs: merge recommendation stands.

### Verified (delta)

- Byte-identical mirror of `.claude/settings.json` and `templates/base/.claude/settings.json` after the MultiEdit matcher fix.
- `PostToolUse` and `PostToolUseFailure` matchers both contain `Bash\|Edit\|Write\|MultiEdit` on root and template (asymmetry closed).
- `HARNESS_VERIFY_MODE` dispatch is strict (`static|test|all` accepted; anything else → exit 2) and mode-exclusive (static block does not run hook tests; test block does not run static checks).
- `scripts/run-static-verify.sh` → exit 0 and `scripts/run-test.sh` → exit 0 at branch HEAD.
- 11/11 test assertions pass in both `test` and `all` modes under a realistic link set.
- No shellcheck `# shellcheck disable=SC2086` remains in `verify.local.sh`.

### Likely but unverified (statically, delta)

- Claude Code actually routes MultiEdit failures through the `PostToolUseFailure` matcher in a real session — the JSON wiring is correct, but end-to-end dispatch is Claude Code runtime behavior that only `/test`'s walkthrough can confirm.

### Not verified (delta)

- shellcheck on the updated `verify.local.sh` and `tests/test-check-mojibake.sh` (tool unavailable on host). CI should catch.

### Minimal additional check to raise confidence (delta)

The same real-session probe recommended in the initial verify, extended by one step: deliberately fail a `MultiEdit` (e.g., stale `old_string`) in a fresh session and confirm `.harness/state/tool_failures.count` increments. Before 306b23a, MultiEdit failures silently did not count; after, they should. If the count moves, the P3 fix is confirmed end-to-end. This is a `/test` walkthrough, not a static check.
