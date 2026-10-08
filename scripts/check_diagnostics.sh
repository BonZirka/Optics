#!/bin/bash
# Negative diagnostics gate: known-bad macro inputs must FAIL compilation with
# the expected user-facing message. Complements check.sh (which asserts the
# happy path). Run from anywhere; exits non-zero if any probe regresses.
set -u
cd "$(dirname "$0")/.."

: "${CANGJIE_HOME:?CANGJIE_HOME must point to the Cangjie toolchain directory (the one containing envsetup.sh)}"

PASS=0
FAIL=0
PROBE_FILE="tests/src/zz_diag_tmp.cj"

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
package tests
import lucida.*
import lucida.macrodsl.*
func z(): Unit { let _ = @f() }
EOF

probe "generic where-clause"       "generic constraints" <<'EOF'
package tests
import lucida.macrodsl.*
@DeriveOptics
public struct BadWhere<T> where T <: ToString {
    public BadWhere(public let v: T) { }
}
EOF

probe "unknown chain start"        "Unknown expression" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
func z(): Unit { let _ = @f(3 + 4) }
EOF

probe "optic unknown field"       "unexpected token in fields" <<'EOF'
package tests
import lucida.macrodsl.*
@Optic[kolor: red]
struct BadOptic1 {}
EOF

probe "optic bad kind"            "unknown kind" <<'EOF'
package tests
import lucida.macrodsl.*
@Optic[source: Int64, focus: Int64, kind: Setter]
struct BadOptic2 {}
EOF

probe "optic non-empty carrier"   "carrier struct must be empty" <<'EOF'
package tests
import lucida.macrodsl.*
@Optic[source: Int64, focus: Int64, kind: Iso, forward: { src }, backward: { focus }]
struct BadOptic3 { public BadOptic3(public let v: Int64) { } }
EOF

probe "optic source in sourceless backward" "has no source parameter" <<'EOF'
package tests
import lucida.macrodsl.*
@Optic[source: Int64, focus: Int64, kind: Prism, forward: { Some(source) }, backward: { source }]
struct BadOptic4 {}
EOF

probe "optic rename arity forward" "binds 2 parameters; expected 1" <<'EOF'
package tests
import lucida.macrodsl.*
@Optic[source: Int64, focus: Int64, kind: Lens, forward: { a, b => a }, backward: { a, b => a }]
struct BadOpticRen1 {}
EOF

probe "optic rename arity sourceless backward" "has no source parameter" <<'EOF'
package tests
import lucida.macrodsl.*
@Optic[source: Int64, focus: Int64, kind: Prism, forward: { s => Some(s) }, backward: { s, d => d }]
struct BadOpticRen2 {}
EOF

probe "optic dot on partial"      "on a partial optic (Prism/Affine)" <<'EOF'
package tests
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
package tests
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
package tests
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
package tests
import lucida.*
import lucida.macrodsl.*
func z4(): Unit {
    let mb = MeterBox(Meters(7))
    let rd = @f(mb.m?.coerce<Int64>())
    let _ = rd
}
EOF

probe "optic dot mid-chain on derived prism" "on a partial optic (Prism/Affine)" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
func z5(): Unit {
    let h = PayloadHolder(Rect(Box(42)))
    let rd = @f(h.shape.Rect.w)
    let _ = rd
}
EOF

probe "optic question-dot on derived lens" "on a total optic (Lens/Iso)" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
func z6(): Unit {
    let mb = MeterBox(Meters(7))
    let rd = @f(mb.m?.v)
    let _ = rd
}
EOF

probe "optic where clause" "generic constraints ('where' clauses) are not supported" <<'EOF'
package tests
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
package tests
import lucida.*
import lucida.macrodsl.*
func z(): Unit {
    let mb = MeterBox(Meters(7))
    let rd = @f(mb.m.coerce())
    let _ = rd
}
EOF

probe "same name and signature twice" "redefinition of declaration '__dup_impl" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
@Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
struct dup {}
@Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
struct dup {}
func z8(): Unit { }
EOF

probe "alias rejects an explicit kind" "takes no 'kind' field" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
@Lens[source: String, focus: Int64, kind: Lens, forward: { source.size }, backward: { focus.toString() }]
struct dupKind {}
func z7b(): Unit { }
EOF

probe "alias blames itself, not @Optic" "@Prism: field 'forward' must be a { ... } block" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
@Prism[source: String, focus: Int64, forward: source.size, backward: { [focus] }]
struct badAlias {}
func z7c(): Unit { }
EOF

# Same name and source, different kind: the generated interfaces differ (kind is
# part of the mangle) but the dispatch members live on RegistryMagical<String>,
# so the clash surfaces as a cjc type error rather than a bespoke message. Pin
# it so the failure mode cannot silently change.
probe "same name and source, different kind" "__downcast_method_mix" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
@Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
struct mix {}
@Prism[source: String, focus: Int64, forward: { if (source.size > 0) { Some(source.size) } else { None } }, backward: { [focus] }]
struct mix {}
func z8(): Unit { }
EOF

probe "block update arity mismatch" "requires a tuple target" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
@DeriveOptics
public struct BlkAB2 { public BlkAB2(public let a: Int64, public let b: Int64) { } }
func z10(): Unit {
    let x = BlkAB2(1, 2)
    let upd = @f(x.{ .a; .b } <- 5)
    let _ = upd
}
EOF

probe "block update partial field" "expected a block chain starting with '.'" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
@DeriveOptics
public struct BlkAB3 { public BlkAB3(public let a: Int64, public let b: Int64) { } }
func z11(): Unit {
    let x = BlkAB3(1, 2)
    let upd = @f(x.{ ?.a } <- 5)
    let _ = upd
}
EOF

