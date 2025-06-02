package optics_experiments.test

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida_macro.*

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
        if (let Right(r) <- @Lucida(h.shape?.Circle)) {
            ok = r == 7
        }
        @Assert(ok)
    }

    @TestCase
    func prismForwardMiss(): Unit {
        let h = ShapeHolder(Square(99))
        var leftOk = false
        if (let Left(_) <- @Lucida(h.shape?.Circle)) {
            leftOk = true
        }
        @Assert(leftOk)
    }

    @TestCase
    func prismBackwardMatch(): Unit {
        let h = ShapeHolder(Circle(7))
        let updated = @Lucida(h.shape?.Circle, 42)
        var ok = false
        match (updated.shape) {
            case Circle(v) => ok = (v == 42)
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func prismBackwardMissIsIdentity(): Unit {
        let h = ShapeHolder(Square(99))
        let updated = @Lucida(h.shape?.Circle, 42)
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
        let updated = @Lucida(o.customer.address.city.name, "Denver")
        @Assert(updated.customer.address.city.name == "Denver")
        @Assert(o.customer.address.city.name == "Atlanta")
        @Assert(updated.id == 1)
    }

    @TestCase
    func deepLensChainRoundTrip(): Unit {
        let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
        let z = @Lucida(o.customer.address.city.zip)
        let rewritten = @Lucida(o.customer.address.city.zip, z)
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
        let updated = @Lucida[unfuse](o.customer.address.city.name, "Denver")
        @Assert(updated.customer.address.city.name == "Denver")
        @Assert(o.customer.address.city.name == "Atlanta")
        @Assert(updated.id == 1)
    }
}
