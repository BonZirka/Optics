package lucida.tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*

// Property laws for the 25 ordered composition pairs.
//
// Canonical instances (all Int64 -> Int64) come from composition_laws.cj
// (isoNeg, lensId, affPos, setWrap) plus a LAWFUL prism defined here: the
// regression suite's prismEven builds a constant on rebuild, which violates
// SetGet; the lawful prism rebuilds the focus itself.
//
// Laws, on a matched source s and focus a:
//   GetSet: set(s, view(s)) == s
//   SetGet: view(set(s, a)) == a
//   SetSet: set(set(s, a1), a2) == set(s, a2)
//
// Composition rows whose kind is Setter have no view — their forward is a
// modify — so only SetSet is asserted for them (9 of the 25 rows). All other
// rows assert the three laws with s = 4, a = 6, a1 = 2, a2 = 5 — inputs
// matched by every canonical instance (even and positive), because the laws
// are quantified over the match set. Sign-flipping or match-breaking
// canonicals (isoNeg, odd rebuilds) would leave the match set mid-chain and
// fail SetGet/SetSet for reasons the composition rows do not own.
// Identity iso: a total iso that keeps every canonical input matched.
func isoId(): Iso<Int64, Int64> {
    Iso<Int64, Int64>({ s: Int64 => s }, { a: Int64 => a })
}

func prismLawful(): Prism<Int64, Int64> {
    Prism<Int64, Int64>(
        { s: Int64 => if (s % 2 == 0) { Right<Int64, Int64>(s) } else { Left<Int64, Int64>(s) } },
        { a: Int64 => a }
    )
}

// Total forward lifted into the Either form the law helpers consume.
func liftFwd(f: (Int64) -> Int64): (Int64) -> Either<Int64, Int64> {
    { s: Int64 => Right<Int64, Int64>(f(s)) }
}

// A prism-rebuild backward (A) -> S unified into the (S, A) -> S form.
func unifyPrismSet(b: (Int64) -> Int64): (Int64, Int64) -> Int64 {
    { s: Int64, a: Int64 => b(a) }
}

// A setter backward (S, (A) -> A) -> S unified with a constant modifier.
func unifySetterSet(b: (Int64, (Int64) -> Int64) -> Int64): (Int64, Int64) -> Int64 {
    { s: Int64, a: Int64 => b(s, { x: Int64 => a }) }
}

func lawGetSet(fwd: (Int64) -> Either<Int64, Int64>, set: (Int64, Int64) -> Int64, s: Int64): Bool {
    match (fwd(s)) {
        case Right(v) => return set(s, v) == s
        case _ => return false
    }
}

func lawSetGet(fwd: (Int64) -> Either<Int64, Int64>, set: (Int64, Int64) -> Int64, s: Int64, a: Int64): Bool {
    match (fwd(set(s, a))) {
        case Right(v) => return v == a
        case _ => return false
    }
}

func lawSetSet(set: (Int64, Int64) -> Int64, s: Int64): Bool {
    return set(set(s, 2), 5) == set(s, 5)
}

// Full triple for rows with a view; SetSet only for setter rows.
func viewLawsHold(fwd: (Int64) -> Either<Int64, Int64>, set: (Int64, Int64) -> Int64): Bool {
    lawGetSet(fwd, set, 4) && lawSetGet(fwd, set, 4, 6) && lawSetSet(set, 4)
}

func setSetHolds(set: (Int64, Int64) -> Int64): Bool {
    lawSetSet(set, 4)
}

// Grounding: the canonical instances themselves satisfy the laws.
@Test
class CanonicalInstanceLaws {
    @TestCase
    func isoIsLawful(): Unit {
        let o = isoNeg()
        @Assert(viewLawsHold(liftFwd(__FirstClassGetters.forward(o)), unifyPrismSet(__FirstClassGetters.backward(o))))
    }

    @TestCase
    func lensIsLawful(): Unit {
        let o = lensId()
        @Assert(viewLawsHold(liftFwd(__FirstClassGetters.forward(o)), __FirstClassGetters.backward(o)))
    }

    @TestCase
    func lawfulPrismIsLawful(): Unit {
        let o = prismLawful()
        var ok = lawGetSet(__FirstClassGetters.forward(o), unifyPrismSet(__FirstClassGetters.backward(o)), 4)
        ok = ok && lawSetGet(__FirstClassGetters.forward(o), unifyPrismSet(__FirstClassGetters.backward(o)), 4, 6)
        ok = ok && lawSetSet(unifyPrismSet(__FirstClassGetters.backward(o)), 4)
        @Assert(ok)
    }

    @TestCase
    func affineIsLawful(): Unit {
        let o = affPos()
        @Assert(viewLawsHold(__FirstClassGetters.forward(o), __FirstClassGetters.backward(o)))
    }

    @TestCase
    func setterSatisfiesSetSet(): Unit {
        let o = setWrap()
        @Assert(setSetHolds(unifySetterSet(__FirstClassGetters.backward(o))))
    }
}

