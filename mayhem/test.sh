#!/usr/bin/env bash
#
# mayhem/test.sh — RUN DCMTK's own unit tests and known-answer probes (all built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
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

BIN="$SRC/mayhem/build/test/bin"
KAT="$SRC/mayhem/test"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
passed=0 ; failed=0

pass() { passed=$((passed + 1)); }
fail() { failed=$((failed + 1)); echo "FAIL: $*" >&2; }

# 1. DCMTK's own unit tests (every upstream DCMTK_ADD_TESTS module except dcmtls, whose tests are
#    #ifdef WITH_OPENSSL and build.sh sets DCMTK_WITH_OPENSSL=OFF; dcmnet's EF_Slow tests are skipped by
#    its runner by default, as in upstream's ctest): each module's runner prints "Test results for module 'M': N succeeded, F failed."
for m in ofstd dcmdata oficonv dcmsr dcmiod dcmfg dcmseg dcmect dcmrt dcmtract dcmnet dcmqrdb dcmwlm dcmpstat; do
  exe="$BIN/${m}_tests"
  if [ ! -x "$exe" ]; then fail "$exe missing (mayhem/build.sh builds it)"; continue; fi
  out="$("$exe" 2>&1)"; rc=$?
  line="$(printf '%s\n' "$out" | grep -E "^Test results for module '$m': [0-9]+ succeeded, [0-9]+ failed" | tail -1)"
  if [ -z "$line" ]; then fail "$m: no summary line from the test runner (rc=$rc)"; continue; fi
  s="$(printf '%s' "$line" | sed -E 's/.*: ([0-9]+) succeeded, ([0-9]+) failed.*/\1/')"
  f="$(printf '%s' "$line" | sed -E 's/.*: ([0-9]+) succeeded, ([0-9]+) failed.*/\2/')"
  [ "$s" -gt 0 ] || fail "$m: 0 tests ran"
  passed=$((passed + s)); failed=$((failed + f))
  [ "$f" -eq 0 ] && [ "$rc" -eq 0 ] || fail "$m: $line (rc=$rc)"
done

# 2. Known-answer probes through the real tools: DCMTK-written DICOM from a text dump, read back and
#    compared against golden output. A neutered tool prints nothing and fails every one of these.
need() { [ -x "$BIN/$1" ] || { fail "$BIN/$1 missing (mayhem/build.sh builds it)"; return 1; }; }
dataset() { sed -n '/^# Dicom-Data-Set/,$p'; }
if need dump2dcm && need dcmdump && need dcm2xml && need dcmconv && need dcmftest; then
  if "$BIN/dump2dcm" +te "$KAT/kat.dump" "$WORK/kat.dcm" >/dev/null 2>&1 && [ -s "$WORK/kat.dcm" ]; then pass; else fail "dump2dcm did not write kat.dcm"; fi

  "$BIN/dcmdump" "$WORK/kat.dcm" 2>/dev/null | dataset > "$WORK/got.dcmdump"
  if [ -s "$WORK/got.dcmdump" ] && diff -u "$KAT/kat.expected.dcmdump" "$WORK/got.dcmdump" >&2; then pass; else fail "dcmdump of kat.dcm differs from golden"; fi

  "$BIN/dcm2xml" "$WORK/kat.dcm" - 2>/dev/null | sed -n '/^<data-set/,/^<\/data-set>/p' > "$WORK/got.xml"
  if [ -s "$WORK/got.xml" ] && diff -u "$KAT/kat.expected.xml" "$WORK/got.xml" >&2; then pass; else fail "dcm2xml of kat.dcm differs from golden"; fi

  v="$("$BIN/dcmdump" +P PatientName +P PatientID +P Rows "$WORK/kat.dcm" 2>/dev/null | sed -E 's/ +#.*//' | tr '\n' '|')"
  if [ "$v" = "(0010,0010) PN [DOE^JANE]|(0010,0020) LO [KAT-0042]|(0028,0010) US 4|" ]; then pass; else fail "dcmdump +P gave '$v'"; fi

  # transfer syntax round trip: explicit -> implicit -> explicit reproduces the data set, except that
  # implicit VR cannot say OB, so the pixel data comes back as OW (byte-swapped words)
  if "$BIN/dcmconv" +ti "$WORK/kat.dcm" "$WORK/kat-i.dcm" >/dev/null 2>&1 \
     && "$BIN/dcmdump" "$WORK/kat-i.dcm" 2>/dev/null | grep -q '^(0002,0010) UI =LittleEndianImplicit'; then pass; else fail "dcmconv +ti did not produce implicit VR"; fi
  if "$BIN/dcmconv" +te "$WORK/kat-i.dcm" "$WORK/kat-e.dcm" >/dev/null 2>&1 \
     && "$BIN/dcmdump" "$WORK/kat-e.dcm" 2>/dev/null | dataset | grep -v '^(7fe0,0010)' > "$WORK/rt.dcmdump" \
     && [ -s "$WORK/rt.dcmdump" ] && grep -v '^(7fe0,0010)' "$KAT/kat.expected.dcmdump" | diff -q - "$WORK/rt.dcmdump" >/dev/null \
     && grep -q '^(7fe0,0010) OW 1100.3322.5544.7766.9988.bbaa.ddcc.ffee ' <("$BIN/dcmdump" "$WORK/kat-e.dcm" 2>/dev/null); then pass; else fail "explicit->implicit->explicit round trip changed the data set"; fi

  ft="$("$BIN/dcmftest" "$WORK/kat.dcm" 2>&1 || true)"
  if [ "${ft%%:*}" = yes ]; then pass; else fail "dcmftest does not recognise kat.dcm"; fi
  printf 'not a dicom file\n' > "$WORK/junk.dcm"
  ft="$("$BIN/dcmftest" "$WORK/junk.dcm" 2>&1 || true)"
  if [ "${ft%%:*}" = no ]; then pass; else fail "dcmftest accepted a text file"; fi
fi

emit_ctrf "dcmtk-oftest+kat" "$passed" "$failed" 0
