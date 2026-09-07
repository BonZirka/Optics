#!/bin/bash
# Negative diagnostics gate: known-bad macro inputs must FAIL compilation with
# the expected user-facing message. Complements check.sh (which asserts the
# happy path). Run from anywhere; exits non-zero if any probe regresses.
set -u
cd "$(dirname "$0")/.."

: "${CANGJIE_HOME:?CANGJIE_HOME must point to the Cangjie toolchain directory (the one containing envsetup.sh)}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
source "$CANGJIE_HOME/envsetup.sh"
export CANGJIE_STDX_PATH="${CANGJIE_STDX_PATH:-$(dirname "$CANGJIE_HOME")/linux_x86_64_cjnative/dynamic/stdx}"

PASS=0
FAIL=0
PROBE_FILE="src/tests/zz_diag_tmp.cj"

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

probe "empty @f()"            "expects at least one argument" <<'EOF'
package lucida.tests
import lucida.*
import lucida.macrodsl.*
func z(): Unit { let _ = @f() }
EOF

probe "generic where-clause"       "generic constraints" <<'EOF'
package lucida.tests
import lucida.macrodsl.*
@DeriveOptics
public struct BadWhere<T> where T <: ToString {
    public BadWhere(public let v: T) { }
}
EOF

probe "unknown chain start"        "Unknown expression" <<'EOF'
package lucida.tests
import lucida.*
import lucida.macrodsl.*
func z(): Unit { let _ = @f(3 + 4) }
EOF

probe "optic unknown field"       "unexpected token in fields" <<'EOF'
package lucida.tests
import lucida.macrodsl.*
@Optic[kolor: red]
struct BadOptic1 {}
EOF

probe "optic bad kind"            "unknown kind" <<'EOF'
package lucida.tests
import lucida.macrodsl.*
@Optic[source: Int64, focus: Int64, kind: Setter]
struct BadOptic2 {}
EOF

probe "optic non-empty carrier"   "carrier struct must be empty" <<'EOF'
package lucida.tests
import lucida.macrodsl.*
@Optic[source: Int64, focus: Int64, kind: Iso, forward: { src }, backward: { focus }]
struct BadOptic3 { public BadOptic3(public let v: Int64) { } }
EOF

probe "optic source in sourceless backward" "has no source slot" <<'EOF'
package lucida.tests
import lucida.macrodsl.*
@Optic[source: Int64, focus: Int64, kind: Prism, forward: { Some(source) }, backward: { source }]
struct BadOptic4 {}
EOF

probe "optic rename arity forward" "binds 2 names but this kind has 1 slots" <<'EOF'
package lucida.tests
import lucida.macrodsl.*
@Optic[source: Int64, focus: Int64, kind: Lens, forward: { a, b => a }, backward: { a, b => a }]
struct BadOpticRen1 {}
EOF

probe "optic rename arity sourceless backward" "has no source slot" <<'EOF'
package lucida.tests
import lucida.macrodsl.*
@Optic[source: Int64, focus: Int64, kind: Prism, forward: { s => Some(s) }, backward: { s, d => d }]
struct BadOpticRen2 {}
EOF

probe "optic dot on partial"      "on a partial optic (Prism/Affine)" <<'EOF'
package lucida.tests
import lucida.*
import lucida.macrodsl.*
public struct DotBox {
    public DotBox(public let v: Int64) { }
}
@Optic[source: DotBox, focus: Int64, kind: Prism, forward: { Some(source.v) }, backward: { DotBox(focus) }]
struct dotPartial {}
func z1(): Unit { let _ = @f(DotBox(1).dotPartial()) }
EOF

probe "optic question-dot on total" "on a total optic (Lens/Iso)" <<'EOF'
package lucida.tests
import lucida.*
import lucida.macrodsl.*
public struct DotBox2 {
    public DotBox2(public let v: Int64) { }
}
@Optic[source: DotBox2, focus: Int64, kind: Lens, forward: { src.v }, backward: { DotBox2(focus) }]
struct qdotTotal {}
func z2(): Unit { let _ = @f(DotBox2(1)?.qdotTotal()) }
EOF

probe "optic dot-write on prism"  "rebuild the source unconditionally on miss" <<'EOF'
package lucida.tests
import lucida.*
import lucida.macrodsl.*
public struct DotBox3 {
    public DotBox3(public let v: Int64) { }
}
@Optic[source: DotBox3, focus: Int64, kind: Prism, forward: { Right(src.v) }, backward: { DotBox3(focus) }]
struct dotPartialW {}
func z3(): Unit {
    let b = DotBox3(1)
    let wr = @f(b.dotPartialW() <- 9)
    let _ = wr
}
EOF

probe "optic question-dot on coerce" "on a total optic (coerce)" <<'EOF'
package lucida.tests
import lucida.*
import lucida.macrodsl.*
func z4(): Unit {
    let mb = MeterBox(Meters(7))
    let rd = @f(mb.m?.coerce<Int64>())
    let _ = rd
}
EOF

probe "optic dot mid-chain on derived prism" "on a partial optic (Prism/Affine)" <<'EOF'
package lucida.tests
import lucida.*
import lucida.macrodsl.*
func z5(): Unit {
    let h = PayloadHolder(Rect(Box(42)))
    let rd = @f(h.shape.Rect.w)
    let _ = rd
}
EOF

probe "optic question-dot on derived lens" "on a total optic (Lens/Iso)" <<'EOF'
package lucida.tests
import lucida.*
import lucida.macrodsl.*
func z6(): Unit {
    let mb = MeterBox(Meters(7))
    let rd = @f(mb.m?.v)
    let _ = rd
}
EOF

probe "optic where clause" "generic constraints ('where' clauses) are not supported" <<'EOF'
package lucida.tests
import lucida.*
import lucida.macrodsl.*
public struct WBox2<T> {
    public WBox2(public let v: T) { }
}
@Optic[source: WBox2<T>, focus: T, kind: Lens, forward: { src.v }, backward: { WBox2(focus) }]
struct wbox2Lens<T> where T <: ToString {}
func z7(): Unit {
    let w = WBox2<Int64>(1)
    let rd = @f(w.wbox2Lens())
    let _ = rd
}
EOF

probe "coerce without type argument" "expects exactly one type argument" <<'EOF'
package lucida.tests
import lucida.*
import lucida.macrodsl.*
func z(): Unit {
    let mb = MeterBox(Meters(7))
    let rd = @f(mb.m.coerce())
    let _ = rd
}
EOF

probe "namespace duplicate same-name optic" "declared more than once" <<'EOF'
package lucida.tests
import lucida.*
import lucida.macrodsl.*
@Optics({
    @Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
    struct dup {}
    @Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
    struct dup {}
})
func z8(): Unit { }
EOF

probe "namespace kind macro outside @Optics" "must be used inside an @Optics block" <<'EOF'
package lucida.tests
import lucida.*
import lucida.macrodsl.*
@Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
struct stray {}
func z9(): Unit { }
EOF

echo "diagnostics gate: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then exit 1; fi
exit 0
