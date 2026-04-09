#!/usr/bin/env sh
set -eu

# Ralph Orchestrator — multi-worktree parallel pipeline execution
#
# Reads a Ralph Loop plan (with vertical slice definitions), creates a Git
# worktree for each independent slice, and runs ralph-pipeline.sh in each
# worktree concurrently. Slices with dependencies wait for prerequisites.
#
# Requires: git, jq, ralph-pipeline.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKTREE_BASE=".claude/worktrees"
ORCH_STATE=".harness/state/orchestrator"
EVIDENCE_DIR="docs/evidence"
PLAN_FILE=""
MAX_PARALLEL=4
MAX_ITERATIONS=20
DRY_RUN=0
UNIFIED_PR=0

usage() {
  cat <<'USAGE'
Usage: ralph-orchestrator.sh --plan <plan-file-or-directory> [OPTIONS]

Multi-worktree parallel pipeline orchestrator for Ralph Loop.

Options:
  --plan <path>          Path to a plan file (inline slices) or plan directory (slice-*.md files) (required)
  --max-parallel N       Max concurrent worktree pipelines (default: 4)
  --max-iterations N     Per-slice iteration cap passed to ralph-pipeline.sh (default: 20)
  --unified-pr           Create a single unified PR instead of per-slice PRs
  --dry-run              Parse plan and show what would run without executing
  -h, --help             Show this help
USAGE
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --plan)            shift; PLAN_FILE="${1:?requires a file path}" ;;
    --max-parallel)    shift; MAX_PARALLEL="${1:?requires a number}" ;;
    --max-iterations)  shift; MAX_ITERATIONS="${1:?requires a number}" ;;
    --unified-pr)      UNIFIED_PR=1 ;;
    --dry-run)         DRY_RUN=1 ;;
    -h|--help)         usage ;;
    *)                 echo "Unknown option: $1"; usage ;;
  esac
  shift
done

if [ -z "$PLAN_FILE" ]; then
  echo "Error: --plan <file-or-directory> is required"
  usage
fi
if [ ! -f "$PLAN_FILE" ] && [ ! -d "$PLAN_FILE" ]; then
  echo "Error: --plan target not found: ${PLAN_FILE}"
  usage
fi

# ═══════════════════════════════════════════════════════════════════
# Utility functions
# ═══════════════════════════════════════════════════════════════════

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
ts_file() { date -u '+%Y-%m-%d-%H%M%S'; }
log() { printf '[%s] %s\n' "$(ts)" "$*"; }
log_error() { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; }

# ═══════════════════════════════════════════════════════════════════
# Plan parsing — extract slices from markdown
# ═══════════════════════════════════════════════════════════════════

# Parse slice definitions from the plan.
# Output: one line per slice: slug|objective|dependencies|affected_files|plan_file_path
# Automatically detects input type:
#   - Directory with slice-*.md files → parse_slices_directory()
#   - Single markdown file with ### Slice N: headers → parse_slices_inline()
parse_slices() {
  _plan="$1"

  if [ -d "$_plan" ]; then
    parse_slices_directory "$_plan"
  else
    parse_slices_inline "$_plan"
  fi
}

