#!/bin/bash
# Negative diagnostics gate: known-bad macro inputs must FAIL compilation with
# the expected user-facing message. Complements check.sh (which asserts the
# happy path). Run from anywhere; exits non-zero if any probe regresses.
set -u
cd "$(dirname "$0")/.."

source "${CANGJIE_HOME:-$HOME/cangjie-sdk/cangjie}/envsetup.sh"
export CANGJIE_STDX_PATH="${CANGJIE_STDX_PATH:-/home/huawei/cangjie-sdk/linux_x86_64_cjnative/dynamic/stdx}"

PASS=0
FAIL=0
PROBE_FILE="src/test/zz_diag_tmp.cj"

probe() {
    local name="$1" expected="$2"
    shift 2
    cat > "$PROBE_FILE"
    local out
    out=$(cjpm build -i 2>&1)
    rm -f "$PROBE_FILE" "$PROBE_FILE.macrocall"
    if echo "$out" | grep -q "$expected"; then
        PASS=$((PASS + 1))
        echo "diag ok   : $name"
    else
        FAIL=$((FAIL + 1))
        echo "diag FAIL : $name — expected substring '$expected'"
        echo "$out" | tail -5 | sed 's/^/    /'
    fi
}

probe "empty @Lucida()"            "expects at least one argument" <<'EOF'
package optics_experiments.test
import lucida.*
import lucida_macro.*
func z(): Unit { let _ = @Lucida() }
EOF

probe "enum multi-payload case"    "associated values; only single-payload" <<'EOF'
package optics_experiments.test
import lucida_macro.*
@DeriveOptics
public enum BadPair {
    | Two(Int64, Int64)
}
EOF

probe "enum payloadless case"      "no associated value" <<'EOF'
package optics_experiments.test
import lucida_macro.*
@DeriveOptics
public enum BadEmpty {
    | Emptyz
}
EOF

probe "generic where-clause"       "generic constraints" <<'EOF'
package optics_experiments.test
import lucida_macro.*
@DeriveOptics
public struct BadWhere<T> where T <: ToString {
    public BadWhere(public let v: T) { }
}
EOF

probe "unknown chain start"        "Unknown expression" <<'EOF'
package optics_experiments.test
import lucida.*
import lucida_macro.*
func z(): Unit { let _ = @Lucida(3 + 4) }
EOF

echo "diagnostics gate: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then exit 1; fi
exit 0