// The 25 ordered composition pairs. Per row: the composed kind determines
// the wrapper (total / partial / prism-rebuild / setter) and which laws hold.
@Test
class CompositionPropertyLaws {
    // ===== case 1 <Iso, Iso> — composed Iso: total, sourceless backward =====
    @TestCase
    func case01_IsoIso(): Unit {
        let o1 = isoId(); let o2 = isoId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(liftFwd(fwd), unifyPrismSet(bwd)))
    }

    // ===== case 2 <Lens, Lens> — composed Lens: total =====
    @TestCase
    func case02_LensLens(): Unit {
        let o1 = lensId(); let o2 = lensId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(liftFwd(fwd), bwd))
    }

    // ===== case 3 <Prism, Prism> — composed Prism: rebuild backward =====
    @TestCase
    func case03_PrismPrism(): Unit {
        let o1 = prismLawful(); let o2 = prismLawful()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(fwd, unifyPrismSet(bwd)))
    }

    // ===== case 4 <Affine, Affine> — composed Affine: sourceful =====
    @TestCase
    func case04_AffAff(): Unit {
        let o1 = affPos(); let o2 = affPos()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(fwd, bwd))
    }

    // ===== case 5 <Setter, Setter> — composed Setter: SetSet only =====
    @TestCase
    func case05_SetterSetter(): Unit {
        let o1 = setWrap(); let o2 = setWrap()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(setSetHolds(unifySetterSet(bwd)))
    }

    // ===== case 6 <Iso, Lens> — composed Iso: total =====
    @TestCase
    func case06_IsoLens(): Unit {
        let o1 = isoId(); let o2 = lensId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(liftFwd(fwd), bwd))
    }

    // ===== case 7 <Lens, Iso> — composed Iso: total =====
    @TestCase
    func case07_LensIso(): Unit {
        let o1 = lensId(); let o2 = isoId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(liftFwd(fwd), bwd))
    }

    // ===== case 8 <Iso, Prism> — composed Prism: rebuild backward =====
    @TestCase
    func case08_IsoPrism(): Unit {
        let o1 = isoId(); let o2 = prismLawful()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(fwd, unifyPrismSet(bwd)))
    }

    // ===== case 9 <Prism, Iso> — composed Prism: rebuild backward =====
    @TestCase
    func case09_PrismIso(): Unit {
        let o1 = prismLawful(); let o2 = isoId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(fwd, unifyPrismSet(bwd)))
    }

    // ===== case 10 <Prism, Lens> — composed Affine: sourceful =====
    @TestCase
    func case10_PrismLens(): Unit {
        let o1 = prismLawful(); let o2 = lensId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(fwd, bwd))
    }

    // ===== case 11 <Lens, Prism> — composed Affine: sourceful =====
    @TestCase
    func case11_LensPrism(): Unit {
        let o1 = lensId(); let o2 = prismLawful()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(fwd, bwd))
    }

    // ===== case 12 <Iso, Affine> — composed Affine: sourceful =====
    @TestCase
    func case12_IsoAff(): Unit {
        let o1 = isoId(); let o2 = affPos()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(fwd, bwd))
    }

    // ===== case 13 <Affine, Iso> — composed Affine: sourceful =====
    @TestCase
    func case13_AffIso(): Unit {
        let o1 = affPos(); let o2 = isoId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(fwd, bwd))
    }

    // ===== case 14 <Iso, Setter> — composed Setter: SetSet only =====
    @TestCase
    func case14_IsoSetter(): Unit {
        let o1 = isoId(); let o2 = setWrap()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(setSetHolds(unifySetterSet(bwd)))
    }

    // ===== case 15 <Setter, Iso> — composed Setter: SetSet only =====
    @TestCase
    func case15_SetterIso(): Unit {
        let o1 = setWrap(); let o2 = isoId()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(setSetHolds(unifySetterSet(bwd)))
    }

    // ===== case 16 <Lens, Affine> — composed Affine: sourceful =====
    @TestCase
    func case16_LensAff(): Unit {
        let o1 = lensId(); let o2 = affPos()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(fwd, bwd))
    }

    // ===== case 17 <Prism, Affine> — composed Affine: sourceful =====
    @TestCase
    func case17_PrismAff(): Unit {
        let o1 = prismLawful(); let o2 = affPos()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(fwd, bwd))
    }

    // ===== case 18 <Affine, Lens> — composed Affine: sourceful =====
    @TestCase
    func case18_AffLens(): Unit {
        let o1 = affPos(); let o2 = lensId()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(fwd, bwd))
    }

    // ===== case 19 <Affine, Prism> — composed Affine: sourceful =====
    @TestCase
    func case19_AffPrism(): Unit {
        let o1 = affPos(); let o2 = prismLawful()
        let fwd = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(viewLawsHold(fwd, bwd))
    }

    // ===== case 20 <Lens, Setter> — composed Setter: SetSet only =====
    @TestCase
    func case20_LensSetter(): Unit {
        let o1 = lensId(); let o2 = setWrap()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(setSetHolds(unifySetterSet(bwd)))
    }

    // ===== case 21 <Setter, Lens> — composed Setter: SetSet only =====
    @TestCase
    func case21_SetterLens(): Unit {
        let o1 = setWrap(); let o2 = lensId()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(setSetHolds(unifySetterSet(bwd)))
    }

    // ===== case 22 <Prism, Setter> — composed Setter: SetSet only =====
    @TestCase
    func case22_PrismSetter(): Unit {
        let o1 = prismLawful(); let o2 = setWrap()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(setSetHolds(unifySetterSet(bwd)))
    }

    // ===== case 23 <Setter, Prism> — composed Setter: SetSet only =====
    @TestCase
    func case23_SetterPrism(): Unit {
        let o1 = setWrap(); let o2 = prismLawful()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(setSetHolds(unifySetterSet(bwd)))
    }

    // ===== case 24 <Affine, Setter> — composed Setter: SetSet only =====
    @TestCase
    func case24_AffSetter(): Unit {
        let o1 = affPos(); let o2 = setWrap()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(setSetHolds(unifySetterSet(bwd)))
    }

    // ===== case 25 <Setter, Affine> — composed Setter: SetSet only =====
    @TestCase
    func case25_SetterAff(): Unit {
        let o1 = setWrap(); let o2 = affPos()
        let bwd = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        @Assert(setSetHolds(unifySetterSet(bwd)))
    }
}
