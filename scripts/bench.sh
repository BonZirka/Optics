#!/bin/bash
# Runs the benchmark suite (examples/bench plus the generated shapes in
# tests/src/generated) and prints per-case statistics.
# Requires CANGJIE_HOME; see docs/benchmarks.md for recorded results.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${CANGJIE_HOME:?CANGJIE_HOME must point to the Cangjie toolchain directory (the one containing envsetup.sh)}"

CJ_RUNTIME=$(ls -d "$CANGJIE_HOME"/runtime/lib/*_cjnative | head -1)
export LD_LIBRARY_PATH="$CJ_RUNTIME:$PWD/target/release/lucida:$PWD/tests/target/release/lucida${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export DYLD_FALLBACK_LIBRARY_PATH="$CJ_RUNTIME:$PWD/target/release/lucida:$PWD/tests/target/release/lucida${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

# Every case here allocates in a tight loop, so a GC pause landing inside a
# measurement batch dominates the result: medians swing by ~2x between runs and
# the ranking flips, because the pause lands in a different case each time.
# A large heap with a long GC interval keeps collection out of the batches
# entirely. Override by exporting these before calling.
#
# The interval is a DURATION in nanoseconds, not a byte count: the runtime
# rejects `512MB` with "Unsupported cjGCInterval parameter" and then runs with
# its default, which looks like it worked because the benchmark still produces
# numbers. ~4.3s of wall clock between collections, against a 4GB heap.
: "${cjHeapSize:=4GB}"
: "${cjGCInterval:=4294967296ns}"
export cjHeapSize cjGCInterval

echo "== building benchmark binaries =="
( cd examples && cjpm test -i --rel --no-run )
( cd tests && cjpm test -i --rel --no-run )

BIN=examples/target/release/unittest_bin
for bench in general depth examples; do
    echo "== bench: $bench =="
    "$BIN/optics_experiments.bench.$bench" --bench
done

# The generated shapes live with the harness they measure, in the test project.
echo "== bench: generated =="
tests/target/release/unittest_bin/tests.generated --bench