# Parse slices from a directory of slice-*.md files.
# Supports two field formats per slice:
#   1. Inline: "- Objective: ...", "- Dependencies: ...", "- Affected files: ..."
#   2. Section headers: "## Objective" (next non-empty line), "## Dependencies", "## Affected files"
parse_slices_directory() {
  _plan_dir="$1"
  _found=0

  for _slice_file in "$_plan_dir"/slice-*.md; do
    [ -f "$_slice_file" ] || continue
    _found=1

    # Extract slug from filename: slice-1-auth-api.md -> 1-auth-api
    # Keeps the number prefix to guarantee uniqueness across slices
    _basename="$(basename "$_slice_file" .md)"
    _slug="$(echo "$_basename" | sed 's/^slice-//')"

    _objective=""
    _deps=""
    _files=""
    _section=""

    while IFS= read -r line; do
      case "$line" in
        # --- Inline format ---
        "- Objective: "*)
          _objective="$(echo "$line" | sed 's/^- Objective: *//')"
          _section=""
          ;;
        "- Dependencies: "*)
          _raw_deps="$(echo "$line" | sed 's/^- Dependencies: *//')"
          case "$_raw_deps" in
            none|None|"") _deps="" ;;
            *) _deps="$_raw_deps" ;;
          esac
          _section=""
          ;;
        "- Affected files: "*)
          _files="$(echo "$line" | sed 's/^- Affected files: *//' | tr -d '[]')"
          _section=""
          ;;
        # --- Section header format ---
        "## Objective"*)   _section="objective" ;;
        "## Dependencies"*)  _section="deps" ;;
        "## Affected files"*) _section="files" ;;
        "## "*)            _section="" ;;
        # --- Section body ---
        *)
          if [ -n "$_section" ] && [ -n "$line" ]; then
            case "$_section" in
              objective)
                if [ -z "$_objective" ]; then
                  _objective="$line"
                fi
                ;;
              deps)
                _raw_dep="$(echo "$line" | sed 's/^- *//' | tr -d '`')"
                case "$_raw_dep" in
                  none|None) ;;
                  *)
                    if [ -n "$_raw_dep" ]; then
                      _deps="${_deps:+${_deps}, }${_raw_dep}"
                    fi
                    ;;
                esac
                ;;
              files)
                _raw_file="$(echo "$line" | sed 's/^- *//' | tr -d '`')"
                if [ -n "$_raw_file" ]; then
                  _files="${_files:+${_files}, }${_raw_file}"
                fi
                ;;
            esac
          fi
          ;;
      esac
    done < "$_slice_file"

    printf '%s|%s|%s|%s|%s\n' "$_slug" "$_objective" "$_deps" "$_files" "$_slice_file"
  done

  if [ "$_found" -eq 0 ]; then
    return 1
  fi
}

# Parse slices from inline ### Slice N: headers in a single plan file (legacy)
parse_slices_inline() {
  _plan="$1"
  _in_slice=0
  _slug=""
  _objective=""
  _deps=""
  _files=""

  while IFS= read -r line; do
    # Detect slice header: ### Slice N: <name>
    case "$line" in
      "### Slice "*)
        # Emit previous slice if any
        if [ -n "$_slug" ]; then
          printf '%s|%s|%s|%s|%s\n' "$_slug" "$_objective" "$_deps" "$_files" "$_plan"
        fi
        # Extract slug from header (e.g., "### Slice 1: auth-module" -> "auth-module")
        _raw_name="$(echo "$line" | sed 's/^### Slice [0-9]*: *//')"
        _slug="$(echo "$_raw_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')"
        _objective=""
        _deps=""
        _files=""
        _in_slice=1
        continue
        ;;
    esac

    if [ "$_in_slice" -eq 1 ]; then
      case "$line" in
        "- Objective: "*)
          _objective="$(echo "$line" | sed 's/^- Objective: *//')"
          ;;
        "- Dependencies: "*)
          _raw_deps="$(echo "$line" | sed 's/^- Dependencies: *//')"
          case "$_raw_deps" in
            none|None|"") _deps="" ;;
            *) _deps="$_raw_deps" ;;
          esac
          ;;
        "- Affected files: "*)
          _files="$(echo "$line" | sed 's/^- Affected files: *//' | tr -d '[]')"
          ;;
        "## "*)
          # New top-level section — end slice parsing
          if [ -n "$_slug" ]; then
            printf '%s|%s|%s|%s|%s\n' "$_slug" "$_objective" "$_deps" "$_files" "$_plan"
          fi
          _in_slice=0
          _slug=""
          break
          ;;
        "### Shared-file locklist"*)
          # Skip locklist header
          ;;
      esac
    fi
  done < "$_plan"

  # Emit last slice
  if [ -n "$_slug" ]; then
    printf '%s|%s|%s|%s|%s\n' "$_slug" "$_objective" "$_deps" "$_files" "$_plan"
  fi
}

