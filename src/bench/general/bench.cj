package optics_experiments.bench.general

import std.deriving.*

import std.unittest.*
import std.unittest.testmacro.*

import lucida.*
import lucida_macro.*

@Derive[ToString]
@DeriveOptics
public struct A {
    public A(
        public var x: B,
        public var y: String
    ) { }
}

@Derive[ToString]
@DeriveOptics
public struct B {
    public B(
        public var x: String,
        public var y: String
    ) { }
}

public var test: Option<A> = None;
public let bow = A(B("Brave", "Old"), "World")

@Test
@Configure[baseline: "nativeBaseline"]
class StructMutBenchmark {

    @Bench
    func nativeBaseline(): Unit {
        var bnw_ = bow
        bnw_.x.y = "New"
        let bnw = bnw_ 
        test = bnw
    }

    @Bench
    func opticsBaseline(): Unit {
        let bnw = @Lucida(bow.x.y <- "New")
        test = bnw
    }

    @Bench
    func unfusedOptics(): Unit {
        let bnw = @Lucida[unfuse](bow.x.y <- "New")
        test = bnw
    }

    @Bench
    func reconstruction(): Unit {
        let bnw = A(B(bow.x.x, "New"), bow.y)
        test = bnw
    }

    @AfterAll
    func aa(): Unit {
        let _ = test
    }
}
