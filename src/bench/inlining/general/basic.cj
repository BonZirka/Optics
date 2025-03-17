package optics_experiments.bench.inlining.general

import std.unittest.*
import std.unittest.testmacro.*

public var test: Option<A> = None;
public let bow = A(B("Brave", "Old"), "World")

public struct A {
    public A(
        public var x: B,
        public var y: String
    ) {}
}

public struct B {
    public B(
        public var x: String,
        public var y: String
    ) {}
}

public func highOrderComposeLensesSetter<S, A, B>(v1: (S) -> A, u1: (S, A) -> S, u2: (A, B) -> A): (S, B) -> S {
    { source: S, focus: B => u1(source, u2(v1(source), focus)) }
}

public func highOrderComposeLensesGetter<S, A, B>(v1: (S) -> A, v2: (A) -> B): (S) -> B {
    { source: S => v2(v1(source)) }
}

struct AOpticality {
    public let __lens_x_view = { source: A => source.x }
    public let __lens_x_update = { source: A, focus: B => A(focus, source.y) }
    public let __lens_y_view = { source: A => source.y }
    public let __lens_y_update = { source: A, focus: String => A(source.x, focus) }
}

struct BOpticality {
    public let __lens_x_view = { source: B => source.x }
    public let __lens_x_update = { source: B, focus: String => B(focus, source.y) }
    public let __lens_y_view = { source: B => source.y }
    public let __lens_y_update = { source: B, focus: String => B(source.x, focus) }
}

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
    func highOrderComposition(): Unit {
        let bnw = highOrderComposeLensesSetter(AOpticality().__lens_x_view, AOpticality().__lens_x_update, BOpticality().__lens_y_update)(bow, "New")
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