# Parse shared-file locklist from the plan (dual-mode: directory or file)
parse_locklist() {
  _plan="$1"

  if [ -d "$_plan" ]; then
    _manifest="${_plan}/_manifest.md"
    if [ -f "$_manifest" ]; then
      parse_locklist_from_file "$_manifest"
    fi
  else
    parse_locklist_from_file "$_plan"
  fi
}

parse_locklist_from_file() {
  _file="$1"
  _in_locklist=0

  while IFS= read -r line; do
    case "$line" in
      "### Shared-file locklist"*|"## Shared-file locklist"*)
        _in_locklist=1
        continue
        ;;
    esac

    if [ "$_in_locklist" -eq 1 ]; then
      case "$line" in
        "### "*|"## "*)
          # Next section
          break
          ;;
        "- "*)
          # Extract file path (remove leading "- " and surrounding backticks)
          echo "$line" | sed 's/^- *//' | tr -d '`'
          ;;
      esac
    fi
  done < "$_file"
}

# Auto-detect shared files: files that appear in more than one slice
detect_shared_files() {
  _slices_data="$1"
  _all_files=""

  echo "$_slices_data" | while IFS='|' read -r _s _o _d files _p; do
    echo "$files" | tr ',' '\n' | while IFS= read -r f; do
      _f="$(echo "$f" | tr -d ' ')"
      if [ -n "$_f" ]; then
        echo "$_f"
      fi
    done
  done | sort | uniq -d
}

# Check if a slice has dependencies on locked files that another running slice owns
check_locklist_conflict() {
  _slice_files="$1"
  _locklist="$2"
  _running_slices_files="$3"

  echo "$_slice_files" | tr ',' '\n' | while IFS= read -r f; do
    _f="$(echo "$f" | tr -d ' ')"
    if [ -z "$_f" ]; then continue; fi
    # Check if this file is in the locklist
    if echo "$_locklist" | grep -qF "$_f"; then
      # Check if any running slice also touches this file
      if echo "$_running_slices_files" | grep -qF "$_f"; then
        echo "$_f"
        return 0
      fi
    fi
  done
}

# ═══════════════════════════════════════════════════════════════════
# Integration branch management
# ═══════════════════════════════════════════════════════════════════

INTEGRATION_BRANCH=""
PLAN_SLUG=""

# Extract slug from plan path for branch naming
extract_plan_slug() {
  _path="$1"
  if [ -d "$_path" ]; then
    basename "$_path"
  else
    basename "$_path" .md
  fi
}

# Create an integration branch for unified PR workflow
create_integration_branch() {
  _slug="$1"
  _base="$2"
  INTEGRATION_BRANCH="integration/${_slug}"

  if git rev-parse --verify "$INTEGRATION_BRANCH" >/dev/null 2>&1; then
    log "Integration branch already exists: ${INTEGRATION_BRANCH}"
    return 0
  fi

  git branch "$INTEGRATION_BRANCH" "$_base" 2>/dev/null || {
    log_error "Failed to create integration branch: ${INTEGRATION_BRANCH}"
    return 1
  }
  log "Created integration branch: ${INTEGRATION_BRANCH} (from ${_base})"
}

# ═══════════════════════════════════════════════════════════════════
# Worktree management
# ═══════════════════════════════════════════════════════════════════

