package tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.macrodsl.*

@DeriveOptics
public struct GBox<T> {
    public GBox(public let v: T) { }
}

@Test
class GenericDeriveLaws {
    @TestCase
    func gboxLensForwardBackward(): Unit {
        let b = GBox<Int64>(5)
        let got = @f(b.v)
        @Assert(got == 5)
    }

    @TestCase
    func gboxLensSet(): Unit {
        let b = GBox<Int64>(5)
        let updated = @f(b.v <- 7)
        @Assert(updated.v == 7)
        @Assert(b.v == 5)
    }
}
