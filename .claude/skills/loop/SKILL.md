---
name: loop
description: Initialize a Ralph Loop session for autonomous multi-iteration work. Supports two modes — standard (implementation-only loop) and pipeline (full autonomous Inner/Outer Loop with review, verify, test, docs, codex-review, and PR). Invoke automatically when a task benefits from sustained autonomous iteration outside Claude Code.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, AskUserQuestion
---
Set up a Ralph Loop for autonomous iteration outside Claude Code.

## Goals

- Turn a task into a self-contained loop that runs autonomously
- Choose the right mode: **standard** (implementation-only) or **pipeline** (full autonomous pipeline)
- Choose the right prompt template for the task type
- Leave the user ready to start the loop from their terminal

## Steps

### Step 1 — コンテキスト把握

Read `AGENTS.md` and scan `docs/plans/active/` to understand the current project state.

### Step 1.5 — ループモード選択

Use **AskUserQuestion** to let the user pick a loop mode:

- Options:
  1. **標準ループ** — implementation-only loop (`ralph-loop.sh`). Post-implementation pipeline runs manually after the loop.
  2. **パイプラインループ (Recommended)** — full autonomous pipeline (`ralph-pipeline.sh`): implement → self-review → verify → test → sync-docs → codex-review → PR. The loop handles everything from implementation through PR creation.
- If the plan involves large-scale work, multi-step features, or the user wants full autonomy, recommend パイプラインループ.

### Step 2 — タスクタイプ選択

Use **AskUserQuestion** to let the user pick a task type.

- Options: `general` / `refactor` / `test-coverage` / `bugfix` / `docs` / `migration`
- If the task type can be inferred from the conversation context or the active plan, place that option first with `(Recommended)` appended to the label.
- Descriptions for each option:
  - general — default for most tasks
  - refactor — restructuring without behaviour change
  - test-coverage — adding or improving tests
  - bugfix — diagnosing and fixing a bug
  - docs — documentation updates
  - migration — language, framework, or API migration

### Step 3 — 目的と計画ファイルの確認

Use **AskUserQuestion** to confirm the objective and optionally link a plan file.

- Pre-fill the question with an objective inferred from conversation context.
- If `docs/plans/active/` contains plan files, list them as options (plus "None" for no plan).
- If no plans exist, skip the plan selection and only confirm the objective.

### Step 3.5 — Git Worktree 作成

Create an isolated worktree for the loop session:

1. Read the active plan to extract metadata (type, issue number, slug).
2. Determine branch name: `<type>/<issue>/<slug>` (with issue) or `<type>/<slug>` (without issue).
3. Run `git worktree add .claude/worktrees/<slug> -b <branch-name>` to create the worktree.
4. Update the plan file: replace `Branch: TBD` (or any TBD variant) with the actual branch name.
5. All subsequent steps (init script, PROMPT.md generation, etc.) execute inside the worktree directory.

If already on a feature branch (not main/master), skip worktree creation and work in-place.

### Step 4 — init スクリプト実行

Run the init script with the confirmed parameters. Add `--pipeline` if pipeline mode was selected:
```sh
# Standard mode:
./scripts/ralph-loop-init.sh <task-type> "<objective>" [plan-slug]
# Pipeline mode:
./scripts/ralph-loop-init.sh --pipeline <task-type> "<objective>" [plan-slug]
```

### Step 5 — PROMPT.md の承認

Read the generated `.harness/state/loop/PROMPT.md` and display its contents. Then use **AskUserQuestion** to get approval:

- Options:
  1. **このまま実行** — proceed as-is
  2. **調整が必要** — user provides edits; apply them to PROMPT.md and re-display for confirmation
  3. **キャンセル** — abort the loop setup
- If the user chooses "調整が必要", edit PROMPT.md per their instructions, then re-ask for approval.

### Step 6 — 実行コマンドの提示

After approval, print the run command based on the selected mode:

**Standard mode:**
```sh
./scripts/ralph-loop.sh                          # basic
./scripts/ralph-loop.sh --verify                  # with verification
./scripts/ralph-loop.sh --verify --max-iterations 10  # bounded
```

