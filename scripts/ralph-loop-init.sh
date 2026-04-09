#!/usr/bin/env sh
set -eu

# Initialize a Ralph Loop session.
# Generates PROMPT.md and state files from a prompt template.
#
# Modes:
#   Standard: ./ralph-loop-init.sh <task-type> <objective> [plan-slug]
#   Pipeline: ./ralph-loop-init.sh --pipeline <task-type> <objective> [plan-slug]

LOOP_DIR=".harness/state/loop"
PIPELINE_DIR=".harness/state/pipeline"
ARCHIVE_DIR=".harness/state/loop-archive"
TEMPLATE_DIR=".claude/skills/loop/prompts"

VALID_TYPES="general refactor test-coverage bugfix docs migration"

usage() {
  echo "Usage: $0 [--pipeline] <task-type> <objective> [plan-slug]"
  echo ""
  echo "Options:"
  echo "  --pipeline    Initialize in pipeline mode (full autonomous Inner/Outer Loop)"
  echo ""
  echo "Task types: ${VALID_TYPES}"
  echo ""
  echo "Examples:"
  echo "  $0 general 'Implement user auth'"
  echo "  $0 --pipeline refactor 'Extract shared utils' extract-utils"
  echo "  $0 bugfix 'Fix login timeout' login-timeout"
  exit 1
}

# Parse --pipeline flag
PIPELINE_MODE=0
if [ "${1:-}" = "--pipeline" ]; then
  PIPELINE_MODE=1
  shift
fi

if [ $# -lt 2 ]; then
  usage
fi

task_type="$1"
objective="$2"
plan_slug="${3:-}"

# Validate task type
valid=0
for t in $VALID_TYPES; do
  if [ "$t" = "$task_type" ]; then
    valid=1
    break
  fi
done

if [ "$valid" -eq 0 ]; then
  echo "Error: invalid task type '${task_type}'"
  echo "Valid types: ${VALID_TYPES}"
  exit 1
fi

# Select template based on mode
if [ "$PIPELINE_MODE" -eq 1 ]; then
  template_file="${TEMPLATE_DIR}/pipeline-inner.md"
else
  template_file="${TEMPLATE_DIR}/${task_type}.md"
fi

if [ ! -f "$template_file" ]; then
  echo "Error: template not found: ${template_file}"
  exit 1
fi

# Archive previous loop state if it exists
if [ -d "$LOOP_DIR" ] && [ -f "${LOOP_DIR}/task.json" ]; then
  archive_ts="$(date -u '+%Y%m%d-%H%M%S')"
  archive_dest="${ARCHIVE_DIR}/${archive_ts}"
  mkdir -p "$archive_dest"
  cp -r "${LOOP_DIR}/." "$archive_dest/"
  echo "Archived previous loop state to ${archive_dest}"
  rm -rf "$LOOP_DIR"
fi

# Archive previous pipeline state if it exists
if [ "$PIPELINE_MODE" -eq 1 ] && [ -d "$PIPELINE_DIR" ] && [ -f "${PIPELINE_DIR}/checkpoint.json" ]; then
  archive_ts="${archive_ts:-$(date -u '+%Y%m%d-%H%M%S')}"
  pipeline_archive="${ARCHIVE_DIR}/${archive_ts}-pipeline"
  mkdir -p "$pipeline_archive"
  cp -r "${PIPELINE_DIR}/." "$pipeline_archive/"
  echo "Archived previous pipeline state to ${pipeline_archive}"
  rm -rf "$PIPELINE_DIR"
fi

# Create fresh state directories
mkdir -p "$LOOP_DIR"
if [ "$PIPELINE_MODE" -eq 1 ]; then
  mkdir -p "$PIPELINE_DIR"
fi

# Resolve plan path
plan_path=""
if [ -n "$plan_slug" ]; then
  candidate="docs/plans/active/${plan_slug}.md"
  if [ -f "$candidate" ]; then
    plan_path="$candidate"
  else
    echo "Warning: plan file not found at ${candidate}, continuing without plan reference"
  fi
fi

# Generate PROMPT.md from template
sed \
  -e "s|__OBJECTIVE__|${objective}|g" \
  -e "s|__PLAN_PATH__|${plan_path}|g" \
  -e "s|__TASK_TYPE__|${task_type}|g" \
  "$template_file" > "${LOOP_DIR}/PROMPT.md"

echo "Generated ${LOOP_DIR}/PROMPT.md"

# Create task.json
created_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
_mode="standard"
if [ "$PIPELINE_MODE" -eq 1 ]; then
  _mode="pipeline"
fi

cat > "${LOOP_DIR}/task.json" <<EOF
{
  "objective": "${objective}",
  "task_type": "${task_type}",
  "plan": "${plan_path}",
  "mode": "${_mode}",
  "created": "${created_ts}",
  "status": "pending"
}
EOF

echo "Created ${LOOP_DIR}/task.json"

# Initialize progress log
cat > "${LOOP_DIR}/progress.log" <<EOF
# Progress log
# Task: ${objective}
# Type: ${task_type}
# Mode: ${_mode}
# Created: ${created_ts}

EOF

echo "Created ${LOOP_DIR}/progress.log"

# Initialize stuck counter
echo "0" > "${LOOP_DIR}/stuck.count"

# Initialize status
echo "pending" > "${LOOP_DIR}/status"

# --- Pipeline mode: additional initialization ---
if [ "$PIPELINE_MODE" -eq 1 ]; then
  # Copy pipeline prompt templates with variable substitution
  for tpl in pipeline-inner.md pipeline-review.md pipeline-outer.md; do
    src="${TEMPLATE_DIR}/${tpl}"
    if [ -f "$src" ]; then
      sed \
        -e "s|__OBJECTIVE__|${objective}|g" \
        -e "s|__PLAN_PATH__|${plan_path}|g" \
        -e "s|__TASK_TYPE__|${task_type}|g" \
        "$src" > "${PIPELINE_DIR}/${tpl}"
    fi
  done
  echo "Prepared pipeline prompt templates in ${PIPELINE_DIR}/"

  # Create pipeline metadata
  cat > "${PIPELINE_DIR}/pipeline.json" <<EOF
{
  "objective": "${objective}",
  "task_type": "${task_type}",
  "plan": "${plan_path}",
  "created": "${created_ts}",
  "max_iterations": 10,
  "max_inner_cycles": 5,
  "max_outer_cycles": 3,
  "max_repair_attempts": 5
}
EOF
  echo "Created ${PIPELINE_DIR}/pipeline.json"
fi

echo ""
if [ "$PIPELINE_MODE" -eq 1 ]; then
  echo "Ralph Pipeline initialized."
  echo "  Mode:      pipeline (full autonomous Inner/Outer Loop)"
else
  echo "Ralph Loop initialized."
  echo "  Mode:      standard"
fi
echo "  Type:      ${task_type}"
echo "  Objective: ${objective}"
echo "  Plan:      ${plan_path:-none}"
echo ""
echo "Next steps:"
if [ "$PIPELINE_MODE" -eq 1 ]; then
  echo "  1. Review ${PIPELINE_DIR}/pipeline-inner.md"
  echo "  2. Run: ./scripts/ralph-pipeline.sh"
  echo "  3. Optional: ./scripts/ralph-pipeline.sh --preflight --dry-run"
  echo "  4. Full run: ./scripts/ralph-pipeline.sh --max-iterations 10"
else
  echo "  1. Review ${LOOP_DIR}/PROMPT.md"
  echo "  2. Run: ./scripts/ralph-loop.sh"
  echo "  3. Optional: ./scripts/ralph-loop.sh --verify --max-iterations 10"
fi
