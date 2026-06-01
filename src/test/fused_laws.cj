package optics_experiments.test

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.stdlib.*
import lucida_macro.*

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
        let fwd = @Lucida(h.shape?.Circle)
        match (fwd) {
            case Right(r) => ok = (r == 7)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func prismForwardMiss(): Unit {
        let h = ShapeHolder(Square(99))
        var leftOk = false
        let fwd = @Lucida(h.shape?.Circle)
        match (fwd) {
            case Left(_) => leftOk = true
            case _ => ()
        }
        @Assert(leftOk)
    }

    @TestCase
    func prismBackwardMatch(): Unit {
        let h = ShapeHolder(Circle(7))
        let updated = @Lucida(h.shape?.Circle <- 42)
        var ok = false
        match (updated.shape) {
            case Circle(v) => ok = (v == 42)
            case _ => ()
        }
        @Assert(ok)
    }

    // ===== fused forward must match the library's composed semantics: =====
    // ===== Either<S, B> with Left carrying the ORIGINAL chain source =====

    // Trailing prism miss: Left must carry the original source (ShapeHolder),
    // not the post-lens value (Shape2D).
    @TestCase
    func trailingPrismForwardMissCarriesSource(): Unit {
        let h = ShapeHolder(Square(99))
        let miss = @Lucida(h.shape?.Circle)
        var ok = false
        match (miss) {
            case Left(src) => match (src.shape) {
                case Square(v) => ok = (v == 99)
                case _ => ()
            }
            case _ => ()
        }
        @Assert(ok)
    }

    // Lens->prism->lens forward: full match yields Right(final focus).
    @TestCase
    func mixedLensPrismLensForwardMatch(): Unit {
        let h = PayloadHolder(Rect(Box(42)))
        let fwd = @Lucida(h.shape?.Rect.w)
        var ok = false
        match (fwd) {
            case Right(v) => ok = (v == 42)
            case _ => ()
        }
        @Assert(ok)
    }

    // Lens->prism->lens forward miss: Left carries the original source.
    @TestCase
    func mixedLensPrismLensForwardMissCarriesSource(): Unit {
        let h = PayloadHolder(Dot(1))
        let miss = @Lucida(h.shape?.Rect.w)
        var ok = false
        match (miss) {
            case Left(src) => match (src.shape) {
                case Dot(v) => ok = (v == 1)
                case _ => ()
            }
            case _ => ()
        }
        @Assert(ok)
    }

    // Prism->prism->lens forward: match and miss.
    @TestCase
    func prismPrismLensForwardMatch(): Unit {
        let w = Wrap2D.Wrap(Rect(Box(7)))
        let fwd = @Lucida(w?.Wrap?.Rect.w)
        var ok = false
        match (fwd) {
            case Right(v) => ok = (v == 7)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func prismPrismLensForwardMissCarriesSource(): Unit {
        let w = Wrap2D.Wrap(Dot(3))
        let miss = @Lucida(w?.Wrap?.Rect.w)
        var ok = false
        match (miss) {
            case Left(src) => match (src) {
                case Wrap(inner) => match (inner) {
                    case Dot(v) => ok = (v == 3)
                    case _ => ()
                }
                case _ => ()
            }
            case _ => ()
        }
        @Assert(ok)
    }

    // Mixed affine + prism chain must fall back to the library composition,
    // not throw inside the macro.
    @TestCase
    func affinePrismForwardFallback(): Unit {
        let shapes = [Payload2D.Dot(1), Payload2D.Rect(Box(7))]
        let fwd = @Lucida(shapes.selectFirst({ p: Payload2D => match (p) { case Rect(_) => true case _ => false } })?.Rect.w)
        var ok = false
        match (fwd) {
            case Right(v) => ok = (v == 7)
            case _ => ()
        }
        @Assert(ok)
    }

    // Affine (at) -> prism -> lens forward.
    @TestCase
    func atPrismLensForwardMatch(): Unit {
        let shapes = [Payload2D.Dot(1), Payload2D.Rect(Box(7))]
        let fwd = @Lucida(shapes.at(1)?.Rect.w)
        var ok = false
        match (fwd) {
            case Right(v) => ok = (v == 7)
            case _ => ()
        }
        @Assert(ok)
    }

    // Affine -> prism -> lens backward: rebuild through selectFirst and the prism.
    @TestCase
    func selectFirstPrismLensBackward(): Unit {
        let shapes = [Payload2D.Dot(1), Payload2D.Rect(Box(5))]
        let updated = @Lucida(shapes.selectFirst({ p: Payload2D => match (p) { case Rect(_) => true case _ => false } })?.Rect.w <- 7)
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
        let updated = @Lucida(shapes.selectFirst({ p: Payload2D => match (p) { case Rect(_) => true case _ => false } })?.Rect.w <- 7)
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
        @Assert(@Lucida(mb.m.coerce<Int64>()) == 7)
    }

    @TestCase
    func coerceTailBackward(): Unit {
        let mb = MeterBox(Meters(7))
        let updated = @Lucida(mb.m.coerce<Int64>() <- 5)
        @Assert(updated.m.v == 5)
    }

    // Lens -> iso -> lens: forward and backward through the middle iso.
    @TestCase
    func coerceMiddleChainForward(): Unit {
        let h = WBox(W1(Nested(3)))
        @Assert(@Lucida(h.w.coerce<Nested>().n) == 3)
    }

    @TestCase
    func coerceMiddleChainBackward(): Unit {
        let h = WBox(W1(Nested(3)))
        let updated = @Lucida(h.w.coerce<Nested>().n <- 9)
        @Assert(updated.w.f.n == 9)
    }

    // ===== backward regression pins (library fallback path) =====

    @TestCase
    func mixedLensPrismLensBackward(): Unit {
        let h = PayloadHolder(Rect(Box(42)))
        let updated = @Lucida(h.shape?.Rect.w <- 7)
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
        let updated = @Lucida(h.shape?.Rect.w <- 7)
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
        let updated = @Lucida(w?.Wrap?.Rect.w <- 7)
        var ok = false
        match (updated) {
            case Wrap(inner) => match (inner) {
                case Rect(b) => ok = (b.w == 7)
                case _ => ()
            }
            case _ => ()
        }
        @Assert(ok)
    }

    // Prism->prism->lens backward miss at the inner prism: identity through both.
    @TestCase
    func prismPrismLensBackwardMissIsIdentity(): Unit {
        let w = Wrap2D.Wrap(Dot(3))
        let updated = @Lucida(w?.Wrap?.Rect.w <- 7)
        var ok = false
        match (updated) {
            case Wrap(inner) => match (inner) {
                case Dot(v) => ok = (v == 3)
                case _ => ()
            }
            case _ => ()
        }
        @Assert(ok)
    }

    // Four prisms in one chain (deepest pinned overload): forward, miss, backward.
    @TestCase
    func fourPrismsForwardMatch(): Unit {
        let d = Deep1.V1(Deep2.V2(Deep3.V3(Deep4.V4(42))))
        let fwd = @Lucida(d?.V1?.V2?.V3?.V4)
        var ok = false
        match (fwd) {
            case Right(v) => ok = (v == 42)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func fourPrismsForwardMissCarriesSource(): Unit {
        let d = Deep1.V1(Deep2.V2(Deep3.V3(Deep4.N4(5))))
        let miss = @Lucida(d?.V1?.V2?.V3?.V4)
        var ok = false
        match (miss) {
            case Left(src) => match (src) {
                case V1(inner2) => match (inner2) {
                    case V2(inner3) => match (inner3) {
                        case V3(inner4) => match (inner4) {
                            case N4(v) => ok = (v == 5)
                            case _ => ()
                        }
                        case _ => ()
                    }
                    case _ => ()
                }
                case _ => ()
            }
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func fourPrismsBackward(): Unit {
        let d = Deep1.V1(Deep2.V2(Deep3.V3(Deep4.V4(42))))
        let updated = @Lucida(d?.V1?.V2?.V3?.V4 <- 9)
        var ok = false
        match (updated) {
            case V1(i2) => match (i2) {
                case V2(i3) => match (i3) {
                    case V3(i4) => match (i4) {
                        case V4(v) => ok = (v == 9)
                        case _ => ()
                    }
                    case _ => ()
                }
                case _ => ()
            }
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func fourPrismsBackwardMissIsIdentity(): Unit {
        let d = Deep1.V1(Deep2.V2(Deep3.V3(Deep4.N4(5))))
        let updated = @Lucida(d?.V1?.V2?.V3?.V4 <- 9)
        var ok = false
        match (updated) {
            case V1(i2) => match (i2) {
                case V2(i3) => match (i3) {
                    case V3(i4) => match (i4) {
                        case N4(v) => ok = (v == 5)
                        case _ => ()
                    }
                    case _ => ()
                }
                case _ => ()
            }
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func prismBackwardMissIsIdentity(): Unit {
        let h = ShapeHolder(Square(99))
        let updated = @Lucida(h.shape?.Circle <- 42)
        // Original source type preserved; non-match => identity
        match (updated.shape) {
            case Square(v) => @Assert(v == 99)
            case _ => @Assert(false)
        }
    }
}

@Test
class FusedLensLaws {
    @TestCase
    func deepLensChainForward(): Unit {
        let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
        @Assert(@Lucida(o.customer.address.city.name) == "Atlanta")
        @Assert(@Lucida(o.customer.address.city.zip) == 30301)
    }

    @TestCase
    func deepLensChainBackwardImmutable(): Unit {
        let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
        let updated = @Lucida(o.customer.address.city.name <- "Denver")
        @Assert(updated.customer.address.city.name == "Denver")
        @Assert(o.customer.address.city.name == "Atlanta")
        @Assert(updated.id == 1)
    }

    @TestCase
    func deepLensChainRoundTrip(): Unit {
        let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
        let z = @Lucida(o.customer.address.city.zip)
        let rewritten = @Lucida(o.customer.address.city.zip <- z)
        @Assert(rewritten.customer.address.city.zip == o.customer.address.city.zip)
    }

    @TestCase
    func unfusedForward(): Unit {
        let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
        @Assert(@Lucida[unfuse](o.customer.address.city.name) == "Atlanta")
    }

    @TestCase
    func unfusedBackward(): Unit {
        let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
        let updated = @Lucida[unfuse](o.customer.address.city.name <- "Denver")
        @Assert(updated.customer.address.city.name == "Denver")
        @Assert(o.customer.address.city.name == "Atlanta")
        @Assert(updated.id == 1)
    }
}
