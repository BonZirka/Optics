package tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.macrodsl.*

public struct GPair<T, U> {
    public GPair(public let first: T, public let second: U) { }
}

// ===== User-declared optics (see 2026-09-09-user-declared-optics-design.md) =====

@Optic[
    source: Array<T>
    focus: T
    kind: Affine
    args: (n: Int64)
    forward: { if (let Some(f) <- source.get(n)) { Some(f) } else { None } }
    backward: { let a = source.clone(); a[n] = focus; a }
]
struct at2<T> {}

public struct UBox {
    public UBox(public let v: Int64) { }
}

@Optic[
    source: UBox
    focus: Int64
    kind: Lens
    forward: { source.v }
    backward: { UBox(focus) }
]
struct uBoxLens {}

public struct ULen {
    public ULen(public let m: Int64) { }
}

@Optic[
    source: ULen
    focus: Int64
    kind: Iso
    forward: { source.m }
    backward: { ULen(focus) }
]
struct uLenIso {}

public enum UMaybe {
    | UJust(Int64)
    | UNothing
}

@Optic[
    source: UMaybe
    focus: Int64
    kind: Prism
    forward: { match (source) { case UJust(v) => Some(v) case _ => None } }
    backward: { UJust(focus) }
]
struct uJust {}

@Optic[source: GBox<T>, focus: T, kind: Lens, forward: { source.v }, backward: { GBox(focus) }]
struct guBoxLens<T> {}

@Optic[source: GBox<T>, focus: T, kind: Lens, forward: { source.v }, backward: { GBox(focus) }]
struct guBoxLensStr<T> {}

@Optic[source: GBox<T>, focus: T, kind: Affine, forward: { Some(source.v) }, backward: { GBox(focus) }]
struct guBoxAffine<T> {}

@Optic[source: GBox<T>, focus: Int64, kind: Lens, forward: { 1 }, backward: { source }]
struct guBoxTag<T> {}

@Optic[source: GBox<GBox<T>>, focus: T, kind: Lens, forward: { source.v.v }, backward: { GBox(GBox(focus)) }]
struct guBoxNested<T> {}

@Optic[source: GPair<T, U>, focus: T, kind: Lens, forward: { source.first }, backward: { GPair(focus, source.second) }]
struct gpairFirst<T, U> {}

// ===== renamed slots (spec docs/superpowers/specs/2026-09-29-optic-slot-renames-design.md) =====

@Optic[source: UBox, focus: Int64, kind: Lens, forward: { s => s.v }, backward: { s, d => UBox(s.v + d) }]
struct uRenLens {}

@Optic[source: UMaybe, focus: Int64, kind: Prism, forward: { m => match (m) { case UJust(v) => Some(v) case _ => None } }, backward: { d => UJust(d) }]
struct uRenPrism {}

@Optic[source: UMaybe, focus: Int64, kind: Affine, forward: { m => match (m) { case UJust(v) => Some(v) case _ => None } }, backward: { m, d => match (m) { case UJust(_) => UJust(d) case _ => m } }]
struct uRenAffine {}

@Optic[source: UBox, focus: Int64, kind: Lens, forward: { _ => 42 }, backward: { _, d => UBox(d) }]
struct uRenSkip {}

@Optic[source: UBox, focus: Int64, kind: Lens, forward: { s => let source = 3; s.v + source }, backward: { s, d => UBox(s.v + d) }]
struct uRenShadow {}

@Test
class OpticChainForms {
    // A first-class optic can be built from a derived one and applied mid-chain.
    @TestCase
    func firstClassFromDerived(): Unit {
        let b = UBox(3)
        let lens = @f(@typeof(b).uBoxLens())
        let got = @f(b.@use(lens))
        @Assert(got == 3)
        @Assert(b.v == 3)
    }

    // An Optic node can START a chain: no source anchor, the chain just
    // round-trips the optic value.
    @TestCase
    func opticStartRoundTrip(): Unit {
        let b = UBox(3)
        let lens = @f(@typeof(b).uBoxLens())
        let same = @f(@use(lens))
        let got2 = @f(b.@use(same))
        @Assert(got2 == 3)
        @Assert(b.v == 3)
    }

    // Optic-first setter: produces a first-class setter value from an optic and
    // a target, with no source in the chain; applying it updates a new value.
    @TestCase
    func opticStartSetter(): Unit {
        let b = UBox(3)
        let lens = @f(@typeof(b).uBoxLens())
        let setter = @f(@use(lens) <- 42)
        let updated = @f(b.@use(setter))
        @Assert(updated.v == 42)
        @Assert(b.v == 3)
    }
}

