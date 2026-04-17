# Self-review report: mojibake-postedit-guard

- Date: 2026-04-17
- Plan: docs/plans/active/2026-04-17-mojibake-postedit-guard.md
- Branch: chore/mojibake-postedit-guard
- Reviewer: reviewer subagent (Claude)
- Scope: Diff quality only (naming, readability, unnecessary changes, typos, null safety, debug code, secrets, exception handling, security, maintainability). Spec compliance and test coverage are explicitly out of scope (handled by /verify and /test).

## Evidence reviewed

- `git log main..HEAD` — 4 commits (22642c9, 3311dc6, 911c5ac, 7c4cc9e)
- `git diff main...HEAD --stat` — 14 files, +646/-2
- `.claude/hooks/check_mojibake.sh` (root + templates/base mirror, git mode 100755, byte-for-byte identical: `cmp` → exit 0; SHA `2b2626c...`)
- `.claude/hooks/mojibake-allowlist` (root + mirror, 100644, byte-for-byte identical: `cmp` → exit 0; SHA `d162329...`)
- `.claude/settings.json` + `templates/base/.claude/settings.json` (both show matcher `Edit|Write` → `Edit|Write|MultiEdit` and added hook entry)
- `scripts/verify.local.sh` (100755, repo-only)
- `tests/test-check-mojibake.sh` (100755, bash-based)
- `tests/fixtures/payloads/{edit,write,multiedit}.json`
- `scripts/check-sync.sh` diff — 4 new lines in `ROOT_ONLY_EXCLUSIONS` (`scripts/verify.local.sh`, `tests/`, `docs/plans/active/`)
- `AGENTS.md` diff — 1 line under `.claude/hooks/`
- `grep` for literal U+FFFD bytes (`EF BF BD`) across all new files — **no matches** (`grep` exit 1)
- `sh -n` + `bash -n` on all new shell scripts — clean
- `bash tests/test-check-mojibake.sh` — **11/11 PASS**
- `bash scripts/check-sync.sh` — PASS, 0 DRIFTED / 0 ROOT_ONLY, 107 IDENTICAL
- Cross-comparison with existing hooks (`post_edit_verify.sh`, `pre_bash_guard.sh`, `prompt_gate.sh`) — shebang, `set -eu`, and HOOK_DIR pattern match existing house style
- Manual probes: POSIX `case`-glob behavior with quoted `$REPO_ROOT`, unquoted `$normalised`, and `$(cmd)` inside pattern values
- tech-debt register (`docs/tech-debt/README.md`) — entry for "Per-slice pipeline CRITICAL behavior" already exists; no stale mojibake entry to reconcile

## Findings

