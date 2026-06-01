package optics_experiments.bench.wut

import std.unittest.*
import std.unittest.testmacro.*

import std.deriving.*

import lucida_macro.*
import lucida.*
// import lucida.stdlib.*

@Derive[ToString]
@DeriveOptics
public struct A {
    A(
        public let x: String
    ) { }
}

public let x = A("Hello")
@Test
@Configure[baseline: "nativeBaseline"]
class StructMutBenchmark {
    @Bench
    func nativeBaseline(): Unit {
        let firstClass = @Lucida(@TypeOf(x).x <- "Bye")
        let setter = @Lucida(@Optic(firstClass) <- "Bye")
        let evaled = @Lucida(x.@Optic(setter))
        println("")
    }
}