@Test
class UserAffineOpticLaws {
    @TestCase
    func forwardMatch(): Unit {
        let xs = [1, 2, 3]
        var ok = false
        match (@f(xs?.at2(1))) {
            case Some(r) => ok = (r == 2)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func forwardMissIsIdentity(): Unit {
        let xs = [1, 2, 3]
        var ok = false
        match (@f(xs?.at2(10))) {
            case None => ok = true
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func backwardUpdate(): Unit {
        let xs = [1, 2, 3]
        let updated = @f(xs?.at2(1) <- 9)
        @Assert(updated[1] == 9)
        @Assert(updated[0] == 1 && updated[2] == 3)
    }

    @TestCase
    func backwardMissIsIdentity(): Unit {
        let xs = [1, 2, 3]
        let updated = @f(xs?.at2(10) <- 9)
        @Assert(updated == xs)
    }
}

@Test
class UserLensIsoPrismLaws {
    @TestCase
    func lensForward(): Unit {
        let b = UBox(3)
        let got3 = @f(b.uBoxLens())
        @Assert(got3 == 3)
    }

    @TestCase
    func lensBackward(): Unit {
        let b = UBox(3)
        let got4 = @f(b.uBoxLens() <- 5).v
        @Assert(got4 == 5)
    }

    @TestCase
    func chainMembersMinted(): Unit {
        // @Optic mints the first-class chain member for mid-chain upcasts
        // even when no chain here routes through it — keep them exercised.
        let _ = RegistryMagical<UBox>().__method_uBoxLens_optics(RegistryMagical<UBox>())
        let _ = RegistryMagical<ULen>().__method_uLenIso_optics(RegistryMagical<ULen>())
        let _ = RegistryMagical<UMaybe>().__method_uJust_optics(RegistryMagical<UMaybe>())
    }

    @TestCase
    func isoForward(): Unit {
        let m = ULen(5)
        let got5 = @f(m.uLenIso())
        @Assert(got5 == 5)
    }

    @TestCase
    func isoBackward(): Unit {
        let m = ULen(5)
        let got6 = @f(m.uLenIso() <- 9).m
        @Assert(got6 == 9)
    }

    @TestCase
    func prismForwardMatch(): Unit {
        let m = UMaybe.UJust(7)
        var ok = false
        match (@f(m?.uJust())) {
            case Some(r) => ok = (r == 7)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func prismForwardMissCarriesSource(): Unit {
        let m = UMaybe.UNothing
        let fwd = @f(m?.uJust())
        var ok = false
        match (fwd) {
            case None => ok = true
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func prismBackward(): Unit {
        let m = UMaybe.UJust(7)
        let bwd = @f(m?.uJust() <- 9)
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
        let bwd = @f(m?.uJust() <- 9)
        var ok = false
        match (bwd) {
            case UNothing => ok = true
            case _ => ()
        }
        @Assert(ok)
    }
}

@Test
class UserMixedChainLaws {
    @TestCase
    func userTailAfterBuiltinAffine(): Unit {
        let bs = [UBox(1), UBox(2)]
        var ok = false
        match (@f(bs?.at2(0).uBoxLens())) {
            case Some(r) => ok = (r == 1)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func userTailAfterBuiltinAffineBackward(): Unit {
        let bs = [UBox(1), UBox(2)]
        let updated = @f(bs?.at2(0).uBoxLens() <- 7)
        @Assert(updated[0].v == 7 && updated[1].v == 2)
    }

    @TestCase
    func userPrismAfterBuiltinAffine(): Unit {
        let ms = [UMaybe.UJust(1), UMaybe.UNothing]
        var ok = false
        match (@f(ms?.at2(0)?.uJust())) {
            case Some(r) => ok = (r == 1)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func userPrismAfterBuiltinAffineMissCarriesOriginalSource(): Unit {
        let ms = [UMaybe.UJust(1), UMaybe.UNothing]
        var ok = false
        match (@f(ms?.at2(1)?.uJust())) {
            case None => ok = true
            case _ => ()
        }
        // the original array is untouched
        var originalKept = false
        match (ms[1]) {
            case UNothing => originalKept = true
            case _ => ()
        }
        @Assert(originalKept)
        @Assert(ok)
    }

    @TestCase
    func unfuseFallbackStillWorks(): Unit {
        let xs = [1, 2, 3]
        let updated = @f[unfuse](xs.at2(1) <- 9)
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
        let got7 = @f(gb.guBoxLens())
        @Assert(got7 == 5)
        let updated = @f(gb.guBoxLens() <- 9)
        @Assert(updated.v == 9)
    }

    // Explicit carrier generics with call-site inference: the carrier carries
    // <T>; members emit as a generic extension and T is inferred per call site.
    @TestCase
    func explicitCarrierStringLensForwardBackward(): Unit {
        let gb = GBox<String>("x")
        let got8 = @f(gb.guBoxLensStr())
        @Assert(got8 == "x")
        let updated = @f(gb.guBoxLensStr() <- "y")
        @Assert(updated.v == "y")
    }

    // Generic affine: '?.' read yields Some(value); [unfuse] write composes
    // the parametric registry off the fusion walk (mark-agnostic, like
    // salary_bump).
    @TestCase
    func genericAffineReadAndUnfuseWrite(): Unit {
        let gb = GBox<Int64>(5)
        let rd = @f(gb?.guBoxAffine())
        var ok = false
        match (rd) {
            case Some(v) => ok = (v == 5)
            case _ => ()
        }
        @Assert(ok)
        let updated = @f[unfuse](gb.guBoxAffine() <- 9)
        @Assert(updated.v == 9)
    }

    // Parameter only in source: a read-mostly optic over GBox<T> focusing a
    // concrete type; identity backward keeps writes lossless.
    @TestCase
    func paramOnlyInSource(): Unit {
        let gb = GBox<String>("x")
        let got9 = @f(gb.guBoxTag())
        @Assert(got9 == 1)
        let updated = @f(gb.guBoxTag() <- 7)
        @Assert(updated.v == "x")
    }

    // Nested parameter (spec: nesting works — type text is spliced verbatim).
    @TestCase
    func nestedGenericLens(): Unit {
        let g = GBox<GBox<Int64>>(GBox(3))
        let got10 = @f(g.guBoxNested())
        @Assert(got10 == 3)
        let updated = @f(g.guBoxNested() <- 4)
        @Assert(updated.v.v == 4)
    }

    // Multi-parameter carrier: both params thread through genHdr.
    @TestCase
    func multiParamExplicitCarrier(): Unit {
        let gp = GPair<Int64, String>(1, "a")
        let got11 = @f(gp.gpairFirst())
        @Assert(got11 == 1)
        let updated = @f(gp.gpairFirst() <- 2)
        @Assert(updated.first == 2)
        @Assert(updated.second == "a")
    }

    // Generic affine FUSED write through the parametric registry ('?.' mark,
    // gated walk — complement to the [unfuse] write from Task 3).
    @TestCase
    func genericAffineFusedWrite(): Unit {
        let gb = GBox<Int64>(5)
        let updated = @f(gb?.guBoxAffine() <- 9)
        @Assert(updated.v == 9)
    }

    // Second instantiation pins per-call-site inference for the
    // param-only-in-source shape.
    @TestCase
    func paramOnlyInSourceSecondInstantiation(): Unit {
        let gb = GBox<Bool>(true)
        let got12 = @f(gb.guBoxTag())
        @Assert(got12 == 1)
    }

    // Manual-registry multi-arg call site (the salary_bump pattern): member
    // generics that are pinned only by the receiver require explicit type
    // arguments, so the walk must reconstruct the segment call with
    // comma-separated type arguments before classification.
    @TestCase
    func manualRegistryMultiTypeArg(): Unit {
        let gp = GPair<Int64, String>(1, "a")
        let focused = @f(gp.mfirst<Int64, String>())
        @Assert(focused.first == 1 && focused.second == "a")
    }
}

@Test
class OpticSlotRenames {
    @TestCase
    func renamedLensRoundTrip(): Unit {
        let b = UBox(3)
        let got = @f(b.uRenLens())
        @Assert(got == 3)
        let updated = @f(b.uRenLens() <- 5)
        @Assert(updated.v == 8)
    }

    @TestCase
    func renamedPrismSourcelessBackward(): Unit {
        let m = UMaybe.UJust(4)
        let got = @f(m?.uRenPrism())
        @Assert(got == 4)
        let updated = @f(m?.uRenPrism() <- 7)
        var ok = false
        match (updated) {
            case UJust(v) => ok = (v == 7)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func renamedAffineBackwardMissKeepsSource(): Unit {
        let n = UMaybe.UNothing
        let updated = @f(n?.uRenAffine() <- 7)
        var ok = false
        match (updated) {
            case UNothing => ok = true
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func skippedSlot(): Unit {
        let b = UBox(3)
        let got = @f(b.uRenSkip())
        @Assert(got == 42)
        let updated = @f(b.uRenSkip() <- 5)
        @Assert(updated.v == 5)
    }

    @TestCase
    func renameEscapesSlotShadowing(): Unit {
        let b = UBox(3)
        let got = @f(b.uRenShadow())
        @Assert(got == 6)
        let updated = @f(b.uRenShadow() <- 4)
        @Assert(updated.v == 7)
    }
}
