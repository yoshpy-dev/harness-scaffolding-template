# Tech debt

Record debt that should not disappear into chat history.

Recommended fields:
- debt item
- impact
- why it was deferred
- trigger for paying it down
- related plan or report

## Entries

| Debt item | Impact | Why deferred | Trigger to pay down | Related plan/report |
| --- | --- | --- | --- | --- |
| Per-slice pipelines do NOT stop on CRITICAL self-review findings | Differs from standard `/work` flow behavior | Autonomous pipelines benefit from letting verify/test confirm true positives before halting | If false-negative CRITICAL findings slip through to merge | `.claude/rules/post-implementation-pipeline.md` |
| `ralph status --json` outputs plain text, not JSON | AC11 partially met; machine consumption broken | Phase 6a scope — table/JSON rendering deferred to Phase 6b Go native | Phase 6b implementation | `docs/plans/active/2026-04-16-ralph-cli-tool.md` |
| `ralph init/upgrade` lack transactional safety (journal.toml, staging) | AC17/18/21 not met; interrupted init can leave inconsistent state | Development cost vs. shipping core CLI functionality first | Before v1.0 release or after first user report of interrupted init corruption | `docs/plans/active/2026-04-16-ralph-cli-tool.md` |
| Phase 6b: Go native pipeline migration pending | Pipeline runs via shell wrapper (Phase 6a) | 3400 lines of shell → Go is a major effort requiring parity tests | Next PR; parity tests must pass before shell scripts are removed | `docs/plans/active/2026-04-16-ralph-cli-tool.md` |