create_worktree() {
  _slug="$1"
  # Use integration branch as base if UNIFIED_PR mode, otherwise current branch
  if [ "$UNIFIED_PR" -eq 1 ] && [ -n "$INTEGRATION_BRANCH" ]; then
    _base_branch="$INTEGRATION_BRANCH"
  else
    _base_branch="$(git rev-parse --abbrev-ref HEAD)"
  fi

  _wt_path="${WORKTREE_BASE}/${_slug}"

  # In unified PR mode, use slice/<plan-slug>/<name> branch naming
  if [ "$UNIFIED_PR" -eq 1 ] && [ -n "$PLAN_SLUG" ]; then
    _wt_branch="slice/${PLAN_SLUG}/${_slug}"
  else
    _wt_branch="slice/${_slug}"
  fi

  if [ -d "$_wt_path" ]; then
    log "Worktree already exists: ${_wt_path}"
    return 0
  fi

  mkdir -p "$WORKTREE_BASE"
  git worktree add -b "$_wt_branch" "$_wt_path" "$_base_branch" 2>/dev/null || {
    # Branch might already exist
    git worktree add "$_wt_path" "$_wt_branch" 2>/dev/null || {
      log_error "Failed to create worktree for slice: ${_slug}"
      return 1
    }
  }
  log "Created worktree: ${_wt_path} (branch: ${_wt_branch}, base: ${_base_branch})"
}

remove_worktree() {
  _slug="$1"
  _wt_path="${WORKTREE_BASE}/${_slug}"

  if [ -d "$_wt_path" ]; then
    git worktree remove "$_wt_path" --force 2>/dev/null || true
    log "Removed worktree: ${_wt_path}"
  fi
}

# ═══════════════════════════════════════════════════════════════════
# Slice execution
# ═══════════════════════════════════════════════════════════════════

# Run ralph-pipeline.sh in a worktree for a single slice
run_slice() {
  _slug="$1"
  _objective="$2"
  _slice_plan="${3:-}"
  _wt_path="${WORKTREE_BASE}/${_slug}"
  _log_file="${ORCH_STATE}/slice-${_slug}.log"

  log "Starting slice: ${_slug} — ${_objective}"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[DRY RUN] Would run ralph-pipeline.sh in ${_wt_path}"
    log "[DRY RUN] Slice plan: ${_slice_plan:-none}"
    echo "complete" > "${ORCH_STATE}/slice-${_slug}.status"
    return 0
  fi

  # Copy slice plan into the worktree so the agent can read it via relative path
  _wt_plan_path=""
  if [ -n "$_slice_plan" ] && [ -f "$_slice_plan" ]; then
    _wt_plan_dir="${_wt_path}/$(dirname "$_slice_plan")"
    mkdir -p "$_wt_plan_dir"
    cp "$_slice_plan" "${_wt_path}/${_slice_plan}"
    _wt_plan_path="$_slice_plan"
  fi

  # Initialize pipeline state in the worktree
  (
    cd "$_wt_path"
    "${SCRIPT_DIR}/ralph-loop-init.sh" --pipeline general "$_objective" "$_wt_plan_path" 2>&1 || true
    "${SCRIPT_DIR}/ralph-pipeline.sh" \
      --max-iterations "$MAX_ITERATIONS" \
      2>&1
  ) > "$_log_file" 2>&1 &

  _pid=$!
  echo "$_pid" > "${ORCH_STATE}/slice-${_slug}.pid"
  echo "running" > "${ORCH_STATE}/slice-${_slug}.status"
  log "Slice ${_slug} started (PID: ${_pid})"
}

# Check if a slice has completed
check_slice_status() {
  _slug="$1"
  _status_file="${ORCH_STATE}/slice-${_slug}.status"
  _pid_file="${ORCH_STATE}/slice-${_slug}.pid"

  if [ ! -f "$_status_file" ]; then
    echo "pending"
    return
  fi

  _status="$(cat "$_status_file")"
  if [ "$_status" != "running" ]; then
    echo "$_status"
    return
  fi

  # Check if PID is still running
  if [ -f "$_pid_file" ]; then
    _pid="$(cat "$_pid_file")"
    if kill -0 "$_pid" 2>/dev/null; then
      echo "running"
    else
      # Process ended — check exit code via worktree checkpoint
      _wt_path="${WORKTREE_BASE}/${_slug}"
      _ckpt="${_wt_path}/.harness/state/pipeline/checkpoint.json"
      if [ -f "$_ckpt" ]; then
        _ckpt_status="$(jq -r '.status // "unknown"' "$_ckpt" 2>/dev/null || echo "unknown")"
        echo "$_ckpt_status" > "$_status_file"
        echo "$_ckpt_status"
      else
        echo "failed" > "$_status_file"
        echo "failed"
      fi
    fi
  else
    echo "unknown"
  fi
}

