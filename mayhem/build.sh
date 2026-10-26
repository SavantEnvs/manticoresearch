#!/usr/bin/env bash
# Builds (1) the qfuzzer libFuzzer harness + a standalone reproducer, linked against a sanitized,
# DWARF-3 build of Manticore's query-parser libraries, and (2) an independent normal-flags build of
# upstream's tokenizer/query-parser gtests for mayhem/test.sh.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# the columnar library (mcl) is a git submodule; an empty mcl/ means the checkout/COPY lacked submodules
[ -f mcl/CMakeLists.txt ] || { echo "mcl/ submodule is empty: clone with 'git submodule update --init'" >&2; exit 1; }

# upstream's CMake downloads third-party sources (googletest, cctz, roaring, ...) into CACHEB the first
# time it configures; the image build is online, later (air-gapped) rebuilds find them there.
export CACHEB="${CACHEB:-/opt/deps/cache}" LIBS_BUNDLE="${LIBS_BUNDLE:-/opt/deps/bundle}"
mkdir -p "$CACHEB" "$LIBS_BUNDLE"

COMMON=(-GNinja -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX"
  -DWITH_GALERA=0 -DWITH_SSL=0 -DWITH_ZSTD=0 -DWITH_CURL=0 -DWITH_ODBC=0 -DWITH_EXPAT=0 -DWITH_MYSQL=0
  -DWITH_POSTGRESQL=0 -DWITH_ICU=1 -DWITH_ICU_FORCE_STATIC=0 -DWITH_JIEBA=0 -DWITH_RE2=0 -DWITH_STEMMER=0
  -DBUILD_TESTING=1 -DNOAPI=1 -DMCL_LOCAL_RUNTIME=OFF
  -DCMAKE_PROJECT_INCLUDE="$SRC/mayhem/cmake/mayhem_hook.cmake")

# a re-run may resolve the compiler to a different path (e.g. the image build runs under the ccache wrapper);
# CMake then discards its cache *and* the -D flags with it, so always configure from scratch
rm -rf cmake-build-tests build

# 1) the normal-flags test build first (-DNDEBUG: upstream's snippetindex.cpp assert() does not compile with WITH_RE2=0): it also populates CACHEB with an UNsanitized googletest
cmake -S . -B cmake-build-tests "${COMMON[@]}" -DCMAKE_BUILD_TYPE=Debug \
  -DMAYHEM_GTESTS=ON -DCMAKE_C_FLAGS="$COVERAGE_FLAGS -DNDEBUG" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS -DNDEBUG"
cmake --build cmake-build-tests -j"$MAYHEM_JOBS" --target mayhem_gtests
cp cmake-build-tests/mayhem_gtests /mayhem/mayhem_gtests

# 2) the fuzz build: upstream's own QFUZZER=ON mode (libFuzzer+ASan instrumentation of the libraries)
cmake -S . -B build "${COMMON[@]}" -DQFUZZER=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DMAYHEM_FUZZ_HARNESS="$SRC/mayhem/qfuzzer_harness.cpp" -DMAYHEM_LSAN_OFF="$SRC/mayhem/lsan_off.cc" -DMAYHEM_STANDALONE_MAIN="$STANDALONE_FUZZ_MAIN" \
  -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS"
cmake --build build -j"$MAYHEM_JOBS" --target mayhem_qfuzzer mayhem_qfuzzer_standalone
cp build/mayhem_qfuzzer /mayhem/qfuzzer
cp build/mayhem_qfuzzer_standalone /mayhem/qfuzzer-standalone