| Severity | Area | Finding | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| LOW | maintainability | `tests/test-check-mojibake.sh` cleanup trap unconditionally removes `$REPO_ROOT/.harness/state/mojibake-jq-missing`. If a real Claude Code session on the dev machine legitimately created that marker (jq genuinely missing), running the test erases the signal. The test should scope cleanup to files it created under `$workdir` (Case E already uses `$alt_root/.harness/state/...` for its own marker). | `tests/test-check-mojibake.sh` L51-55; marker write location in hook is `$REPO_ROOT/.harness/state/mojibake-jq-missing` (line 39). | Drop the `rm -f "$REPO_ROOT/.harness/state/mojibake-jq-missing"` line from `cleanup()`. Case E writes to `$alt_root/...`, so no repo-root file is ever created by the test itself. (Non-blocking — the marker is advisory, and a developer can re-trigger it by editing any file without jq.) |
| LOW | maintainability | Hook silently no-ops on malformed JSON payloads. `jq -r '...' 2>/dev/null \|\| true` swallows jq errors, producing an empty `file_path` which routes to `exit 0`. A payload with corrupted JSON (e.g. a future Claude Code bug) would bypass the scan without any log line. | `.claude/hooks/check_mojibake.sh` L44-48. Contract comment L19-21 says "If file does not exist, is empty, or has no U+FFFD, exit 0" but does not mention malformed JSON. | Consider emitting a one-line stderr warning when the payload is non-empty but `file_path` extraction fails, e.g. `printf 'check_mojibake.sh: could not extract file_path from payload; skipping.\n' >&2`. Or tighten the contract comment to say "malformed payload → silent exit 0 (fail-open)". Not blocking — fail-open on malformed payload is a defensible choice. |
| LOW | security / robustness | `[ ! -f "$file_path" ]` follows symlinks (POSIX `-f` returns true for symlink-to-regular-file). A malicious or accidental payload with `file_path` pointing to `/etc/passwd` would cause the hook to `grep -q` over it. Impact is minimal (read-only grep, no output on miss, no information leak because hook only exits 0/2), but the hook will do work on paths outside the repo root. | `.claude/hooks/check_mojibake.sh` L50. Probe: `ln -sf /etc/passwd /tmp/x; [ -f /tmp/x ]` → true. | Optional hardening: constrain scan to files under `$REPO_ROOT` by rejecting `$file_path` that does not start with `$REPO_ROOT` (or a user-specified allowlist of prefixes). Not a vulnerability today; log as a tech-debt note only if the hook is ever reused in multi-tenant contexts. |
| LOW | readability | `HOOK_REPO_ROOT` is documented in the header comment as "used by tests", which is accurate, but the name does not follow any existing hook convention (other hooks use HOOK_DIR only and derive REPO_ROOT relative to the script). The override is legitimate because the test creates synthetic repo trees, but the name is the only public contract for that indirection. | `.claude/hooks/check_mojibake.sh` L27-28, L33; `tests/test-check-mojibake.sh` uses it 7 times. | No change required. The `HOOK_REPO_ROOT` name is grep-able and the comment is adequate. Mention in PR description that this env var is test-only and should not be set in normal Claude Code sessions. |
| LOW | readability | `verify.local.sh` builds `$hook_scripts` as an unquoted space-separated string and intentionally disables `SC2086`. This works (all paths are internal globs, no shell metacharacters), but using a POSIX array-equivalent (positional parameters with `set --`) would be clearer and shellcheck-clean without a disable comment. | `scripts/verify.local.sh` L30-36. | Optional refactor: replace the loop + unquoted expansion with `set -- .claude/hooks/*.sh templates/base/.claude/hooks/*.sh scripts/verify.local.sh tests/test-check-mojibake.sh; for f do [ -f "$f" ] || continue; ...; done` + `run "shellcheck" shellcheck "$@"`. Not blocking. |
| LOW | maintainability | `scripts/check-sync.sh` adds `"tests/"` as a ROOT_ONLY prefix exclusion. This silently excludes any future test file from the sync check. That's correct for today (tests/ is repo-only), but a future contributor adding a test that should be distributed (e.g. a user-facing smoke test) would see it invisibly excluded. | `scripts/check-sync.sh` L38-39. | Not a change request. Consider leaving a comment above the entry pointing at `scripts/verify.local.sh`'s "not shipped to scaffolded projects" note so the rationale is discoverable when editing check-sync.sh. |
| LOW | maintainability | Plan mentions the AGENTS.md addition as "2 行注記" (two-line annotation) in the plan's acceptance criteria and implementation outline, but the actual addition is a single nested bullet. Not a bug — the plan drifted from implementation on wording only, and the one-line form fits AGENTS.md's "keep short" rule. | Plan L27, L56, L101 vs. AGENTS.md diff (1 line added under `.claude/hooks/`). | No change needed; flagged only to note that the progress checklist item "AGENTS.md repo map に 2 行注記" (line 72 of plan) is now satisfied by one line. |

No CRITICAL, HIGH, or MEDIUM findings. All diffs reviewed are internally consistent; the plan's acceptance criteria are reflected in the code; tests pass 11/11; sync-check passes; byte-for-byte mirror verified.

## Positive notes

