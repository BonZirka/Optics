package tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.macrodsl.*
import lucida_stdlib.*
import tests.inline.*

@DeriveOptics
public struct InlBox {
    public InlBox(public let x: Int64, public let y: InlLeaf, public let tag: Int64) { }
}

@DeriveOptics
public struct InlLeaf {
    public InlLeaf(public let a: Int64, public let b: InlTip) { }
}

@DeriveOptics
public struct InlTip {
    public InlTip(public let v: Int64, public let w: Int64) { }
}

@DeriveOptics
public struct InlWide {
    public InlWide(public let p: Int64, public let q: Int64, public let r: Int64) { }
}

@DeriveOptics
public struct InlArr {
    public InlArr(public let items: Array<Int64>, public let n: Int64) { }
}

// One-field derivations: what a coercion resolves against. `InlUnit` is an iso
// to `Int64` and `InlWrap` an iso to `InlUnit`, so a chain can coerce and then
// keep going.
@DeriveOptics
public struct InlUnit {
    public InlUnit(public let n: Int64) { }
}

@DeriveOptics
public struct InlWrap {
    public InlWrap(public let u: InlUnit) { }
}

@DeriveOptics
public struct InlWrapBox {
    public InlWrapBox(public let w: InlWrap, public let tag: Int64) { }
}

extend InlUnit {
    operator func ==(other: InlUnit): Bool { this.n == other.n }
}

extend InlWrap {
    operator func ==(other: InlWrap): Bool { this.u == other.u }
}

extend InlWrapBox {
    operator func ==(other: InlWrapBox): Bool {
        this.w == other.w && this.tag == other.tag
    }
}

// A case payload that is itself a coercion target.
@DeriveOptics
public enum InlGauge {
    | Off
    | On(InlUnit)
}

// A holder around the gauge: the block's guard has to rebuild this level too.
@DeriveOptics
public struct InlGaugeTree {
    public InlGaugeTree(public let g: InlGauge, public let tag: Int64) { }
}

extend InlGaugeTree {
    operator func ==(other: InlGaugeTree): Bool {
        this.g == other.g && this.tag == other.tag
    }
}

extend InlGauge {
    operator func ==(other: InlGauge): Bool {
        match ((this, other)) {
            case (Off, Off) => true
            case (On(a), On(b)) => a == b
            case _ => false
        }
    }
}

// A hand-written (method) optic, not a derived field, so it can only be inlined
// through registered forward/backward bodies.
@Lens[source: Array<Int64>, focus: Int64, forward: { source[0] }, backward: { [focus] }]
struct inlHead {}


@DeriveOptics
public enum InlSlot {
    | Empty
    | Held(Int64)
}

@DeriveOptics
public enum InlPair {
    | Both(Int64, Int64)
}

@DeriveOptics
public struct InlSlotBox {
    public InlSlotBox(public let slot: Option<InlSlot>) { }
}

extend InlSlotBox {
    operator func ==(other: InlSlotBox): Bool {
        match ((slot, other.slot)) {
            case (Some(a), Some(b)) => a == b
            case (None, None) => true
            case _ => false
        }
    }
}

// A chain that ends in an enum, for the partial-write miss cases: the miss has
// to hand back the whole chain's source, not just the value at the case.
@DeriveOptics
public struct InlSlotLeaf {
    public InlSlotLeaf(public let a: Int64, public let slot: InlSlot) { }
}

@DeriveOptics
public struct InlSlotTree {
    public InlSlotTree(public let leaf: InlSlotLeaf, public let tag: Int64) { }
}

extend InlSlotLeaf {
    operator func ==(other: InlSlotLeaf): Bool {
        this.a == other.a && this.slot == other.slot
    }
}

extend InlSlotTree {
    operator func ==(other: InlSlotTree): Bool {
        this.leaf == other.leaf && this.tag == other.tag
    }
}

@DeriveOptics
public struct InlOpt {
    public InlOpt(public let m: Option<InlBox>, public let n: Int64) { }
}

extend InlSlot {
    operator func ==(other: InlSlot): Bool {
        match ((this, other)) {
            case (Empty, Empty) => true
            case (Empty, _) => false
            case (_, Empty) => false
            case (Held(a), Held(b)) => a == b
        }
    }
}

