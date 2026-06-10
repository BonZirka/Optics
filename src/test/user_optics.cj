package optics_experiments.test

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.stdlib.*
import lucida_macro.*

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