probe "block chains conflicting overlap" "block chains conflict on a shared prefix" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
@DeriveOptics
public struct BlkDup { public BlkDup(public let a: Int64, public let b: Int64) { } }
func z12(): Unit {
    let x = BlkDup(1, 2)
    let upd = @f(x.{ .a; .a } <- (5, 6))
    let _ = upd
}
EOF

probe "@InlineOptics total case slot" "needs a partial slot" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
import tests.inline.*
@DeriveOptics
public enum InlC { | Empty | Held(Int64) }
func z21(): Unit {
    let x = InlC.Held(1)
    let r = @InlineOptics[shapes: (InlC, (Empty, ()), (Held, (v, Int64))), root: InlC](x.Held)
    let _ = r
}
EOF

probe "@InlineOptics block anchored above a case" "block anchor cannot cross a partial slot" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
import tests.inline.*
@DeriveOptics
public struct InlOptE { public InlOptE(public let q: Int64) { } }
@DeriveOptics
public struct InlOptM { public InlOptM(public let e: InlOptE) { } }
@DeriveOptics
public enum InlOptF { | Off | On(InlOptM) }
@DeriveOptics
public struct InlOptG { public InlOptG(public let f: InlOptF, public let t: Int64) { } }
func z21c(): Unit {
    let x = InlOptG(InlOptF.On(InlOptM(InlOptE(2))), 3)
    let r = @InlineOptics[shapes: (InlOptG, (f, InlOptF), (t, Int64)), (InlOptF, (Off, ()), (On, (m, InlOptM))), (InlOptM, (e, InlOptE)), (InlOptE, (q, Int64)), root: InlOptG](x.f?.On.e.{ .q } <- (5))
    let _ = r
}
EOF

probe "@InlineOptics question-dot before a struct field" "on a total optic (Lens/Iso)" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
import tests.inline.*
@DeriveOptics
public struct InlOptH { public InlOptH(public let s: Option<InlOptE>) { } }
func z21d(): Unit {
    let x = InlOptH(Some(InlOptE(1)))
    let r = @InlineOptics[shapes: (InlOptH, (s, Option<InlOptE>)), (InlOptE, (q, Int64)), root: InlOptH](x?.s.q <- 5)
    let _ = r
}
EOF

probe "@InlineOptics block anchored on a struct field" "on a total optic (Lens/Iso)" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
import tests.inline.*
@DeriveOptics
public struct InlOptI { public InlOptI(public let s: Option<InlOptE>) { } }
func z21e(): Unit {
    let x = InlOptI(Some(InlOptE(1)))
    let r = @InlineOptics[shapes: (InlOptI, (s, Option<InlOptE>)), (InlOptE, (q, Int64)), root: InlOptI](x?.s.{ .q } <- (5))
    let _ = r
}
EOF

probe "@InlineOptics unknown field" "has no field 'zz'" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
import tests.inline.*
@DeriveOptics
public struct InlC { public InlC(public let a: Int64) { } }
func z22(): Unit {
    let x = InlC(1)
    let r = @InlineOptics[shapes: (InlC, (a, Int64)), root: InlC](x.zz <- 5)
    let _ = r
}
EOF

probe "@InlineOptics unregistered slot" "no inlining metadata registered" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
import tests.inline.*
@DeriveOptics
public struct InlD { public InlD(public let a: Int64) { } }
func z23(): Unit {
    let x = InlD(1)
    let r = @InlineOptics[shapes: (InlD, (a, Int64)), root: InlD](x.pick() <- 5)
    let _ = r
}
EOF

probe "@InlineOptics first-class anchor" "macro should be contained inside '@f'" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
import tests.inline.*
@DeriveOptics
public struct InlD2 { public InlD2(public let a: Int64) { } }
let inlD2Optic = @f(@typeof(InlD2(0)).a)
func z23b(): Unit {
    let x = InlD2(1)
    let r = @InlineOptics[shapes: (InlD2, (a, Int64)), root: InlD2, registry: (inlD2Optic, InlD2, a)](x.@use(inlD2Optic) <- 5)
    let _ = r
}
EOF

probe "@InlineOptics missing shapes" "missing required field 'shapes'" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
import tests.inline.*
@DeriveOptics
public struct InlE { public InlE(public let a: Int64) { } }
func z24(): Unit {
    let x = InlE(1)
    let r = @InlineOptics[root: InlE](x.a <- 5)
    let _ = r
}
EOF

probe "@InlineOptics coerce on a multi-field shape" "a coercion needs a one-field shape" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
import tests.inline.*
@DeriveOptics
public struct InlG2 { public InlG2(public let a: Int64, public let b: Int64) { } }
@DeriveOptics
public struct InlG { public InlG(public let m: InlG2, public let t: Int64) { } }
func z25(): Unit {
    let x = InlG(InlG2(1, 2), 3)
    let r = @InlineOptics[
        shapes: (InlG, (m, InlG2), (t, Int64)), (InlG2, (a, Int64), (b, Int64)),
        root: InlG
    ](x.m.coerce<Int64>() <- 5)
    let _ = r
}
EOF

probe "@InlineOptics coerce to the wrong type" "is an iso to 'Int64', not to 'String'" <<'EOF'
package tests
import lucida.*
import lucida.macrodsl.*
import tests.inline.*
@DeriveOptics
public struct InlH { public InlH(public let m: Int64) { } }
func z26(): Unit {
    let x = InlH(1)
    let r = @InlineOptics[shapes: (InlH, (m, Int64)), root: InlH](x.coerce<String>())
    let _ = r
}
EOF

echo "diagnostics gate: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then exit 1; fi
exit 0