extend InlPair {
    operator func ==(other: InlPair): Bool {
        match ((this, other)) {
            case (Both(p1, q1), Both(p2, q2)) => p1 == p2 && q1 == q2
        }
    }
}

extend InlOpt {
    // Option has no structural ==, so unwrap explicitly.
    operator func ==(other: InlOpt): Bool {
        match ((m, other.m)) {
            case (Some(a), Some(b)) => a == b && n == other.n
            case (None, None) => n == other.n
            case _ => false
        }
    }
}

@Test
class InlineOpticsTranslation {
    @TestCase
    func translatesDeepChainUpdate(): Unit {
        let o = InlBox(1, InlLeaf(2, InlTip(3, 4)), 5)
        let viaOptics = @f(o.y.b.v <- 99)
        let viaInline = @InlineOptics[
            shapes: (InlBox, (x, Int64), (y, InlLeaf), (tag, Int64)),
                    (InlLeaf, (a, Int64), (b, InlTip)),
                    (InlTip, (v, Int64), (w, Int64)),
            root: InlBox
        ](o.y.b.v <- 99)
        @Assert(viaOptics == viaInline)
        @Assert(viaInline.y.b.v == 99)
        @Assert(viaInline.y.b.w == 4)
        @Assert(viaInline.y.a == 2)
        @Assert(viaInline.x == 1)
        @Assert(viaInline.tag == 5)
    }

    @TestCase
    func translatesWideChainUpdate(): Unit {
        let o = InlWide(1, 2, 3)
        let viaOptics = @f(o.q <- 42)
        let viaInline = @InlineOptics[
            shapes: (InlWide, (p, Int64), (q, Int64), (r, Int64)),
            root: InlWide
        ](o.q <- 42)
        @Assert(viaOptics == viaInline)
        @Assert(viaInline == InlWide(1, 42, 3))
    }

    @TestCase
    func translatesForwardRead(): Unit {
        let o = InlBox(1, InlLeaf(2, InlTip(3, 4)), 5)
        let viaOptics = @f(o.y.b.v)
        let viaInline = @InlineOptics[
            shapes: (InlBox, (x, Int64), (y, InlLeaf), (tag, Int64)),
                    (InlLeaf, (a, Int64), (b, InlTip)),
                    (InlTip, (v, Int64), (w, Int64)),
            root: InlBox
        ](o.y.b.v)
        @Assert(viaOptics == viaInline)
        @Assert(viaInline == 3)
    }

    // A first-class optic mid-chain (`o.@use(lens).b.v`) is NOT covered here:
    // @use only expands inside @f, and this harness lives outside lucida's
    // macro package, so its guard fires before the harness ever sees the
    // tokens. The registry path itself is still covered below, spelled as a
    // method call.

    // A hand-written optic whose forward and backward are registered for
    // inlining: `b.items.inlHead() <- 7` becomes `InlArr([7], b.n)`.
    @TestCase
    func inlinesRegisteredUserOpticBodies(): Unit {
        let b = InlArr([1, 2, 3], 9)
        let viaOptics = @f(b.items.inlHead() <- 7)
        let viaInline = @InlineOptics[
            shapes: (InlArr, (items, Array<Int64>), (n, Int64)),
            root: InlArr,
            registry: (inlHead, body, { source => source[0] }, { source, focus => [focus] }, Int64)
        ](b.items.inlHead() <- 7)
        @Assert(viaOptics == viaInline)
        @Assert(viaInline == InlArr([7], 9))
    }

    @TestCase
    func inlinesRegisteredUserOpticForward(): Unit {
        let b = InlArr([1, 2, 3], 9)
        let viaOptics = @f(b.items.inlHead())
        let viaInline = @InlineOptics[
            shapes: (InlArr, (items, Array<Int64>), (n, Int64)),
            root: InlArr,
            registry: (inlHead, body, { source => source[0] }, { source, focus => [focus] }, Int64)
        ](b.items.inlHead())
        @Assert(viaOptics == viaInline)
        @Assert(viaInline == 1)
    }
}

