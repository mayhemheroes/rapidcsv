#!/usr/bin/env bash
#
# mayhem/build.sh — build the rapidcsv fuzz target and the upstream test suite.
#
# rapidcsv is a header-only C++11 CSV library (src/rapidcsv.h), so the sanitized
# "project build" IS the harness compile: all fuzzed library code is compiled
# into the harness translation unit with $SANITIZER_FLAGS + $DEBUG_FLAGS.
#   build/fuzzcsv             libFuzzer harness (sanitized, DWARF-3) — the Mayhem target
#   build/fuzzcsv-standalone  run-once reproducer ($STANDALONE_FUZZ_MAIN, no libFuzzer runtime)
#   build-tests/              upstream's FULL ctest unit-test suite (Debug build, normal
#                             flags — the honest functional oracle run by mayhem/test.sh)
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "${SRC:-/mayhem}"

# 1+2) Sanitized fuzz harness (header-only: this instruments the whole library).
mkdir -p build
# shellcheck disable=SC2086
$CXX -std=c++11 -O1 $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    -I src mayhem/fuzzcsv.cpp -o build/fuzzcsv

# Standalone run-once reproducer: same harness against $STANDALONE_FUZZ_MAIN.
# Compile the driver as C first so LLVMFuzzerTestOneInput keeps C linkage.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
# shellcheck disable=SC2086
$CXX -std=c++11 -O1 $SANITIZER_FLAGS $DEBUG_FLAGS \
    -I src mayhem/fuzzcsv.cpp /tmp/standalone_main.o -o build/fuzzcsv-standalone

# 3) Upstream test suite, NORMAL flags (independent Debug build => the full ctest
#    unit-test set; upstream only registers unit tests in Debug). test.sh RUNS it.
cmake -B build-tests -S . \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DRAPIDCSV_BUILD_TESTS=ON \
    -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build build-tests -j"$MAYHEM_JOBS"

echo "build.sh: built build/fuzzcsv (+standalone) and build-tests/ (upstream ctest suite)"