- **Byte-for-byte mirror discipline**: `cmp` confirms both the hook script and the allowlist are identical between root and `templates/base/`, and git modes (100755 for scripts, 100644 for data file) match. `chmod +x` was not forgotten.
- **No U+FFFD literal in sources**: grep across all new files returned exit 1. The runtime-construction of `FFFD="$(printf '\357\277\275')"` (hook line 83) is correctly paired with the allowlist self-entry (`.claude/hooks/check_mojibake.sh`), giving belt-and-suspenders protection against self-detection.
- **Defense-in-depth for `$REPO_ROOT` globbing**: `case "$file_path" in "$REPO_ROOT"/*)` correctly quotes `$REPO_ROOT`, so even a REPO_ROOT containing glob metacharacters (e.g. `/tmp/[weird]/root`) is treated as literal (verified via probe). Unquoted `$normalised` in the allowlist loop is glob-expanded as intended, but `$(...)` inside an allowlist line is NOT command-substituted (POSIX case-pattern semantics), so malicious allowlist entries cannot execute code.
- **fail-open-with-warning is deliberate and documented**: The jq-missing path writes a marker to `.harness/state/mojibake-jq-missing` so later tooling can detect the degraded state. The rationale is in the hook's header comment (L18-21), matching Codex finding #2 from the planning advisory.
- **Commit slicing is coherent**: 4 commits, each mapping to a single concern (hook + tests / settings registration / AGENTS.md note / plan checkbox flip). This is exactly the pattern called for by `.claude/rules/git-commit-strategy.md` (commit after each passing slice).
- **Existing hook style preserved**: same shebang (`#!/usr/bin/env sh`), same `set -eu`, same `HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"` idiom as `post_edit_verify.sh` and `pre_bash_guard.sh`. Reviewer can scan hook sources without context-switch.
- **Fixture design is robust**: the `__FILE_PATH__` placeholder in `tests/fixtures/payloads/*.json` means schema changes in Claude Code (e.g. extra fields in `tool_input`) only need one fixture update, not a test rewrite. The Edit fixture deliberately includes an escaped `\"quotes\"` field — this exercises the sed-fallback edge case flagged in the planning risk register.
- **No debug code / no hardcoded secrets / no swallowed security-relevant errors**: searched for `eval`, `sh -c`, `bash -c`, `exec `, and dynamic execution — none. The only `2>/dev/null` suppressions are on non-security-relevant ops (directory creation in `.harness/state`, marker file touch, jq extraction).
- **Rollback plan is concrete**: plan section "Rollout or rollback notes" (L156-158) lists all 8 file-level actions needed to retire the hook. Low future cost.

## Tech debt identified

| Debt item | Impact | Why deferred | Trigger to pay down | Related plan/report |
| --- | --- | --- | --- | --- |
| `check_mojibake.sh` is a temporary mitigation for upstream Claude Code Issue #43746. Hook, allowlist, tests, fixtures, settings.json entry, AGENTS.md line, and check-sync.sh exclusions must all be removed when upstream ships a fix. | Carrying permanent hooks for fixed upstream bugs becomes dead weight; the hook scans every `Edit|Write|MultiEdit` on every session. | Upstream fix not released yet; interim detection is needed to keep the workflow correct. | Claude Code release that closes Issue #43746 and one week of observed non-recurrence locally. | `docs/plans/active/2026-04-17-mojibake-postedit-guard.md` |
| Hook silently passes on malformed JSON payloads (jq extract fails → empty file_path → exit 0). No log line, no marker file. If Claude Code ever emits a broken payload, the mojibake scan degrades without visibility. | Low (detection gap narrows but not eliminated; malformed payload is not the bug this hook targets). | Keeping the hook minimal and fail-open on parsing errors; adding a warning path adds conditional complexity. | A reported case where U+FFFD made it through because the payload was malformed. | `docs/reports/self-review-mojibake-postedit-guard.md` (this file) |

_The first entry should be appended to `docs/tech-debt/README.md`. The second is lower priority and can be tracked only inline in this report._

## Recommendation

- **Merge**: YES.
- **Blockers**: none (no CRITICAL or HIGH findings).
- **Follow-ups** (all LOW, none gate merge):
  1. Narrow `tests/test-check-mojibake.sh` cleanup to `$workdir`-only (remove the `rm -f "$REPO_ROOT/.harness/state/mojibake-jq-missing"` line). Small follow-up PR or amend in `/verify` cycle.
  2. Optionally add a one-line stderr warning when jq extraction fails on a non-empty payload (covers the silent-malformed-JSON path).
  3. Optionally add a comment in `scripts/check-sync.sh` cross-referencing `scripts/verify.local.sh`'s "not shipped to scaffolded projects" contract so the `"tests/"` exclusion rationale is self-evident.
  4. Append the "temporary mitigation" entry to `docs/tech-debt/README.md` so the retirement trigger is tracked alongside other debt items.

Hand off to `/verify` for spec-compliance + static-analysis (`./scripts/run-verify.sh` is reported green by the user; verifier should re-confirm all 13 acceptance criteria map to diff evidence).