// Structural equality, so the tests can assert the inlined constructor chain
// and the @f expansion produce exactly the same value.
extend InlTip {
    operator func ==(other: InlTip): Bool {
        v == other.v && w == other.w
    }
}

extend InlLeaf {
    operator func ==(other: InlLeaf): Bool {
        a == other.a && b == other.b
    }
}

extend InlBox {
    operator func ==(other: InlBox): Bool {
        x == other.x && y == other.y && tag == other.tag
    }
}

extend InlWide {
    operator func ==(other: InlWide): Bool {
        p == other.p && q == other.q && r == other.r
    }
}

extend InlArr {
    operator func ==(other: InlArr): Bool {
        items == other.items && n == other.n
    }
}
// Option has no structural ==, so the assertions compare through these.
private func optUnitEq(a: Option<Unit>, b: Option<Unit>): Bool {
    match ((a, b)) {
        case (Some(_), Some(_)) => true
        case (None, None) => true
        case _ => false
    }
}

private func optIntEq(a: Option<Int64>, b: Option<Int64>): Bool {
    match ((a, b)) {
        case (Some(x), Some(y)) => x == y
        case (None, None) => true
        case _ => false
    }
}

private func optOptIntEq(a: Option<Option<Int64>>, b: Option<Option<Int64>>): Bool {
    match ((a, b)) {
        case (Some(x), Some(y)) => optIntEq(x, y)
        case (None, None) => true
        case _ => false
    }
}

private func optPairEq(a: Option<(Int64, Int64)>, b: Option<(Int64, Int64)>): Bool {
    match ((a, b)) {
        case (Some(p), Some(q)) => p == q
        case (None, None) => true
        case _ => false
    }
}

// ===== partial segments, prisms and sibling blocks =====

@Test
class InlineOpticsPartial {
    // A payloadless case derives a Unit-focus prism.
    @TestCase
    func inlinesPrismReadHit(): Unit {
        let s = InlSlot.Empty
        let got = @InlineOptics[
            shapes: (InlSlot, (Empty, ()), (Held, (v, Int64))),
            root: InlSlot
        ](s?.Empty)
        @Assert(optUnitEq(got, @f(s?.Empty)))
        @Assert(optUnitEq(got, Some(())))
    }

    @TestCase
    func inlinesPrismReadMiss(): Unit {
        let s = InlSlot.Held(3)
        let got = @InlineOptics[
            shapes: (InlSlot, (Empty, ()), (Held, (v, Int64))),
            root: InlSlot
        ](s?.Empty)
        @Assert(optUnitEq(got, Option<Unit>.None))
        @Assert(optUnitEq(got, @f(s?.Empty)))
    }

    // A miss is identity, not None: a prism's backward cannot fail.
    @TestCase
    func inlinesPrismWriteMissIsIdentity(): Unit {
        let s = InlSlot.Held(3)
        let got = @InlineOptics[
            shapes: (InlSlot, (Empty, ()), (Held, (v, Int64))),
            root: InlSlot
        ](s?.Empty <- ())
        @Assert(got == InlSlot.Held(3))
        @Assert(got == @f(s?.Empty <- ()))
    }

    @TestCase
    func inlinesPrismWriteHit(): Unit {
        let s = InlSlot.Empty
        let got = @InlineOptics[
            shapes: (InlSlot, (Empty, ()), (Held, (v, Int64))),
            root: InlSlot
        ](s?.Empty <- ())
        @Assert(got == InlSlot.Empty)
        @Assert(got == @f(s?.Empty <- ()))
    }

    // A write that misses has nothing to rebuild: the source comes back as it
    // was. This is the case that catches an expansion which wraps the levels
    // above the `match` instead of hoisting the `match` over them -- same value,
    // but it would allocate a fresh object to copy an unchanged one.
    @TestCase
    func inlinesPrismWriteMiss(): Unit {
        let s = InlSlot.Empty
        let got = @InlineOptics[
            shapes: (InlSlot, (Empty, ()), (Held, (v, Int64))),
            root: InlSlot
        ](s?.Held <- 7)
        @Assert(got == InlSlot.Empty)
        @Assert(got == @f(s?.Held <- 7))
    }

