package optics_experiments.test

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.stdlib.*
import lucida_macro.*

public struct GPair<T, U> {
    public GPair(public let first: T, public let second: U) { }
}

// ===== User-declared optics (see 2026-09-09-user-declared-optics-design.md) =====

@LucidaOptic[
    source: Array<T>
    focus: T
    kind: Affine
    args: (n: Int64)
    forward: { if (let Some(f) <- src.get(n)) { Right(f) } else { Left(src) } }
    backward: { let a = src.clone(); a[n] = focus; a }
]
struct at2<T> {}

public struct UBox {
    public UBox(public let v: Int64) { }
}

@LucidaOptic[
    source: UBox
    focus: Int64
    kind: Lens
    forward: { src.v }
    backward: { UBox(focus) }
]
struct uBoxLens {}

public struct ULen {
    public ULen(public let m: Int64) { }
}

@LucidaOptic[
    source: ULen
    focus: Int64
    kind: Iso
    forward: { src.m }
    backward: { ULen(focus) }
]
struct uLenIso {}

public enum UMaybe {
    | UJust(Int64)
    | UNothing
}

@LucidaOptic[
    source: UMaybe
    focus: Int64
    kind: Prism
    forward: { match (src) { case UJust(v) => Right(v) case _ => Left(src) } }
    backward: { UJust(focus) }
]
struct uJust {}

@LucidaOptic[source: GBox<T>, focus: T, kind: Lens, forward: { src.v }, backward: { GBox(focus) }]
struct guBoxLens<T> {}

@LucidaOptic[source: GBox<T>, focus: T, kind: Lens, forward: { src.v }, backward: { GBox(focus) }]
struct guBoxLensStr<T> {}

@LucidaOptic[source: GBox<T>, focus: T, kind: Affine, forward: { Right(src.v) }, backward: { GBox(focus) }]
struct guBoxAffine<T> {}

@LucidaOptic[source: GBox<T>, focus: Int64, kind: Lens, forward: { 1 }, backward: { src }]
struct guBoxTag<T> {}

@LucidaOptic[source: GBox<GBox<T>>, focus: T, kind: Lens, forward: { src.v.v }, backward: { GBox(GBox(focus)) }]
struct guBoxNested<T> {}

@LucidaOptic[source: GPair<T, U>, focus: T, kind: Lens, forward: { src.first }, backward: { GPair(focus, src.second) }]
struct gpairFirst<T, U> {}

