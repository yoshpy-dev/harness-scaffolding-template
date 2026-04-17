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