    // The same miss, but with levels above the case: the `match` still has to
    // return the whole chain's source rather than the value at the case.
    @TestCase
    func inlinesPrismWriteMissUnderAChain(): Unit {
        let s = InlSlotTree(InlSlotLeaf(2, InlSlot.Empty), 3)
        let got = @InlineOptics[
            shapes: (InlSlotTree, (leaf, InlSlotLeaf), (tag, Int64)),
                    (InlSlotLeaf, (a, Int64), (slot, InlSlot)),
                    (InlSlot, (Empty, ()), (Held, (v, Int64))),
            root: InlSlotTree
        ](s.leaf.slot?.Held <- 7)
        @Assert(got == s)
        @Assert(got == @f(s.leaf.slot?.Held <- 7))
    }

    // A single-payload case focuses the payload itself.
    @TestCase
    func inlinesSinglePayloadCase(): Unit {
        let s = InlSlot.Held(7)
        let read = @InlineOptics[
            shapes: (InlSlot, (Empty, ()), (Held, (v, Int64))),
            root: InlSlot
        ](s?.Held)
        let written = @InlineOptics[
            shapes: (InlSlot, (Empty, ()), (Held, (v, Int64))),
            root: InlSlot
        ](s?.Held <- 9)
        @Assert(optIntEq(read, Some(7)))
        @Assert(optIntEq(read, @f(s?.Held)))
        @Assert(written == InlSlot.Held(9))
        @Assert(written == @f(s?.Held <- 9))
    }

    // A multi-payload case focuses the whole payload tuple.
    @TestCase
    func inlinesMultiPayloadCase(): Unit {
        let s = InlPair.Both(1, 2)
        let read = @InlineOptics[
            shapes: (InlPair, (Both, (p, Int64), (q, Int64))),
            root: InlPair
        ](s?.Both)
        let written = @InlineOptics[
            shapes: (InlPair, (Both, (p, Int64), (q, Int64))),
            root: InlPair
        ](s?.Both <- (3, 4))
        @Assert(optPairEq(read, Some((1, 2))))
        @Assert(optPairEq(read, @f(s?.Both)))
        @Assert(written == InlPair.Both(3, 4))
        @Assert(written == @f(s?.Both <- (3, 4)))
    }

    // `?.` on an Option-typed field: unwrap, rebuild, rewrap.
    @TestCase
    func inlinesPartialFieldUpdate(): Unit {
        let o = InlOpt(Some(InlBox(1, InlLeaf(2, InlTip(3, 4)), 5)), 6)
        let viaInline = @InlineOptics[
            shapes: (InlOpt, (m, Option<InlBox>), (n, Int64)),
                    (InlBox, (x, Int64), (y, InlLeaf), (tag, Int64)),
                    (InlLeaf, (a, Int64), (b, InlTip)),
                    (InlTip, (v, Int64), (w, Int64)),
            root: InlOpt
        ](o.m?.y.a <- 20)
        @Assert(viaInline == InlOpt(Some(InlBox(1, InlLeaf(20, InlTip(3, 4)), 5)), 6))
    }

    // A miss on an Option field is identity too.
    @TestCase
    func inlinesPartialFieldUpdateOnNone(): Unit {
        let o = InlOpt(None, 6)
        let viaInline = @InlineOptics[
            shapes: (InlOpt, (m, Option<InlBox>), (n, Int64)),
                    (InlBox, (x, Int64), (y, InlLeaf), (tag, Int64)),
                    (InlLeaf, (a, Int64), (b, InlTip)),
                    (InlTip, (v, Int64), (w, Int64)),
            root: InlOpt
        ](o.m?.y.a <- 20)
        @Assert(viaInline == InlOpt(None, 6))
    }

    // A partial read stays a single Option: the lenses below it are total.
    @TestCase
    func inlinesPartialFieldRead(): Unit {
        let o = InlOpt(Some(InlBox(1, InlLeaf(2, InlTip(3, 4)), 5)), 6)
        let viaInline = @InlineOptics[
            shapes: (InlOpt, (m, Option<InlBox>), (n, Int64)),
                    (InlBox, (x, Int64), (y, InlLeaf), (tag, Int64)),
                    (InlLeaf, (a, Int64), (b, InlTip)),
                    (InlTip, (v, Int64), (w, Int64)),
            root: InlOpt
        ](o.m?.y.b.v)
        @Assert(optIntEq(viaInline, Some(3)))
    }

