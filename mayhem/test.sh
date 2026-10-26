#!/usr/bin/env bash
# mayhem/test.sh — RUNS the googletest binary that mayhem/build.sh built; it does not build anything.
# Emits a CTRF summary (file + `CTRF {...}` stdout line); exit 0 iff no test failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Upstream's own googletest suites for the tokenizer / query parser (the QueryParser cases assert the exact
# transformed query tree strings) and string formatting, linked against the project's libraries and built
# by mayhem/build.sh with normal flags. The counts are parsed from
# googletest's own summary, so a neutered binary (no summary) fails.
BIN=/mayhem/mayhem_gtests
[ -x "$BIN" ] || { echo "missing $BIN — mayhem/build.sh did not produce it" >&2; emit_ctrf manticore-gtests 0 1 0; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
export GTEST_DICT="$SRC/src/gtests"
OUT="$WORK/gtest.out"
"$BIN" --gtest_brief=0 >"$OUT" 2>&1; rc=$?
tail -40 "$OUT"

ran=$(sed -n 's/^\[==========\] \([0-9][0-9]*\) tests\? from .* ran\..*/\1/p' "$OUT" | tail -1)
passed=$(sed -n 's/^\[  PASSED  \] \([0-9][0-9]*\) tests\?\..*/\1/p' "$OUT" | tail -1)
failed=$(sed -n 's/^\[  FAILED  \] \([0-9][0-9]*\) tests\?, listed below:.*/\1/p' "$OUT" | tail -1)
skipped=$(sed -n 's/^\[  SKIPPED \] \([0-9][0-9]*\) tests\?, listed below:.*/\1/p' "$OUT" | tail -1)
: "${ran:=0}" "${passed:=0}" "${failed:=0}" "${skipped:=0}"

# known-answer floor: the suite has well over 150 cases; a build that silently lost them must fail
if [ "$ran" -lt 150 ] || [ "$passed" -lt 150 ]; then
  echo "expected >=150 passing googletest cases, got ran=$ran passed=$passed (rc=$rc)" >&2
  failed=$(( failed + 1 ))
fi
[ "$rc" -eq 0 ] || [ "$failed" -gt 0 ] || failed=1
emit_ctrf manticore-gtests "$passed" "$failed" "$skipped"
