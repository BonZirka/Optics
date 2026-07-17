#!/bin/bash
# Lucida verification gate: library build + law tests + consumer build + diagnostics gate.
# Non-zero exit on any failure.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${CANGJIE_HOME:?CANGJIE_HOME must point to the Cangjie toolchain directory (the one containing envsetup.sh)}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
source "$CANGJIE_HOME/envsetup.sh"
export CANGJIE_STDX_PATH="${CANGJIE_STDX_PATH:-$(dirname "$CANGJIE_HOME")/linux_x86_64_cjnative/dynamic/stdx}"

echo "== library: build =="
cjpm build -i
echo "== library: law tests =="
cjpm test "$@"
echo "== examples: build (consumer + benches) =="
( cd examples && cjpm build -i )
echo "== diagnostics (negative tests) =="
./scripts/check_diagnostics.sh
echo "check.sh: OK"