# Wait for a specific slice to complete
wait_for_slice() {
  _slug="$1"
  _pid_file="${ORCH_STATE}/slice-${_slug}.pid"

  if [ ! -f "$_pid_file" ]; then
    return 0
  fi

  _pid="$(cat "$_pid_file")"
  if kill -0 "$_pid" 2>/dev/null; then
    log "Waiting for slice ${_slug} (PID: ${_pid})..."
    wait "$_pid" 2>/dev/null || true
  fi
}

# ═══════════════════════════════════════════════════════════════════
# Integration merge check
# ═══════════════════════════════════════════════════════════════════

integration_merge_check() {
  _base_branch="$(git rev-parse --abbrev-ref HEAD)"
  _conflicts=0
  _merge_branch="integration-check-$(ts_file)"

  log "Running integration merge check..."

  # Create a temporary merge branch
  git checkout -b "$_merge_branch" "$_base_branch" 2>/dev/null || {
    log_error "Failed to create merge check branch"
    return 1
  }

  # Try merging each slice branch (use for loop to avoid pipe-subshell variable loss)
  for status_file in "${ORCH_STATE}"/slice-*.status; do
    [ -f "$status_file" ] || continue
    _s="$(basename "$status_file" | sed 's/^slice-//;s/\.status$//')"
    _status="$(cat "$status_file")"
    if [ "$_status" = "complete" ]; then
      _slice_branch="slice/${_s}"
      log "Merging ${_slice_branch}..."
      if ! git merge --no-commit --no-ff "$_slice_branch" 2>/dev/null; then
        log_error "CONFLICT merging ${_slice_branch}"
        git merge --abort 2>/dev/null || true
        _conflicts=$((_conflicts + 1))
      else
        git reset --hard HEAD 2>/dev/null || true
      fi
    fi
  done

  # Clean up merge branch
  git checkout "$_base_branch" 2>/dev/null || true
  git branch -D "$_merge_branch" 2>/dev/null || true

  if [ "$_conflicts" -gt 0 ]; then
    log_error "Integration check found ${_conflicts} conflict(s). Manual resolution needed."
    return 1
  fi

  log "Integration merge check passed"
  return 0
}

# Sequential merge of completed slice branches into the integration branch.
# Merges slices in file-order (which matches dependency order from parse_slices).
# Aborts on first conflict.
integration_merge() {
  _int_branch="$1"
  _slices_file="$2"
  _conflicts=0
  _merged=0

  log "Running sequential merge into ${_int_branch}..."

  # Save current branch to return to later
  _orig_branch="$(git rev-parse --abbrev-ref HEAD)"

  git checkout "$_int_branch" 2>/dev/null || {
    log_error "Failed to checkout integration branch: ${_int_branch}"
    return 1
  }

  # Merge each completed slice in order
  while IFS='|' read -r s _o _d _f _p; do
    _status_file="${ORCH_STATE}/slice-${s}.status"
    [ -f "$_status_file" ] || continue
    _status="$(cat "$_status_file")"
    if [ "$_status" != "complete" ]; then
      log "Skipping slice ${s} (status: ${_status})"
      continue
    fi

    # Determine the slice branch name
    if [ -n "$PLAN_SLUG" ]; then
      _slice_branch="slice/${PLAN_SLUG}/${s}"
    else
      _slice_branch="slice/${s}"
    fi

    log "Merging ${_slice_branch} into ${_int_branch}..."
    if ! git merge --no-ff "$_slice_branch" -m "$(cat <<MERGE_EOF
chore: merge ${_slice_branch} into ${_int_branch}
MERGE_EOF
)" 2>/dev/null; then
      log_error "CONFLICT merging ${_slice_branch} into ${_int_branch}"
      git merge --abort 2>/dev/null || true
      _conflicts=$((_conflicts + 1))
      # Return to original branch before reporting error
      git checkout "$_orig_branch" 2>/dev/null || true
      log_error "Sequential merge aborted at slice ${s}. ${_merged} slice(s) merged before conflict."
      return 1
    fi
    _merged=$((_merged + 1))
    log "Merged ${_slice_branch} (${_merged} total)"
  done < "$_slices_file"

  # Return to original branch
  git checkout "$_orig_branch" 2>/dev/null || true

  log "Sequential merge complete: ${_merged} slice(s) merged into ${_int_branch}"
  return 0
}