    // Two siblings at one level: one rebuild, two fields replaced.
    @TestCase
    func inlinesSiblingBlockUpdate(): Unit {
        let l = InlLeaf(1, InlTip(2, 3))
        let viaInline = @InlineOptics[
            shapes: (InlLeaf, (a, Int64), (b, InlTip)),
                    (InlTip, (v, Int64), (w, Int64)),
            root: InlLeaf
        ](l.{ .a; .b.v } <- (10, 20))
        @Assert(viaInline == @f(l.{ .a; .b.v } <- (10, 20)))
        @Assert(viaInline == InlLeaf(10, InlTip(20, 3)))
    }

    @TestCase
    func inlinesSiblingBlockRead(): Unit {
        let l = InlLeaf(1, InlTip(2, 3))
        let viaInline = @InlineOptics[
            shapes: (InlLeaf, (a, Int64), (b, InlTip)),
                    (InlTip, (v, Int64), (w, Int64)),
            root: InlLeaf
        ](l.{ .a; .b.v })
        @Assert(viaInline == (1, 2))
        @Assert(viaInline == @f(l.{ .a; .b.v }))
    }

    // Entries that share a prefix rebuild that level exactly once.
    @TestCase
    func inlinesSiblingBlockWithSharedPrefix(): Unit {
        let o = InlBox(1, InlLeaf(2, InlTip(3, 4)), 5)
        let viaInline = @InlineOptics[
            shapes: (InlBox, (x, Int64), (y, InlLeaf), (tag, Int64)),
                    (InlLeaf, (a, Int64), (b, InlTip)),
                    (InlTip, (v, Int64), (w, Int64)),
            root: InlBox
        ](o.{ .y.a; .y.b.v; .tag } <- (10, 20, 50))
        @Assert(viaInline == @f(o.{ .y.a; .y.b.v; .tag } <- (10, 20, 50)))
        @Assert(viaInline == InlBox(1, InlLeaf(10, InlTip(20, 4)), 50))
    }

    // A block reached through an anchor chain.
    @TestCase
    func inlinesSiblingBlockThroughAnchor(): Unit {
        let o = InlBox(1, InlLeaf(2, InlTip(3, 4)), 5)
        let viaInline = @InlineOptics[
            shapes: (InlBox, (x, Int64), (y, InlLeaf), (tag, Int64)),
                    (InlLeaf, (a, Int64), (b, InlTip)),
                    (InlTip, (v, Int64), (w, Int64)),
            root: InlBox
        ](o.y.{ .a; .b.v } <- (10, 20))
        @Assert(viaInline == @f(o.y.{ .a; .b.v } <- (10, 20)))
        @Assert(viaInline == InlBox(1, InlLeaf(10, InlTip(20, 4)), 5))
    }

    // Two partial segments in a row nest their Options.
    @TestCase
    func inlinesPartialThenPrism(): Unit {
        let b = InlSlotBox(Some(InlSlot.Held(4)))
        let read = @InlineOptics[
            shapes: (InlSlotBox, (slot, Option<InlSlot>)),
                    (InlSlot, (Empty, ()), (Held, (v, Int64))),
            root: InlSlotBox
        ](b.slot?.Held)
        let written = @InlineOptics[
            shapes: (InlSlotBox, (slot, Option<InlSlot>)),
                    (InlSlot, (Empty, ()), (Held, (v, Int64))),
            root: InlSlotBox
        ](b.slot?.Held <- 8)
        // Each `?.` opens one failure channel: unwrapping `slot` can miss, and
        // so can the `Held` case, so a hit arrives as Some(Some(4)).
        @Assert(optOptIntEq(read, Some(Some(4))))
        @Assert(written == InlSlotBox(Some(InlSlot.Held(8))))
    }
}

