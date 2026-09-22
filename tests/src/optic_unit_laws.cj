package tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*

@Test
class OpticUnitLaws {
    // Iso: to/from cancel in both directions
    @TestCase
    func isoRoundTrip(): Unit {
        let o = Iso<Int64, Int64>({ x: Int64 => -x }, { x: Int64 => -x })
        @Assert(o.to(o.from(42)) == 42)
        @Assert(o.from(o.to(42)) == 42)
    }

    // Lens: get-after-set returns focus; set-after-get reconstructs original
    @TestCase
    func lensLaws(): Unit {
        let o = Lens<Int64, Int64>({ s: Int64 => s }, { _: Int64, v: Int64 => v })
        @Assert(o.view(o.update(7, 99)) == 99)
        @Assert(o.update(7, o.view(7)) == 7)
    }

    // Prism/Affine: non-match backward = identity; match updates
    @TestCase
    func prismNonMatchIdentity(): Unit {
        let o = prismEven()
        @Assert(isNone(o.preview(3)))
        @Assert(isSomeWith(o.preview(4), 4))
        @Assert(o.build(5) == 8)
    }

    @TestCase
    func affineNonMatchIdentityAndMatchUpdates(): Unit {
        let o = affPos()
        // non-match: backward = identity
        @Assert(isNone(o.preview(-1)))
        @Assert(o.update(-1, 99) == -1)
        // match: update applies
        @Assert(isSomeWith(o.preview(4), 4))
        @Assert(o.update(4, 99) == 99)
    }

    // Setter: modifyId = identity; modify applies function
    @TestCase
    func setterLaws(): Unit {
        let o = Setter<Int64, Int64>({ s: Int64, f: (Int64) -> Int64 => f(s) })
        @Assert(o.modifyId(41) == 41)
        @Assert(o.modify(41, { x: Int64 => x + 1 }) == 42)
    }

    // ===== zero boundary: even matches, positive does not =====
    @TestCase
    func zeroBoundaryEdges(): Unit {
        // 0 is even -> prism focuses on zero
        @Assert(isSomeWith(prismEven().preview(0), 0))
        @Assert(prismEven().build(5) == 8)
        // 0 is not > 0 -> affine does not focus, update preserves
        @Assert(isNone(affPos().preview(0)))
        @Assert(affPos().update(0, 99) == 0)
        // composition: affine(non-match at 0) o prism keeps identity even though
        // the PRISM side would have matched
        let o1 = affPos()
        let o2 = prismEven()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(bwd(0, 5) == 0)
    }
}
