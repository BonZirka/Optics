package tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*

// Canonical instances, all Int64 -> Int64:
//   prismEven: matches even numbers; builds constant 8
//   affPos:    matches n > 0; update replaces focus
func prismEven(): Prism<Int64, Int64> {
    Prism<Int64, Int64>(
        { s: Int64 => if (s % 2 == 0) { Some(s) } else { None } },
        { _: Int64 => 8 }
    )
}

func affPos(): Affine<Int64, Int64> {
    // Lawful affine: update preserves source when the optic does not focus.
    // (Matches the guarding convention of the library's own stdlib impls.)
    Affine<Int64, Int64>(
        { s: Int64 => if (s > 0) { Some(s) } else { None } },
        { s: Int64, v: Int64 => if (s > 0) { v } else { s } }
    )
}

// More canonical instances (all Int64 -> Int64):
//   isoNeg:  negates both ways (lawful)
//   lensId:  view = identity, update = replace
//   setWrap: modify f s = f s
func isoNeg(): Iso<Int64, Int64> {
    Iso<Int64, Int64>({ x: Int64 => -x }, { x: Int64 => -x })
}

func lensId(): Lens<Int64, Int64> {
    Lens<Int64, Int64>({ s: Int64 => s }, { _: Int64, v: Int64 => v })
}

func setWrap(): Setter<Int64, Int64> {
    Setter<Int64, Int64>({ s: Int64, f: (Int64) -> Int64 => f(s) })
}

func inc(n: Int64): Int64 {
    n + 1
}

func isSomeWith(e: Option<Int64>, expected: Int64): Bool {
    if (let Some(v) <- e) { return v == expected }
    return false
}

func isNone(e: Option<Int64>): Bool {
    match (e) {
        case None => return true
        case _ => return false
    }
}

@Test
class CompositionLaws {
    // ===== §1.1 case 19: Affine ∘ Prism backward, PRISM does not match =====
    // affPos(3) focuses, prismEven rejects 3 -> whole chain does not focus -> set must be identity.
    // BUG (pre-fix): injects p2build(5) regardless -> returns 8.
    @TestCase
    func affinePrismBackwardNoPrismMatchIsIdentity(): Unit {
        let o1 = affPos()
        let o2 = prismEven()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(bwd(3, 5) == 3)
    }

    // ===== §1.1 case 11: Lens ∘ Prism backward, PRISM does not match =====
    // BUG (pre-fix): unconditional l1update(source, p2build(focus)).
    @TestCase
    func lensPrismBackwardNoPrismMatchIsIdentity(): Unit {
        let o1 = Lens<Int64, Int64>({ s: Int64 => s }, { _: Int64, v: Int64 => v })
        let o2 = prismEven()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(bwd(3, 5) == 3)
    }

    // Sanity: case 19 WITH full match must still update.
    @TestCase
    func affinePrismBackwardFullMatchUpdates(): Unit {
        let o1 = affPos()
        let o2 = prismEven()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        // affPos(4) focuses; prismEven accepts 4 -> o1.update(4, p2build(5)=8) = 8
        @Assert(bwd(4, 5) == 8)
    }

