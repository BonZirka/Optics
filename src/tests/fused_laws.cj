package lucida.tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.stdlib.*
import lucida.macrodsl.*

@DeriveOptics
public struct Box {
    public Box(public let w: Int64) { }
}

@DeriveOptics
public enum Payload2D {
    | Rect(Box)
    | Dot(Int64)
}

@DeriveOptics
public struct PayloadHolder {
    public PayloadHolder(public let shape: Payload2D) { }
}

@DeriveOptics
public enum Wrap2D {
    | Wrap(Payload2D)
}

@DeriveOptics
public enum Deep4 {
    | V4(Int64)
    | N4(Int64)
}

@DeriveOptics
public enum Deep3 {
    | V3(Deep4)
}

@DeriveOptics
public enum Deep2 {
    | V2(Deep3)
}

@DeriveOptics
public enum Deep1 {
    | V1(Deep2)
}

@DeriveOptics
public struct MeterBox {
    public MeterBox(public let m: Meters) { }
}

@DeriveOptics
public struct NestedBox {
    public NestedBox(public let nb: Nested) { }
}

@DeriveOptics
public struct W1 {
    public W1(public let f: Nested) { }
}

@DeriveOptics
public struct WBox {
    public WBox(public let w: W1) { }
}

@DeriveOptics
public enum Shape2D {
    | Circle(Int64)
    | Square(Int64)
}

@DeriveOptics
public struct ShapeHolder {
    public ShapeHolder(public let shape: Shape2D) { }
}

