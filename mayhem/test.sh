#!/usr/bin/env bash
#
# mayhem/test.sh — RUN rapidcsv's own upstream unit-test suite (ctest, built by
# mayhem/build.sh into build-tests/). Each test binary asserts parsed values /
# golden outputs internally (tests/unittest.h ExpectEqual), so this is a real
# behavioral oracle: an exit(0)-neutered library fails the assertions.
# Emits a CTRF report and exits non-zero iff any test failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "${SRC:-/mayhem}"

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

if [ ! -d build-tests ] || [ ! -f build-tests/CTestTestfile.cmake ]; then
  echo "test.sh: build-tests/ missing — mayhem/build.sh must build the suite first" >&2
  emit_ctrf cmake-ctest 0 1
  exit 1
fi

LOG=/tmp/ctest.log
( cd build-tests && ctest --output-on-failure -j"$MAYHEM_JOBS" ) | tee "$LOG"
rc=${PIPESTATUS[0]}

# ctest summary: "100% tests passed, 0 tests failed out of 103"
total=$(sed -n 's/.*out of \([0-9][0-9]*\).*/\1/p' "$LOG" | tail -1)
failed=$(sed -n 's/.*, \([0-9][0-9]*\) tests failed out of.*/\1/p' "$LOG" | tail -1)
if [ -z "$total" ] || [ -z "$failed" ]; then
  echo "test.sh: could not parse ctest summary (rc=$rc)" >&2
  emit_ctrf cmake-ctest 0 1
  exit 1
fi
passed=$(( total - failed ))

# Known-answer output checks: upstream's example programs must PRINT the expected
# parsed values (asserted stdout, not exit status) — a neutered exit(0) binary
# produces no output and fails these.
ka() { # <name> <binary> <expected-stdout>
  local out
  out=$("$2" 2>/dev/null)
  if [ "$out" = "$3" ]; then
    echo "  ok   - $1"; passed=$((passed+1))
  else
    echo "  FAIL - $1 (got: '$out')"; failed=$((failed+1))
  fi
}
ka ex001-known-answer ./build-tests/ex001 'Read 5 values.'
ka ex002-known-answer ./build-tests/ex002 'Read 6 values.
Volume 19259700 on 2017-02-22.'

emit_ctrf cmake-ctest "$passed" "$failed"
