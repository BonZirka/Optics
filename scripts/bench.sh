#!/bin/bash
# Runs the benchmark suite (examples/bench) and prints per-case statistics.
# Requires CANGJIE_HOME; see docs/benchmarks.md for recorded results.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${CANGJIE_HOME:?CANGJIE_HOME must point to the Cangjie toolchain directory (the one containing envsetup.sh)}"

CJ_RUNTIME=$(ls -d "$CANGJIE_HOME"/runtime/lib/*_cjnative | head -1)
export LD_LIBRARY_PATH="$CJ_RUNTIME:$PWD/target/release/lucida${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export DYLD_FALLBACK_LIBRARY_PATH="$CJ_RUNTIME:$PWD/target/release/lucida${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

echo "== building benchmark binaries =="
( cd examples && cjpm test -i --rel --no-run )

BIN=examples/target/release/unittest_bin
for bench in general depth examples; do
    echo "== bench: $bench =="
    "$BIN/optics_experiments.bench.$bench" --bench
done