// A coercion resolves against a one-field derivation: forward is the field
// read, backward is the single-argument constructor. So inlining one is the
// same program `@f` compiles to, and the laws below are the fused ones restated
// as equalities.
@Test
class InlineOpticsCoerce {
    @TestCase
    func inlinesCoerceToTheFieldType(): Unit {
        let b = InlWrapBox(InlWrap(InlUnit(7)), 1)
        let got = @InlineOptics[
            shapes: (InlWrapBox, (w, InlWrap), (tag, Int64)),
                    (InlWrap, (u, InlUnit)),
                    (InlUnit, (n, Int64)),
            root: InlWrapBox
        ](b.w.coerce<InlUnit>())
        @Assert(got == InlUnit(7))
        @Assert(got == @f(b.w.coerce<InlUnit>()))
    }

    // The coercion target is always the field's own type, so "past" means
    // coercing the level whose single field is the leaf.
    @TestCase
    func inlinesCoerceToALeafType(): Unit {
        let b = InlWrapBox(InlWrap(InlUnit(7)), 1)
        let got = @InlineOptics[
            shapes: (InlWrapBox, (w, InlWrap), (tag, Int64)),
                    (InlWrap, (u, InlUnit)),
                    (InlUnit, (n, Int64)),
            root: InlWrapBox
        ](b.w.u.coerce<Int64>())
        @Assert(got == 7)
        @Assert(got == @f(b.w.u.coerce<Int64>()))
    }

    @TestCase
    func inlinesCoerceBackward(): Unit {
        let b = InlWrapBox(InlWrap(InlUnit(7)), 1)
        let got = @InlineOptics[
            shapes: (InlWrapBox, (w, InlWrap), (tag, Int64)),
                    (InlWrap, (u, InlUnit)),
                    (InlUnit, (n, Int64)),
            root: InlWrapBox
        ](b.w.u.coerce<Int64>() <- 5)
        @Assert(got == InlWrapBox(InlWrap(InlUnit(5)), 1))
        @Assert(got == @f(b.w.u.coerce<Int64>() <- 5))
    }

    // Segments below the coercion: they read the coerced type, and the rebuild
    // below it has to wrap the new value before the coercion rebuilds.
    @TestCase
    func inlinesCoerceWithSegmentsBelow(): Unit {
        let b = InlWrapBox(InlWrap(InlUnit(7)), 1)
        let read = @InlineOptics[
            shapes: (InlWrapBox, (w, InlWrap), (tag, Int64)),
                    (InlWrap, (u, InlUnit)),
                    (InlUnit, (n, Int64)),
            root: InlWrapBox
        ](b.w.coerce<InlUnit>().n)
        @Assert(read == 7)
        @Assert(read == @f(b.w.coerce<InlUnit>().n))

        let written = @InlineOptics[
            shapes: (InlWrapBox, (w, InlWrap), (tag, Int64)),
                    (InlWrap, (u, InlUnit)),
                    (InlUnit, (n, Int64)),
            root: InlWrapBox
        ](b.w.coerce<InlUnit>().n <- 9)
        @Assert(written == InlWrapBox(InlWrap(InlUnit(9)), 1))
        @Assert(written == @f(b.w.coerce<InlUnit>().n <- 9))
    }

    // A sibling block anchored on a partial segment: the case's `match` wraps the
    // whole block rebuild, so a hit rebuilds the payload inside the arm and a
    // miss hands back the source untouched. `@f` composes the same way.
    @TestCase
    func inlinesBlockOnPrismAnchorWrite(): Unit {
        let on = InlGauge.On(InlUnit(4))
        let got = @InlineOptics[
            shapes: (InlGauge, (Off, ()), (On, (u, InlUnit))),
                    (InlUnit, (n, Int64)),
            root: InlGauge
        ](on?.On.{ .n } <- 7)
        @Assert(got == InlGauge.On(InlUnit(7)))
        @Assert(got == @f(on?.On.{ .n } <- 7))

        let off = InlGauge.Off
        let miss = @InlineOptics[
            shapes: (InlGauge, (Off, ()), (On, (u, InlUnit))),
                    (InlUnit, (n, Int64)),
            root: InlGauge
        ](off?.On.{ .n } <- 7)
        @Assert(miss == InlGauge.Off)
        @Assert(miss == @f(off?.On.{ .n } <- 7))
    }

