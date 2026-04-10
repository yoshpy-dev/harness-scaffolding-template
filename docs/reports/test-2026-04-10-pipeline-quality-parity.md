# Test report: pipeline-quality-parity

- Date: 2026-04-10
- Plan: (inline test plan from /test invocation — no standalone plan file)
- Tester: tester (pipeline-quality-parity)
- Scope: ralph-pipeline.sh quality parity — syntax, CLI, dry-run, prompt file presence
- Evidence: `docs/evidence/test-2026-04-10-pipeline-quality-parity.log`

## Test execution

| Suite / Command | Tests | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- |
| sh -n (syntax check) | 1 | 1 | 0 | 0 | <1s |
| --help exit code | 1 | 1 | 0 | 0 | <1s |
| --dry-run claude -p calls | 1 | 1 | 0 | 0 | ~2s |
| ralph run --dry-run | 1 | 1 | 0 | 0 | ~2s |
| Prompt file existence (5 files) | 5 | 5 | 0 | 0 | <1s |
| pipeline-review.md absence | 1 | 1 | 0 | 0 | <1s |
| run-test.sh canonical | 1 | 1 | 0 | 0 | <1s |
| **Total** | **11** | **11** | **0** | **0** | ~5s |

## Coverage

- Statement: N/A (shell scripts, no coverage tooling)
- Branch: N/A
- Function: N/A
- Notes: Behavioral dry-run validation exercises the full pipeline phase sequencing (implement → self-review → verify → test → sync-docs → pr) without live claude API calls.

## Failure analysis

| Test | Error | Root cause | Proposed fix |
| --- | --- | --- | --- |
| (none) | — | — | — |

## Regression checks

| Previously broken behavior | Status | Evidence |
| --- | --- | --- |
| `ralph-pipeline.sh --help` exits 1 (pre-fix) | Fixed | Exit code: 0 confirmed in log line 25 |
| `pipeline-review.md` present after rename | Fixed | Absence confirmed in log line 129 |

## Observations

### Test 3: dry-run claude -p call inventory

The `--dry-run` mode logs 6 `claude -p` invocations across the full pipeline:

1. `.impl-prompt.md` — implement (Inner Loop)
2. `.review-prompt.md` — self-review (Inner Loop)
3. `.verify-prompt.md` — verify (Inner Loop)
4. `.test-prompt.md` — test (Inner Loop)
5. `.docs-prompt.md` — sync-docs (Outer Loop)
6. `.pr-prompt.md` — PR creation (Outer Loop)

The test plan specified "3 calls (self-review, verify, test)" as a minimum; the actual pipeline correctly includes implement and PR phases for a total of 6 calls. This is expected behavior.

### Test 3: hook parity warning

During dry-run, hook parity check reports "uncommitted changes" — this is a known and documented behavior (task.json created during test is not committed). Non-blocking, expected in a test environment.

### Test 3: Codex CLI status

`Codex CLI not available — skipping codex review` was logged. The codex binary is not in the PATH on this run, which causes the codex-review phase to be skipped silently. This is expected pipeline behavior.

### Prompt file references

`ralph-pipeline.sh` uses dual-lookup for all 5 prompt files:
1. `${PIPELINE_DIR}/pipeline-<name>.md` (task-level override)
2. `.claude/skills/loop/prompts/pipeline-<name>.md` (canonical location)

All 5 canonical files are confirmed present: `pipeline-inner.md`, `pipeline-self-review.md`, `pipeline-verify.md`, `pipeline-test.md`, `pipeline-outer.md`.

### run-test.sh canonical

`run-test.sh` exits 0 in this run (no non-docs changes tracked by git diff at test time, since the task.json is tracked but this run occurs after cleanup). The scaffold-level exit-2 behavior from run-test.sh noted in MEMORY.md applies when code-like changed files are detected in `git diff`.

## Test gaps

- **Live claude -p execution**: All tests use dry-run. Live API call through the pipeline phases (impl → self-review → verify → test) is not testable without API credentials.
- **Prompt content correctness**: File existence is verified but prompt content correctness (e.g., sidecar signal format, JSON output contract) is not evaluated by this test suite.
- **Multi-slice dry-run**: Test 4 uses a single-slice plan. Multi-slice dependency ordering (deps field in manifest) is not exercised.
- **--resume behavior**: Resume from checkpoint.json is not tested in this suite.
- **pipeline-inner.md prompt routing**: `run_claude()` in dry-run always writes a fake `.impl-prompt.md`; the actual content routing from `pipeline-inner.md` is not verified at runtime.

## Verdict

- Pass: 11/11 — all tests passed
- Fail: 0
- Blocked: 0

Tests pass. Safe to proceed to /pr.