    // ===== case 1 <Iso, Iso> =====
    @TestCase
    func case01_IsoIso(): Unit {
        let o1 = isoNeg()
        let o2 = isoNeg()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(5) == 5)
        @Assert(bwd(7) == 7)
    }

    // ===== case 2 <Lens, Lens> =====
    @TestCase
    func case02_LensLens(): Unit {
        let o1 = lensId()
        let o2 = lensId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(5) == 5)
        @Assert(bwd(3, 9) == 9)
    }

    // ===== case 3 <Prism, Prism>: backward is a total rebuild (no source) =====
    @TestCase
    func case03_PrismPrism(): Unit {
        let o1 = prismEven()
        let o2 = prismEven()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(isSomeWith(fwd(4), 4))
        @Assert(isNone(fwd(3)))
        @Assert(bwd(5) == 8)
    }

    // ===== case 4 <Affine, Affine> =====
    @TestCase
    func case04_AffAff(): Unit {
        let o1 = affPos()
        let o2 = affPos()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(isSomeWith(fwd(4), 4))
        @Assert(isNone(fwd(-1)))
        @Assert(bwd(4, 9) == 9)
        @Assert(bwd(-1, 9) == -1)
    }

    // ===== case 5 <Setter, Setter> (unlabeled pair between 4 and 6) =====
    @TestCase
    func case05_SetterSetter(): Unit {
        let o1 = setWrap()
        let o2 = setWrap()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(5) == 5)
        @Assert(bwd(3, inc) == 4)
    }

    // ===== case 6 <Iso, Lens> =====
    @TestCase
    func case06_IsoLens(): Unit {
        let o1 = isoNeg()
        let o2 = lensId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(5) == -5)
        @Assert(bwd(3, 9) == -9)
    }

    // ===== case 7 <Lens, Iso> =====
    @TestCase
    func case07_LensIso(): Unit {
        let o1 = lensId()
        let o2 = isoNeg()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(5) == -5)
        @Assert(bwd(3, 9) == -9)
    }

    // ===== case 8 <Iso, Prism>: backward total rebuild =====
    @TestCase
    func case08_IsoPrism(): Unit {
        let o1 = isoNeg()
        let o2 = prismEven()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        // -4 maps through iso to +4 (even -> Some(4)); -3 maps to +3 (odd -> None)
        @Assert(isSomeWith(fwd(-4), 4))
        @Assert(isNone(fwd(-3)))
        // backward: i1from(p2build(5)=8) = -8 (total)
        @Assert(bwd(5) == -8)
    }

    // ===== case 9 <Prism, Iso>: backward total rebuild =====
    @TestCase
    func case09_PrismIso(): Unit {
        let o1 = prismEven()
        let o2 = isoNeg()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(isSomeWith(fwd(4), -4))
        @Assert(isNone(fwd(3)))
        // backward: p1build(i2from(5)=-5) = 8 (total)
        @Assert(bwd(5) == 8)
    }

    // ===== case 10 <Prism, Lens> =====
    @TestCase
    func case10_PrismLens(): Unit {
        let o1 = prismEven()
        let o2 = lensId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(isSomeWith(fwd(4), 4))
        @Assert(isNone(fwd(3)))
        @Assert(bwd(4, 9) == 8)
        @Assert(bwd(3, 9) == 3)
    }

    // ===== case 12 <Iso, Affine> =====
    @TestCase
    func case12_IsoAff(): Unit {
        let o1 = isoNeg()
        let o2 = affPos()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        // focuses when -src > 0, i.e. src < 0; the Some carries the iso-mapped value
        @Assert(isSomeWith(fwd(-4), 4))
        @Assert(isNone(fwd(4)))
        @Assert(bwd(-4, 9) == -9)
        @Assert(bwd(4, 9) == 4)
    }

    // ===== case 13 <Affine, Iso> =====
    @TestCase
    func case13_AffIso(): Unit {
        let o1 = affPos()
        let o2 = isoNeg()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(isSomeWith(fwd(4), -4))
        @Assert(isNone(fwd(-1)))
        // backward replaces with i2from(focus) = -focus
        @Assert(bwd(4, 9) == -9)
        @Assert(bwd(-1, 9) == -1)
    }

    // ===== case 14 <Iso, Setter> =====
    @TestCase
    func case14_IsoSetter(): Unit {
        let o1 = isoNeg()
        let o2 = setWrap()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(5) == 5)
        // i1from(s2modify(i1to(3)=-3, inc)) = -( -3 + 1 ) = 2
        @Assert(bwd(3, inc) == 2)
    }

    // ===== case 15 <Setter, Iso> =====
    @TestCase
    func case15_SetterIso(): Unit {
        let o1 = setWrap()
        let o2 = isoNeg()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(5) == 5)
        // composed(a) = i2from(modifier(i2to(a))) ; setWrap applies it to source
        // composed(3) with inc: -( -3 + 1 ) = 2
        @Assert(bwd(3, inc) == 2)
    }

    // ===== case 16 <Lens, Affine> =====
    @TestCase
    func case16_LensAff(): Unit {
        let o1 = lensId()
        let o2 = affPos()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(isSomeWith(fwd(4), 4))
        @Assert(isNone(fwd(-1)))
        @Assert(bwd(4, 9) == 9)
        @Assert(bwd(-1, 9) == -1)
    }

    // ===== case 17 <Prism, Affine> =====
    @TestCase
    func case17_PrismAff(): Unit {
        let o1 = prismEven()
        let o2 = affPos()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        // 4: even and > 0; 3: odd rejects first stage; -2: even but affine rejects second stage
        @Assert(isSomeWith(fwd(4), 4))
        @Assert(isNone(fwd(3)))
        @Assert(isNone(fwd(-2)))
        @Assert(bwd(4, 9) == 8)
        @Assert(bwd(3, 9) == 3)
        @Assert(bwd(-2, 9) == -2)
    }

    // ===== case 18 <Affine, Lens> =====
    @TestCase
    func case18_AffLens(): Unit {
        let o1 = affPos()
        let o2 = lensId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(isSomeWith(fwd(4), 4))
        @Assert(isNone(fwd(-1)))
        @Assert(bwd(4, 9) == 9)
        @Assert(bwd(-1, 9) == -1)
    }

    // ===== case 19 <Affine, Prism>, affine-side non-match variant added =====
    @TestCase
    func case19_AffPrism_affineSideNonMatchIsIdentity(): Unit {
        let o1 = affPos()
        let o2 = prismEven()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        // -4: affine rejects before the prism is even consulted
        @Assert(bwd(-4, 5) == -4)
    }

    // ===== case 20 <Lens, Setter> =====
    @TestCase
    func case20_LensSetter(): Unit {
        let o1 = lensId()
        let o2 = setWrap()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(5) == 5)
        @Assert(bwd(3, inc) == 4)
    }

    // ===== case 21 <Setter, Lens> =====
    @TestCase
    func case21_SetterLens(): Unit {
        let o1 = setWrap()
        let o2 = lensId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(5) == 5)
        @Assert(bwd(3, inc) == 4)
    }

    // ===== case 22 <Prism, Setter> =====
    @TestCase
    func case22_PrismSetter(): Unit {
        let o1 = prismEven()
        let o2 = setWrap()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(4) == 8)
        @Assert(fwd(3) == 3)
        @Assert(bwd(4, inc) == 8)
        @Assert(bwd(3, inc) == 3)
    }

    // ===== case 23 <Setter, Prism> =====
    @TestCase
    func case23_SetterPrism(): Unit {
        let o1 = setWrap()
        let o2 = prismEven()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(5) == 5)
        // composed(a) = even ? build(modifier(a)) : a
        @Assert(bwd(4, inc) == 8)
        @Assert(bwd(3, inc) == 3)
    }

    // ===== case 24 <Affine, Setter> =====
    @TestCase
    func case24_AffSetter(): Unit {
        let o1 = affPos()
        let o2 = setWrap()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(4) == 4)
        @Assert(fwd(-1) == -1)
        @Assert(bwd(4, inc) == 5)
        @Assert(bwd(-1, inc) == -1)
    }

    // ===== case 25 <Setter, Affine> =====
    @TestCase
    func case25_SetterAff(): Unit {
        let o1 = setWrap()
        let o2 = affPos()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(fwd(5) == 5)
        // composed(a) = a > 0 ? modifier(a) : a
        @Assert(bwd(4, inc) == 5)
        @Assert(bwd(-1, inc) == -1)
    }
}