    // The read half: a tuple on a hit, `None` on a miss.
    @TestCase
    func inlinesBlockOnPrismAnchorRead(): Unit {
        let on = InlGauge.On(InlUnit(4))
        let readHit = @InlineOptics[
            shapes: (InlGauge, (Off, ()), (On, (u, InlUnit))),
                    (InlUnit, (n, Int64)),
            root: InlGauge
        ](on?.On.{ .n })
        @Assert(optIntEq(readHit, Some(4)))
        @Assert(optIntEq(readHit, @f(on?.On.{ .n })))

        let off = InlGauge.Off
        let readMiss = @InlineOptics[
            shapes: (InlGauge, (Off, ()), (On, (u, InlUnit))),
                    (InlUnit, (n, Int64)),
            root: InlGauge
        ](off?.On.{ .n })
        @Assert(optIntEq(readMiss, Option<Int64>.None))
        @Assert(optIntEq(readMiss, @f(off?.On.{ .n })))
    }

    // Levels above the anchor are rebuilt *inside* the guard, so a miss returns
    // the whole chain's source, not just the value at the case.
    @TestCase
    func inlinesBlockOnPrismAnchorUnderAChain(): Unit {
        let tree = InlGaugeTree(InlGauge.On(InlUnit(9)), 3)
        let got = @InlineOptics[
            shapes: (InlGaugeTree, (g, InlGauge), (tag, Int64)),
                    (InlGauge, (Off, ()), (On, (u, InlUnit))),
                    (InlUnit, (n, Int64)),
            root: InlGaugeTree
        ](tree.g?.On.{ .n } <- 11)
        @Assert(got == InlGaugeTree(InlGauge.On(InlUnit(11)), 3))
        @Assert(got == @f(tree.g?.On.{ .n } <- 11))

        let offTree = InlGaugeTree(InlGauge.Off, 3)
        let miss = @InlineOptics[
            shapes: (InlGaugeTree, (g, InlGauge), (tag, Int64)),
                    (InlGauge, (Off, ()), (On, (u, InlUnit))),
                    (InlUnit, (n, Int64)),
            root: InlGaugeTree
        ](offTree.g?.On.{ .n } <- 11)
        @Assert(miss == offTree)
        @Assert(miss == @f(offTree.g?.On.{ .n } <- 11))
    }

    // A coercion below a partial case, on both sides of the miss: the case's
    // `match` carries the coercion, and a miss returns the enum untouched.
    @TestCase
    func inlinesCoerceAfterPrism(): Unit {
        let on = InlGauge.On(InlUnit(4))
        let off = InlGauge.Off
        let readHit = @InlineOptics[
            shapes: (InlGauge, (Off, ()), (On, (u, InlUnit))),
                    (InlUnit, (n, Int64)),
            root: InlGauge
        ](on?.On.coerce<Int64>())
        @Assert(optIntEq(readHit, Some(4)))
        @Assert(optIntEq(readHit, @f(on?.On.coerce<Int64>())))

        let readMiss = @InlineOptics[
            shapes: (InlGauge, (Off, ()), (On, (u, InlUnit))),
                    (InlUnit, (n, Int64)),
            root: InlGauge
        ](off?.On.coerce<Int64>())
        @Assert(optIntEq(readMiss, Option<Int64>.None))
        @Assert(optIntEq(readMiss, @f(off?.On.coerce<Int64>())))

        let written = @InlineOptics[
            shapes: (InlGauge, (Off, ()), (On, (u, InlUnit))),
                    (InlUnit, (n, Int64)),
            root: InlGauge
        ](on?.On.coerce<Int64>() <- 5)
        @Assert(written == InlGauge.On(InlUnit(5)))
        @Assert(written == @f(on?.On.coerce<Int64>() <- 5))

        let missed = @InlineOptics[
            shapes: (InlGauge, (Off, ()), (On, (u, InlUnit))),
                    (InlUnit, (n, Int64)),
            root: InlGauge
        ](off?.On.coerce<Int64>() <- 5)
        @Assert(missed == InlGauge.Off)
        @Assert(missed == @f(off?.On.coerce<Int64>() <- 5))
    }
}