@Test
class FusedPrismLaws {
    @TestCase
    func prismForwardMatch(): Unit {
        let h = ShapeHolder(Circle(7))
        var ok = false
        let fwd = @f(h.shape?.Circle)
        match (fwd) {
            case Some(r) => ok = (r == 7)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func prismForwardMiss(): Unit {
        let h = ShapeHolder(Square(99))
        var leftOk = false
        let fwd = @f(h.shape?.Circle)
        match (fwd) {
            case None => leftOk = true
            case _ => ()
        }
        @Assert(leftOk)
    }

    @TestCase
    func prismBackwardMatch(): Unit {
        let h = ShapeHolder(Circle(7))
        let updated = @f(h.shape?.Circle <- 42)
        var ok = false
        match (updated.shape) {
            case Circle(v) => ok = (v == 42)
            case _ => ()
        }
        @Assert(ok)
    }

    // ===== fused forward must match the library's composed semantics: =====
    // ===== partial chains: the read is Option<B>; a miss is None =====

    // Trailing prism miss: Left must carry the original source (ShapeHolder),
    // not the post-lens value (Shape2D).
    @TestCase
    func trailingPrismForwardMissCarriesSource(): Unit {
        let h = ShapeHolder(Square(99))
        let miss = @f(h.shape?.Circle)
        var ok = false
        match (miss) {
            case None => ok = true
            case _ => ()
        }
        @Assert(ok)
    }

    // Lens->prism->lens forward: full match yields Some(final focus).
    @TestCase
    func mixedLensPrismLensForwardMatch(): Unit {
        let h = PayloadHolder(Rect(Box(42)))
        let fwd = @f(h.shape?.Rect.w)
        var ok = false
        match (fwd) {
            case Some(v) => ok = (v == 42)
            case _ => ()
        }
        @Assert(ok)
    }

    // Lens->prism->lens forward miss: None.
    @TestCase
    func mixedLensPrismLensForwardMissCarriesSource(): Unit {
        let h = PayloadHolder(Dot(1))
        let miss = @f(h.shape?.Rect.w)
        var ok = false
        match (miss) {
            case None => ok = true
            case _ => ()
        }
        @Assert(ok)
    }

    // Prism->prism->lens forward: match and miss.
    @TestCase
    func prismPrismLensForwardMatch(): Unit {
        let w = Wrap2D.Wrap(Rect(Box(7)))
        let fwd = @f(w?.Wrap?.Rect.w)
        var ok = false
        match (fwd) {
            case Some(v) => ok = (v == 7)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func prismPrismLensForwardMissCarriesSource(): Unit {
        let w = Wrap2D.Wrap(Dot(3))
        let miss = @f(w?.Wrap?.Rect.w)
        var ok = false
        match (miss) {
            case None => ok = true
            case _ => ()
        }
        @Assert(ok)
    }

    // Mixed affine + prism chain must fall back to the library composition,
    // not throw inside the macro.
    @TestCase
    func affinePrismForwardFallback(): Unit {
        let shapes = [Payload2D.Dot(1), Payload2D.Rect(Box(7))]
        let fwd = @f(shapes?.selectFirst({ p: Payload2D => match (p) { case Rect(_) => true case _ => false } })?.Rect.w)
        var ok = false
        match (fwd) {
            case Some(v) => ok = (v == 7)
            case _ => ()
        }
        @Assert(ok)
    }

    // Affine (at) -> prism -> lens forward.
    @TestCase
    func atPrismLensForwardMatch(): Unit {
        let shapes = [Payload2D.Dot(1), Payload2D.Rect(Box(7))]
        let fwd = @f(shapes?.at(1)?.Rect.w)
        var ok = false
        match (fwd) {
            case Some(v) => ok = (v == 7)
            case _ => ()
        }
        @Assert(ok)
    }

    // Affine -> prism -> lens backward: rebuild through selectFirst and the prism.
    @TestCase
    func selectFirstPrismLensBackward(): Unit {
        let shapes = [Payload2D.Dot(1), Payload2D.Rect(Box(5))]
        let updated = @f(shapes?.selectFirst({ p: Payload2D => match (p) { case Rect(_) => true case _ => false } })?.Rect.w <- 7)
        var ok = false
        match (updated[1]) {
            case Rect(b) => ok = (b.w == 7)
            case _ => ()
        }
        @Assert(ok)
        // untouched neighbor
        match (updated[0]) {
            case Dot(v) => ok = (v == 1)
            case _ => ()
        }
        @Assert(ok)
    }

    // Affine -> prism -> lens backward with no matching element: identity.
    @TestCase
    func selectFirstPrismLensBackwardMissIsIdentity(): Unit {
        let shapes = [Payload2D.Dot(1), Payload2D.Dot(2)]
        let updated = @f(shapes?.selectFirst({ p: Payload2D => match (p) { case Rect(_) => true case _ => false } })?.Rect.w <- 7)
        var ok = false
        match (updated[0]) {
            case Dot(v) => ok = (v == 1)
            case _ => ()
        }
        @Assert(ok)
        match (updated[1]) {
            case Dot(v) => ok = (v == 2)
            case _ => ()
        }
        @Assert(ok)
    }

    // ===== iso (coerce) chains =====

    // Lens -> iso tail: forward and backward.
    @TestCase
    func coerceTailForward(): Unit {
        let mb = MeterBox(Meters(7))
        let got = @f(mb.m.coerce<Int64>())
        @Assert(got == 7)
    }

    @TestCase
    func coerceTailBackward(): Unit {
        let mb = MeterBox(Meters(7))
        let updated = @f(mb.m.coerce<Int64>() <- 5)
        @Assert(updated.m.v == 5)
    }

    // Lens -> iso -> lens: forward and backward through the middle iso.
    @TestCase
    func coerceMiddleChainForward(): Unit {
        let h = WBox(W1(Nested(3)))
        let got2 = @f(h.w.coerce<Nested>().n)
        @Assert(got2 == 3)
    }

    @TestCase
    func coerceMiddleChainBackward(): Unit {
        let h = WBox(W1(Nested(3)))
        let updated = @f(h.w.coerce<Nested>().n <- 9)
        @Assert(updated.w.f.n == 9)
    }

    // Derived prism -> iso tail: coerce participates in a pinned prism chain.
    @TestCase
    func coerceAfterPrismForwardMatch(): Unit {
        let s = Shape.Circle(Nested(3))
        let fwd = @f(s?.Circle.coerce<Int64>())
        var ok = false
        match (fwd) {
            case Some(v) => ok = (v == 3)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func coerceAfterPrismForwardMissCarriesSource(): Unit {
        let s = Shape.Square(2)
        let miss = @f(s?.Circle.coerce<Int64>())
        var ok = false
        match (miss) {
            case None => ok = true
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func coerceAfterPrismBackward(): Unit {
        let s = Shape.Circle(Nested(3))
        let updated = @f(s?.Circle.coerce<Int64>() <- 5)
        var ok = false
        match (updated) {
            case Circle(inner) => ok = (inner.n == 5)
            case _ => ()
        }
        @Assert(ok)
    }

    // ===== backward regression pins (library fallback path) =====

    @TestCase
    func mixedLensPrismLensBackward(): Unit {
        let h = PayloadHolder(Rect(Box(42)))
        let updated = @f(h.shape?.Rect.w <- 7)
        var ok = false
        match (updated.shape) {
            case Rect(inner) => ok = (inner.w == 7)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func mixedLensPrismLensBackwardMissIsIdentity(): Unit {
        let h = PayloadHolder(Dot(1))
        let updated = @f(h.shape?.Rect.w <- 7)
        var ok = false
        match (updated.shape) {
            case Dot(v) => ok = (v == 1)
            case _ => ()
        }
        @Assert(ok)
    }

    // Prism->prism->lens backward: rebuild through both prisms.
    @TestCase
    func prismPrismLensBackward(): Unit {
        let w = Wrap2D.Wrap(Rect(Box(5)))
        let updated = @f(w?.Wrap?.Rect.w <- 7)
        var ok = false
        match (updated) {
            case Wrap(inner) => match (inner) {
                case Rect(b) => ok = (b.w == 7)
                case _ => ()
            }
        }
        @Assert(ok)
    }

    // Prism->prism->lens backward miss at the inner prism: identity through both.
    @TestCase
    func prismPrismLensBackwardMissIsIdentity(): Unit {
        let w = Wrap2D.Wrap(Dot(3))
        let updated = @f(w?.Wrap?.Rect.w <- 7)
        var ok = false
        match (updated) {
            case Wrap(inner) => match (inner) {
                case Dot(v) => ok = (v == 3)
                case _ => ()
            }
        }
        @Assert(ok)
    }

    // Four prisms in one chain (deepest pinned overload): forward, miss, backward.
    @TestCase
    func fourPrismsForwardMatch(): Unit {
        let d = Deep1.V1(Deep2.V2(Deep3.V3(Deep4.V4(42))))
        let fwd = @f(d?.V1?.V2?.V3?.V4)
        var ok = false
        match (fwd) {
            case Some(v) => ok = (v == 42)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func fourPrismsForwardMissCarriesSource(): Unit {
        let d = Deep1.V1(Deep2.V2(Deep3.V3(Deep4.N4(5))))
        let miss = @f(d?.V1?.V2?.V3?.V4)
        var ok = false
        match (miss) {
            case None => ok = true
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func fourPrismsBackward(): Unit {
        let d = Deep1.V1(Deep2.V2(Deep3.V3(Deep4.V4(42))))
        let updated = @f(d?.V1?.V2?.V3?.V4 <- 9)
        var ok = false
        match (updated) {
            case V1(i2) => match (i2) {
                case V2(i3) => match (i3) {
                    case V3(i4) => match (i4) {
                        case V4(v) => ok = (v == 9)
                        case _ => ()
                    }
                }
            }
        }
        @Assert(ok)
    }

    @TestCase
    func fourPrismsBackwardMissIsIdentity(): Unit {
        let d = Deep1.V1(Deep2.V2(Deep3.V3(Deep4.N4(5))))
        let updated = @f(d?.V1?.V2?.V3?.V4 <- 9)
        var ok = false
        match (updated) {
            case V1(i2) => match (i2) {
                case V2(i3) => match (i3) {
                    case V3(i4) => match (i4) {
                        case N4(v) => ok = (v == 5)
                        case _ => ()
                    }
                }
            }
        }
        @Assert(ok)
    }

    @TestCase
    func prismBackwardMissIsIdentity(): Unit {
        let h = ShapeHolder(Square(99))
        let updated = @f(h.shape?.Circle <- 42)
        // Original source type preserved; non-match => identity
        match (updated.shape) {
            case Square(v) => @Assert(v == 99)
            case _ => @Assert(false)
        }
    }
}

@DeriveOptics
public enum Huge10 {
    | H10(Int64)
    | M10(Int64)
}

@DeriveOptics
public enum Huge9 {
    | H9(Huge10)
    | M9(Int64)
}

@DeriveOptics
public enum Huge8 {
    | H8(Huge9)
    | M8(Int64)
}

@DeriveOptics
public enum Huge7 {
    | H7(Huge8)
    | M7(Int64)
}

@DeriveOptics
public enum Huge6 {
    | H6(Huge7)
    | M6(Int64)
}

@DeriveOptics
public enum Huge5 {
    | H5(Huge6)
    | M5(Int64)
}

@DeriveOptics
public enum Huge4 {
    | H4(Huge5)
    | M4(Int64)
}

@DeriveOptics
public enum Huge3 {
    | H3(Huge4)
    | M3(Int64)
}

@DeriveOptics
public enum Huge2 {
    | H2(Huge3)
    | M2(Int64)
}

@DeriveOptics
public enum Huge1 {
    | H1(Huge2)
    | M1(Int64)
}

func hugeDeep(): Huge1 {
    Huge1.H1(Huge2.H2(Huge3.H3(Huge4.H4(Huge5.H5(Huge6.H6(Huge7.H7(Huge8.H8(Huge9.H9(Huge10.H10(42))))))))))
}

func hugeMiss(): Huge1 {
    Huge1.H1(Huge2.H2(Huge3.H3(Huge4.H4(Huge5.H5(Huge6.H6(Huge7.H7(Huge8.H8(Huge9.H9(Huge10.M10(5))))))))))
}

// Ten Option-producing segments — deeper than the historical hand-unrolled
// pyramid (8). Read chains at this depth used to silently fall back to
// library composition.
@Test
class TenPrismChainLaws {
    @TestCase
    func tenPrismsForwardMatch(): Unit {
        var ok = false
        match (@f(hugeDeep()?.H1?.H2?.H3?.H4?.H5?.H6?.H7?.H8?.H9?.H10)) {
            case Some(v) => ok = (v == 42)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func tenPrismsForwardMissCarriesSource(): Unit {
        var ok = false
        match (@f(hugeMiss()?.H1?.H2?.H3?.H4?.H5?.H6?.H7?.H8?.H9?.H10)) {
            case None => ok = true
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func tenPrismsBackwardRoundTrip(): Unit {
        let updated = @f(hugeDeep()?.H1?.H2?.H3?.H4?.H5?.H6?.H7?.H8?.H9?.H10 <- 9)
        var ok = false
        match (@f(updated?.H1?.H2?.H3?.H4?.H5?.H6?.H7?.H8?.H9?.H10)) {
            case Some(v) => ok = (v == 9)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func tenPrismsBackwardMissIsIdentity(): Unit {
        let updated = @f(hugeMiss()?.H1?.H2?.H3?.H4?.H5?.H6?.H7?.H8?.H9?.H10 <- 9)
        var ok = false
        match (@f(updated?.H1?.H2?.H3?.H4?.H5?.H6?.H7?.H8?.H9?.H10)) {
            case None => ok = true
            case _ => ()
        }
        @Assert(ok)
    }
}

@Test
class FusedLensLaws {
    @TestCase
    func deepLensChainForward(): Unit {
        let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
        let got = @f(o.customer.address.city.name)
        @Assert(got == "Atlanta")
        let got2 = @f(o.customer.address.city.zip)
        @Assert(got2 == 30301)
    }

    @TestCase
    func deepLensChainBackwardImmutable(): Unit {
        let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
        let updated = @f(o.customer.address.city.name <- "Denver")
        @Assert(updated.customer.address.city.name == "Denver")
        @Assert(o.customer.address.city.name == "Atlanta")
        @Assert(updated.id == 1)
    }

    @TestCase
    func deepLensChainRoundTrip(): Unit {
        let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
        let z = @f(o.customer.address.city.zip)
        let rewritten = @f(o.customer.address.city.zip <- z)
        @Assert(rewritten.customer.address.city.zip == o.customer.address.city.zip)
    }

    @TestCase
    func unfusedForward(): Unit {
        let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
        let got3 = @f[unfuse](o.customer.address.city.name)
        @Assert(got3 == "Atlanta")
    }

    @TestCase
    func unfusedBackward(): Unit {
        let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
        let updated = @f[unfuse](o.customer.address.city.name <- "Denver")
        @Assert(updated.customer.address.city.name == "Denver")
        @Assert(o.customer.address.city.name == "Atlanta")
        @Assert(updated.id == 1)
    }
}
