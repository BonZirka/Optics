#!/bin/bash
# Runs the benchmark suite (examples/bench) and prints per-case statistics.
# Requires CANGJIE_HOME; see docs/benchmarks.md for recorded results.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${CANGJIE_HOME:?CANGJIE_HOME must point to the Cangjie toolchain directory (the one containing envsetup.sh)}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
source "$CANGJIE_HOME/envsetup.sh"
export CANGJIE_STDX_PATH="${CANGJIE_STDX_PATH:-$(dirname "$CANGJIE_HOME")/linux_x86_64_cjnative/dynamic/stdx}"
export LD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_STDX_PATH:$PWD/target/release/lucida:${LD_LIBRARY_PATH}"

echo "== building benchmark binaries =="
( cd examples && cjpm test -i --no-run )

BIN=examples/target/release/unittest_bin
for bench in general depth examples; do
    echo "== bench: $bench =="
    "$BIN/optics_experiments.bench.$bench" --bench
done