# Create a unified PR from the integration branch to the base branch
create_unified_pr() {
  _int_branch="$1"
  _base_branch="$2"
  _plan_slug="$3"
  _total_slices="$4"
  _completed="$5"

  log "Creating unified PR: ${_int_branch} → ${_base_branch}..."

  # Push integration branch
  git push -u origin "$_int_branch" 2>/dev/null || {
    log_error "Failed to push integration branch"
    return 1
  }

  # Create PR
  _pr_url="$(gh pr create \
    --base "$_base_branch" \
    --head "$_int_branch" \
    --title "feat: ${_plan_slug}" \
    --body "$(cat <<PR_EOF
## Summary

Unified PR for Ralph Loop parallel slices: ${_plan_slug}

- Total slices: ${_total_slices}
- Completed: ${_completed}
- Integration branch: ${_int_branch}

## Slice branches merged

$(for sf in "${ORCH_STATE}"/slice-*.status; do
  [ -f "$sf" ] || continue
  _name="$(basename "$sf" | sed 's/^slice-//;s/\.status$//')"
  _ss="$(cat "$sf")"
  printf '- %s: %s\n' "$_name" "$_ss"
done)

## Test plan

- [ ] All slice pipelines passed (self-review, verify, test)
- [ ] Integration merge passed without conflicts
- [ ] CI checks pass on this PR

Generated by Ralph Orchestrator
PR_EOF
)" 2>&1)" || {
    log_error "Failed to create unified PR"
    return 1
  }

  log "Unified PR created: ${_pr_url}"
  echo "$_pr_url"
}

# ═══════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════