@Test
class UserAffineOpticLaws {
    @TestCase
    func forwardMatch(): Unit {
        let xs = [1, 2, 3]
        var ok = false
        match (@Lucida(xs?.at2(1))) {
            case Right(r) => ok = (r == 2)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func forwardMissIsIdentity(): Unit {
        let xs = [1, 2, 3]
        var ok = false
        match (@Lucida(xs?.at2(10))) {
            case Left(l) => ok = (l == xs)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func backwardUpdate(): Unit {
        let xs = [1, 2, 3]
        let updated = @Lucida(xs?.at2(1) <- 9)
        @Assert(updated[1] == 9)
        @Assert(updated[0] == 1 && updated[2] == 3)
    }

    @TestCase
    func backwardMissIsIdentity(): Unit {
        let xs = [1, 2, 3]
        let updated = @Lucida(xs?.at2(10) <- 9)
        @Assert(updated == xs)
    }
}

@Test
class UserLensIsoPrismLaws {
    @TestCase
    func lensForward(): Unit {
        let b = UBox(3)
        @Assert(@Lucida(b.uBoxLens()) == 3)
    }

    @TestCase
    func lensBackward(): Unit {
        let b = UBox(3)
        @Assert(@Lucida(b.uBoxLens() <- 5).v == 5)
    }

    @TestCase
    func isoForward(): Unit {
        let m = ULen(5)
        @Assert(@Lucida(m.uLenIso()) == 5)
    }

    @TestCase
    func isoBackward(): Unit {
        let m = ULen(5)
        @Assert(@Lucida(m.uLenIso() <- 9).m == 9)
    }

    @TestCase
    func prismForwardMatch(): Unit {
        let m = UMaybe.UJust(7)
        var ok = false
        match (@Lucida(m?.uJust())) {
            case Right(r) => ok = (r == 7)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func prismForwardMissCarriesSource(): Unit {
        let m = UMaybe.UNothing
        let fwd = @Lucida(m?.uJust())
        var ok = false
        match (fwd) {
            case Left(l) =>
                match (l) {
                    case UNothing => ok = true
                    case _ => ()
                }
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func prismBackward(): Unit {
        let m = UMaybe.UJust(7)
        let bwd = @Lucida(m?.uJust() <- 9)
        var ok = false
        match (bwd) {
            case UJust(v) => ok = (v == 9)
            case UNothing => ()
        }
        @Assert(ok)
    }

    @TestCase
    func prismBackwardMissIsIdentity(): Unit {
        let m = UMaybe.UNothing
        let bwd = @Lucida(m?.uJust() <- 9)
        var ok = false
        match (bwd) {
            case UNothing => ok = true
            case _ => ()
        }
        @Assert(ok)
    }
}

func sameMaybe(a: Array<UMaybe>, b: Array<UMaybe>): Bool {
    if (a.size != b.size) { return false }
    for (i in 0..a.size) {
        let (x, y) = (a[i], b[i])
        let xe = match (x) { case UJust(v) => v case UNothing => -1 }
        let ye = match (y) { case UJust(v) => v case UNothing => -1 }
        let xs = match (x) { case UJust(_) => true case UNothing => false }
        let ys = match (y) { case UJust(_) => true case UNothing => false }
        if (xs != ys || xe != ye) { return false }
    }
    return true
}

@Test
class UserMixedChainLaws {
    @TestCase
    func userTailAfterBuiltinAffine(): Unit {
        let bs = [UBox(1), UBox(2)]
        var ok = false
        match (@Lucida(bs?.at2(0).uBoxLens())) {
            case Right(r) => ok = (r == 1)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func userTailAfterBuiltinAffineBackward(): Unit {
        let bs = [UBox(1), UBox(2)]
        let updated = @Lucida(bs?.at2(0).uBoxLens() <- 7)
        @Assert(updated[0].v == 7 && updated[1].v == 2)
    }

    @TestCase
    func userPrismAfterBuiltinAffine(): Unit {
        let ms = [UMaybe.UJust(1), UMaybe.UNothing]
        var ok = false
        match (@Lucida(ms?.at2(0)?.uJust())) {
            case Right(r) => ok = (r == 1)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func userPrismAfterBuiltinAffineMissCarriesOriginalSource(): Unit {
        let ms = [UMaybe.UJust(1), UMaybe.UNothing]
        var ok = false
        match (@Lucida(ms?.at2(1)?.uJust())) {
            case Left(l) => ok = sameMaybe(l, ms)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func unfuseFallbackStillWorks(): Unit {
        let xs = [1, 2, 3]
        let updated = @Lucida[unfuse](xs.at2(1) <- 9)
        @Assert(updated[1] == 9)
    }
}

// Manual registry with member-level generics (the salary_bump pattern):
// the accessor signatures pin T and U only through the receiver, so the
// call site must pass them explicitly. Identity lens keeps the member
// bodies trivial while exercising the multi-arg call-site path.
extend RegistryMagical<GPair<Int64, String>> {
    public func __downcast_method_mfirst<T, U>(_: RegistryMagical<GPair<T, U>>): RegistryLenses<GPair<T, U>> {
        RegistryLenses()
    }
    public func __method_mfirst_optics<T, U>(_: RegistryMagical<GPair<T, U>>): RegistryMagical<GPair<T, U>> {
        RegistryMagical()
    }
}

extend RegistryLenses<GPair<Int64, String>> {
    public func __method_mfirst_impl_forward<T, U>(_: RegistryMagical<GPair<T, U>>): (GPair<T, U>) -> GPair<T, U> {
        { source: GPair<T, U> => source }
    }
    public func __method_mfirst_impl_backward<T, U>(_: RegistryMagical<GPair<T, U>>): (GPair<T, U>) -> GPair<T, U> {
        { focus: GPair<T, U> => focus }
    }
}

@Test
class GenericUserOpticLaws {
    // Explicit carrier-generic route: struct carries <T>, members emit as a
    // generic extension, call sites infer T from the receiver's registry.
    @TestCase
    func explicitGenericLensForwardBackward(): Unit {
        let gb = GBox<Int64>(5)
        @Assert(@Lucida(gb.guBoxLens()) == 5)
        let updated = @Lucida(gb.guBoxLens() <- 9)
        @Assert(updated.v == 9)
    }

    // Explicit carrier generics with call-site inference: the carrier carries
    // <T>; members emit as a generic extension and T is inferred per call site.
    @TestCase
    func explicitCarrierStringLensForwardBackward(): Unit {
        let gb = GBox<String>("x")
        @Assert(@Lucida(gb.guBoxLensStr()) == "x")
        let updated = @Lucida(gb.guBoxLensStr() <- "y")
        @Assert(updated.v == "y")
    }

    // Generic affine: '?.' read yields Right(value); [unfuse] write composes
    // the parametric registry off the fusion walk (mark-agnostic, like
    // salary_bump).
    @TestCase
    func genericAffineReadAndUnfuseWrite(): Unit {
        let gb = GBox<Int64>(5)
        let rd = @Lucida(gb?.guBoxAffine())
        var ok = false
        match (rd) {
            case Right(v) => ok = (v == 5)
            case _ => ()
        }
        @Assert(ok)
        let updated = @Lucida[unfuse](gb.guBoxAffine() <- 9)
        @Assert(updated.v == 9)
    }

    // Parameter only in source: a read-mostly optic over GBox<T> focusing a
    // concrete type; identity backward keeps writes lossless.
    @TestCase
    func paramOnlyInSource(): Unit {
        let gb = GBox<String>("x")
        @Assert(@Lucida(gb.guBoxTag()) == 1)
        let updated = @Lucida(gb.guBoxTag() <- 7)
        @Assert(updated.v == "x")
    }

    // Nested parameter (spec: nesting works — type text is spliced verbatim).
    @TestCase
    func nestedGenericLens(): Unit {
        let g = GBox<GBox<Int64>>(GBox(3))
        @Assert(@Lucida(g.guBoxNested()) == 3)
        let updated = @Lucida(g.guBoxNested() <- 4)
        @Assert(updated.v.v == 4)
    }

    // Multi-parameter carrier: both params thread through genHdr.
    @TestCase
    func multiParamExplicitCarrier(): Unit {
        let gp = GPair<Int64, String>(1, "a")
        @Assert(@Lucida(gp.gpairFirst()) == 1)
        let updated = @Lucida(gp.gpairFirst() <- 2)
        @Assert(updated.first == 2)
        @Assert(updated.second == "a")
    }

    // Generic affine FUSED write through the parametric registry ('?.' mark,
    // gated walk — complement to the [unfuse] write from Task 3).
    @TestCase
    func genericAffineFusedWrite(): Unit {
        let gb = GBox<Int64>(5)
        let updated = @Lucida(gb?.guBoxAffine() <- 9)
        @Assert(updated.v == 9)
    }

    // Second instantiation pins per-call-site inference for the
    // param-only-in-source shape.
    @TestCase
    func paramOnlyInSourceSecondInstantiation(): Unit {
        let gb = GBox<Bool>(true)
        @Assert(@Lucida(gb.guBoxTag()) == 1)
    }

    // Manual-registry multi-arg call site (the salary_bump pattern): member
    // generics that are pinned only by the receiver require explicit type
    // arguments, so the walk must reconstruct the segment call with
    // comma-separated type arguments before classification.
    @TestCase
    func manualRegistryMultiTypeArg(): Unit {
        let gp = GPair<Int64, String>(1, "a")
        let focused = @Lucida(gp.mfirst<Int64, String>())
        @Assert(focused.first == 1 && focused.second == "a")
    }
}
