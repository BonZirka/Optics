#!/bin/bash
# Lucida verification gate: build + unit/law tests. Non-zero exit on any failure.
set -euo pipefail
cd "$(dirname "$0")/.."

source "${CANGJIE_HOME:-$HOME/cangjie-sdk/cangjie}/envsetup.sh"
export CANGJIE_STDX_PATH="${CANGJIE_STDX_PATH:-$HOME/cangjie-sdk/linux_x86_64_cjnative/dynamic/stdx}"
export LD_LIBRARY_PATH="$PWD/target/release/lucida:${LD_LIBRARY_PATH:-}"

echo "== build =="
cjpm build -i
echo "== test =="
cjpm test "$@"
echo "== diagnostics (negative tests) =="
./scripts/check_diagnostics.sh
echo "check.sh: OK"