main() {
  log "═══ Ralph Orchestrator ═══"
  log "Plan: ${PLAN_FILE}"
  log "Max parallel: ${MAX_PARALLEL}"
  log "Max iterations per slice: ${MAX_ITERATIONS}"
  log "Unified PR: ${UNIFIED_PR}"
  log "Dry run: ${DRY_RUN}"
  log ""

  # --- Extract plan slug and set up integration branch ---
  PLAN_SLUG="$(extract_plan_slug "$PLAN_FILE")"
  _base_branch="$(git rev-parse --abbrev-ref HEAD)"

  if [ "$UNIFIED_PR" -eq 1 ]; then
    create_integration_branch "$PLAN_SLUG" "$_base_branch"
    log "Integration branch: ${INTEGRATION_BRANCH}"
    log ""
  fi

  # --- Parse plan ---
  slices_data="$(parse_slices "$PLAN_FILE")"
  locklist="$(parse_locklist "$PLAN_FILE")"

  # Auto-detect additional shared files
  auto_shared="$(detect_shared_files "$slices_data")"
  if [ -n "$auto_shared" ]; then
    locklist="$(printf '%s\n%s' "$locklist" "$auto_shared" | sort -u)"
    log "Auto-detected shared files added to locklist:"
    echo "$auto_shared" | while IFS= read -r f; do
      log "  - $f"
    done
  fi

  _slice_count="$(echo "$slices_data" | grep -c '|' || echo 0)"
  log "Found ${_slice_count} slice(s)"

  if [ "$_slice_count" -eq 0 ]; then
    log_error "No slices found in plan. Ensure plan has '### Slice N: <name>' sections or is a directory with slice-*.md files."
    exit 1
  fi

  log ""
  log "Slices:"
  echo "$slices_data" | while IFS='|' read -r s o d f p; do
    log "  ${s}: ${o} (deps: ${d:-none}, plan: ${p:-inline})"
  done
  log ""

  if [ -n "$locklist" ]; then
    log "Shared-file locklist:"
    echo "$locklist" | while IFS= read -r f; do
      log "  - $f"
    done
    log ""
  fi

  mkdir -p "$ORCH_STATE" "$EVIDENCE_DIR"

  # Save orchestrator state
  _started="$(ts)"
  cat > "${ORCH_STATE}/orchestrator.json" <<ORCH_JSON
{
  "plan": "${PLAN_FILE}",
  "started": "${_started}",
  "max_parallel": ${MAX_PARALLEL},
  "max_iterations": ${MAX_ITERATIONS},
  "unified_pr": $([ "$UNIFIED_PR" -eq 1 ] && echo true || echo false),
  "status": "running"
}
ORCH_JSON

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[DRY RUN] Plan parsed successfully. Would create ${_slice_count} worktree(s)."
    if [ "$UNIFIED_PR" -eq 1 ]; then
      log "[DRY RUN] Integration branch: ${INTEGRATION_BRANCH}"
    fi
    echo "$slices_data" | while IFS='|' read -r s o d f p; do
      if [ "$UNIFIED_PR" -eq 1 ] && [ -n "$PLAN_SLUG" ]; then
        _br="slice/${PLAN_SLUG}/${s}"
      else
        _br="slice/${s}"
      fi
      log "[DRY RUN] Slice ${s}: worktree at ${WORKTREE_BASE}/${s}, branch ${_br}, plan: ${p:-inline}"
    done
    return 0
  fi

  # --- Save slices to temp file for iteration without pipe-subshell ---
  _slices_file="${ORCH_STATE}/.slices.dat"
  echo "$slices_data" > "$_slices_file"

  # --- Create worktrees ---
  while IFS='|' read -r s o d f p; do
    create_worktree "$s"
  done < "$_slices_file"

  # --- Execute slices respecting dependencies ---
  _running=0
  _completed=0
  _failed=0
  _total="$_slice_count"

  # Track running files for locklist
  : > "${ORCH_STATE}/.running_files"

  while [ "$((_completed + _failed))" -lt "$_total" ]; do
    # Try to start eligible slices
    while IFS='|' read -r s o d f p; do
      _s_status="$(check_slice_status "$s")"

      # Skip if already started or done
      case "$_s_status" in
        running|complete|failed|stuck|repair_limit|aborted) continue ;;
      esac

      # Check dependency satisfaction (avoid pipe-subshell by using temp file)
      _deps_met=1
      if [ -n "$d" ]; then
        _deps_tmp="${ORCH_STATE}/.deps_check.tmp"
        echo "$d" | tr ',' '\n' > "$_deps_tmp"
        while IFS= read -r dep; do
          _dep_slug="$(echo "$dep" | tr -d ' []' | tr '[:upper:]' '[:lower:]' | sed 's/^slice //')"
          [ -z "$_dep_slug" ] && continue
          _dep_status="$(check_slice_status "$_dep_slug")"
          if [ "$_dep_status" != "complete" ]; then
            _deps_met=0
            break
          fi
        done < "$_deps_tmp"
        rm -f "$_deps_tmp"
      fi

      if [ "$_deps_met" -eq 0 ]; then
        continue
      fi

      # Check locklist conflicts
      _running_files="$(cat "${ORCH_STATE}/.running_files" 2>/dev/null || true)"
      _conflict="$(check_locklist_conflict "$f" "$locklist" "$_running_files")"
      if [ -n "$_conflict" ]; then
        log "Slice ${s} deferred: locklist conflict on ${_conflict}"
        continue
      fi

      # Check parallel capacity
      _current_running=0
      _current_running="$(grep -c 'running' "${ORCH_STATE}"/slice-*.status 2>/dev/null)" || _current_running=0
      if [ "$_current_running" -ge "$MAX_PARALLEL" ]; then
        continue
      fi

      # Start the slice
      echo "$f" | tr ',' '\n' >> "${ORCH_STATE}/.running_files"
      run_slice "$s" "$o" "$p"
    done < "$_slices_file"

    # Update status counts and rebuild running_files from currently-running slices
    _completed=0
    _failed=0
    _running=0
    : > "${ORCH_STATE}/.running_files"
    while IFS='|' read -r _rf_s _rf_o _rf_d _rf_f _rf_p; do
      _rf_status="$(check_slice_status "$_rf_s")"
      case "$_rf_status" in
        complete)                        _completed=$((_completed + 1)) ;;
        failed|stuck|repair_limit|aborted) _failed=$((_failed + 1)) ;;
        running)
          _running=$((_running + 1))
          # Re-add only currently running slice files to locklist
          echo "$_rf_f" | tr ',' '\n' >> "${ORCH_STATE}/.running_files"
          ;;
      esac
    done < "$_slices_file"

    if [ "$((_completed + _failed))" -ge "$_total" ]; then
      break
    fi

    # Wait a bit before checking again
    sleep 5
  done

  log ""
  log "═══ Orchestrator Results ═══"
  log "Completed: ${_completed}/${_total}"
  log "Failed: ${_failed}/${_total}"

  # --- Integration merge ---
  _merge_status="skipped"
  _pr_url=""

  if [ "$_completed" -gt 0 ] && [ "$_failed" -eq 0 ]; then
    if [ "$UNIFIED_PR" -eq 1 ] && [ -n "$INTEGRATION_BRANCH" ]; then
      # Unified PR mode: sequential merge into integration branch, then create PR
      if integration_merge "$INTEGRATION_BRANCH" "$_slices_file"; then
        _merge_status="clean"
        log "Sequential merge to ${INTEGRATION_BRANCH} passed."
        # Create unified PR
        _pr_url="$(create_unified_pr "$INTEGRATION_BRANCH" "$_base_branch" "$PLAN_SLUG" "$_total" "$_completed")" || {
          log_error "Unified PR creation failed."
          _pr_url=""
        }
      else
        _merge_status="conflict"
        log_error "Sequential merge failed. Manual resolution needed on ${INTEGRATION_BRANCH}."
      fi
    else
      # Legacy mode: dry merge check only
      if integration_merge_check; then
        _merge_status="clean"
        log "All slices complete with no merge conflicts."
      else
        _merge_status="conflict"
        log_error "Merge conflicts detected. Manual resolution needed."
      fi
    fi
  fi

  # --- Generate execution report ---
  _report_file="${EVIDENCE_DIR}/orchestrator-$(ts_file).json"

  cat > "$_report_file" <<REPORT_JSON
{
  "plan": "${PLAN_FILE}",
  "plan_slug": "${PLAN_SLUG}",
  "started": "${_started}",
  "ended": "$(ts)",
  "total_slices": ${_total},
  "completed": ${_completed},
  "failed": ${_failed},
  "merge_status": "${_merge_status}",
  "unified_pr": $([ "$UNIFIED_PR" -eq 1 ] && echo true || echo false),
  "integration_branch": "$([ "$UNIFIED_PR" -eq 1 ] && echo "${INTEGRATION_BRANCH}" || echo "")",
  "pr_url": "${_pr_url}"
}
REPORT_JSON

  log "Report: ${_report_file}"

  # Update orchestrator status
  jq --arg s "$([ "$_failed" -gt 0 ] && echo "partial" || echo "complete")" \
    --arg pr "${_pr_url}" \
    '.status = $s | .ended = "'"$(ts)"'" | .pr_url = $pr' \
    "${ORCH_STATE}/orchestrator.json" > "${ORCH_STATE}/orchestrator.tmp.json" \
    && mv "${ORCH_STATE}/orchestrator.tmp.json" "${ORCH_STATE}/orchestrator.json"

  if [ "$_failed" -gt 0 ]; then
    log_error "Some slices failed. Check individual slice logs in ${ORCH_STATE}/"
    return 1
  fi

  return 0
}

main
