#!/usr/bin/env sh
set -eu

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$HOOK_DIR/lib_json.sh"

payload="$(cat | tr '\n' ' ')"
file_path="$(extract_json_field "$payload" "file_path")"
load_reason="$(extract_json_field "$payload" "load_reason")"

mkdir -p .harness/logs
printf '%s\t%s\n' "$load_reason" "$file_path" >> .harness/logs/instructions-loaded.log

exit 0
