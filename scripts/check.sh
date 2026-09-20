#!/bin/bash
# Lucida verification gate: library build + law tests + consumer build + diagnostics gate.
# Non-zero exit on any failure.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${CANGJIE_HOME:?CANGJIE_HOME must point to the Cangjie toolchain directory (the one containing envsetup.sh)}"

echo "== library: build =="
cjpm build -i --rel
echo "== library: law tests =="
cjpm test --rel "$@"
echo "== examples: build (consumer + benches) =="
( cd examples && cjpm build -i --rel )
echo "== diagnostics (negative tests) =="
./scripts/check_diagnostics.sh
echo "check.sh: OK"