**Pipeline mode (single):**
```sh
./scripts/ralph run                              # auto-detect plan, single pipeline
./scripts/ralph run --preflight --dry-run         # validate setup first
./scripts/ralph run --max-iterations 15           # bounded
```

**Pipeline mode (parallel slices with unified PR):**
```sh
# Directory-based plan (auto-detects --slices mode)
./scripts/ralph run --plan docs/plans/active/<date>-<slug>/ --unified-pr
# Explicit slices mode
./scripts/ralph run --slices --plan <plan-file-or-dir> --unified-pr
# Dry run to verify slice parsing
./scripts/ralph run --slices --plan <plan-dir> --dry-run
```

## Output

- `.harness/state/loop/PROMPT.md` ready to run
- `.harness/state/loop/task.json` with metadata
- `.harness/state/loop/progress.log` initialized
- Worktree path at `.claude/worktrees/<slug>` (if created)
- Terminal command for the user to start the loop

## After the loop

### Standard mode

**Trigger**: When the user returns to the Claude Code session after running `./scripts/ralph-loop.sh`, detect loop completion by reading `.harness/state/loop/status`. If the file exists (any status), automatically proceed with the post-implementation pipeline below. If the user explicitly mentions the loop is done, proceed even without the status file.

1. Read `.harness/state/loop/status` to check outcome
2. Read `.harness/state/loop/progress.log` for what happened
3. Delegate the post-implementation pipeline to subagents per `.claude/rules/subagent-policy.md`:
   a. `Task(subagent_type="reviewer")` → `/self-review` — stop if CRITICAL findings
   b. `Task(subagent_type="verifier")` → `/verify` — stop if fail verdict
   c. `Task(subagent_type="tester")` → `/test` — stop if fail verdict
   d. `Task(subagent_type="doc-maintainer")` → `/sync-docs`
   e. **Invoke `/codex-review` via the Skill tool** (optional, inline — if Codex CLI unavailable, skip to `/pr`)
   f. **Invoke `/pr` via the Skill tool** — do NOT run `gh pr create` directly. The `/pr` skill enforces the Japanese template, pre-checks, and plan archiving.
4. If a worktree was created, ask the user whether to keep or remove it (`git worktree remove .claude/worktrees/<slug>`)

### Pipeline mode

The pipeline handles everything autonomously (self-review, verify, test, docs, codex-review, PR). When the user returns:

1. Run `./scripts/ralph status` to check outcome
2. Read `.harness/state/pipeline/checkpoint.json` for final state
3. If `status` is `complete` and `pr_created` is true — the pipeline finished successfully. Show the PR URL.
4. If `status` is `stuck`, `repair_limit`, or `aborted` — review the failure context and help the user decide next steps (resume, abort, or manual intervention).
5. The pipeline already creates the PR, so no further post-implementation pipeline is needed.

## Anti-bottleneck

When presenting AskUserQuestion choices, always pre-select or recommend the most likely option based on conversation context and the active plan. This minimizes user effort. See the `anti-bottleneck` skill for the full checklist.

## Additional resources

### Standard mode prompts
- [prompts/general.md](prompts/general.md)
- [prompts/refactor.md](prompts/refactor.md)
- [prompts/test-coverage.md](prompts/test-coverage.md)
- [prompts/bugfix.md](prompts/bugfix.md)
- [prompts/docs.md](prompts/docs.md)
- [prompts/migration.md](prompts/migration.md)

### Pipeline mode prompts
- [prompts/pipeline-inner.md](prompts/pipeline-inner.md) — Implementation agent
- [prompts/pipeline-review.md](prompts/pipeline-review.md) — Self-review + verify + test agent
- [prompts/pipeline-outer.md](prompts/pipeline-outer.md) — Sync-docs + codex-review + PR agent

### Scripts
- `scripts/ralph-pipeline.sh` — Single pipeline orchestrator (Inner/Outer Loop)
- `scripts/ralph-orchestrator.sh` — Multi-worktree parallel orchestrator
- `scripts/ralph` — CLI wrapper (plan/run/status/abort)

### Other
- [Recipe: Ralph Loop](../../../docs/recipes/ralph-loop.md)
