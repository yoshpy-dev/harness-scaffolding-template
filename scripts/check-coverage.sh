#!/usr/bin/env sh
set -eu

# Coverage gate — checks test coverage meets threshold for detected languages
# Relies on packs/languages/<lang>/coverage.sh producing a numeric percentage

THRESHOLD="${COVERAGE_THRESHOLD:-80}"
status=0

fail() { echo "FAIL: $1"; status=1; }

# Detect languages
if [ ! -x scripts/detect-languages.sh ]; then
  echo "[skip] No language detector. Coverage gate not applicable."
  exit 0
fi

langs="$(./scripts/detect-languages.sh 2>/dev/null || true)"
if [ -z "$langs" ]; then
  echo "[skip] No languages detected. Coverage gate not applicable."
  exit 0
fi

checked=0
for lang in $langs; do
  coverage_script="packs/languages/${lang}/coverage.sh"
  [ -x "$coverage_script" ] || continue

  pct="$("./$coverage_script" 2>/dev/null || echo 0)"
  checked=$((checked + 1))

  if [ "$pct" -lt "$THRESHOLD" ]; then
    fail "${lang} coverage ${pct}% < ${THRESHOLD}%"
  else
    echo "[ok] ${lang} coverage ${pct}% >= ${THRESHOLD}%"
  fi
done

if [ "$checked" -eq 0 ]; then
  echo "[skip] No language packs have coverage.sh. Gate not enforced."
  exit 0
fi

exit "$status"
