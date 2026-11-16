#!/usr/bin/env bash
#
# mayhem/build.sh — builds DCMTK three ways, all out of tree under mayhem/build (gitignored by upstream's
# `build` pattern, so `git clean -ffdX` removes it):
#   1. mayhem/build/fuzz   sanitized + SanCov libraries, installed to mayhem/build/prefix, linked into the harnesses
#   2. /mayhem/<harness>[-standalone]   the libFuzzer binaries and their run-once reproducers
#   3. mayhem/build/test   the project's NORMAL build (apps + unit tests) that mayhem/test.sh runs
# Re-runnable, and needs no network: DCMTK has no external fetches (zlib comes from apt, the dictionary
# and the oficonv tables are compiled in).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
B="$SRC/mayhem/build"
mkdir -p "$B"

# What upstream's own configuration would fetch or need from the system is switched off or compiled in.
DCMTK_OPTS=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=None
  -DBUILD_SHARED_LIBS=OFF
  -DDCMTK_DEFAULT_DICT=builtin
  -DDCMTK_ENABLE_BUILTIN_OFICONV_DATA=ON
  -DDCMTK_WITH_DOXYGEN=OFF
  -DDCMTK_ENABLE_MANPAGES=OFF
  -DDCMTK_WITH_OPENSSL=OFF
  -DDCMTK_WITH_PNG=OFF
  -DDCMTK_WITH_TIFF=OFF
  -DDCMTK_WITH_XML=OFF
  -DDCMTK_WITH_ICONV=OFF
  -DDCMTK_WITH_OPENJPEG=OFF
  -DDCMTK_WITH_SNDFILE=OFF
  -DDCMTK_WITH_ZLIB=ON
)

# --- 1. sanitized + instrumented libraries (-fsanitize=fuzzer-no-link gives the library SanCov) ---------
FUZZ_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link -O1 $DEBUG_FLAGS"
export ASAN_OPTIONS="detect_leaks=0${ASAN_OPTIONS:+:$ASAN_OPTIONS}"
cmake -S "$SRC" -B "$B/fuzz" "${DCMTK_OPTS[@]}" \
  -DBUILD_APPS=OFF \
  -DCMAKE_C_FLAGS="$FUZZ_FLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" \
  -DCMAKE_INSTALL_PREFIX="$B/prefix"
cmake --build "$B/fuzz" -j"$MAYHEM_JOBS"
cmake --install "$B/fuzz"

# --- 2. harnesses: a libFuzzer binary and a run-once standalone reproducer each ----------------------------
LIBS="-Wl,--start-group -ldcmimage -ldcmimgle -ldcmjpeg -ldcmjpls -lijg8 -lijg12 -lijg16 -ldcmtkcharls \
-ldcmdata -loflog -lofstd -loficonv -Wl,--end-group -lz -lpthread -ldl"
INC="-I$B/prefix/include"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"
# LeakSanitizer off at build time (leaks are not the class this fleet fuzzes for).
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/lsan_off.o"
for h in dcmtk_dicom_fuzzer dcmtk_meta_fuzzer dcmtk_image_fuzzer; do
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++17 -O1 $INC $LIB_FUZZING_ENGINE \
      "$SRC/mayhem/harnesses/$h.cc" "$B/lsan_off.o" -L"$B/prefix/lib" $LIBS -o "$SRC/$h"
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++17 -O1 $INC \
      "$SRC/mayhem/harnesses/$h.cc" "$B/standalone_main.o" "$B/lsan_off.o" -L"$B/prefix/lib" $LIBS -o "$SRC/$h-standalone"
done

# --- 3. the project's own build (normal flags, no sanitizers) for mayhem/test.sh ----------------------------
# Every upstream DCMTK_ADD_TESTS module except dcmtls: its tests are #ifdef WITH_OPENSSL and OpenSSL is off.
cmake -S "$SRC" -B "$B/test" "${DCMTK_OPTS[@]}" \
  -DBUILD_APPS=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build "$B/test" -j"$MAYHEM_JOBS" --target \
  ofstd_tests dcmdata_tests oficonv_tests dcmsr_tests dcmiod_tests dcmfg_tests dcmseg_tests dcmect_tests \
  dcmrt_tests dcmtract_tests dcmnet_tests dcmqrdb_tests dcmwlm_tests dcmpstat_tests \
  dcmdump dump2dcm dcmconv dcm2xml dcmftest
