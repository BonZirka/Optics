package optics_experiments.bench.inlining.depth

import std.unittest.*
import std.unittest.testmacro.*

public var test: Option<A> = None;
public let bow = A(B(C(D(E("Brave", "Old"), "World"), "World"), "World"), "World")

public struct A {
    public A(
        public var x: B,
        public var y: String
    ) {}
}

public struct B {
    public B(
        public var x: C,
        public var y: String
    ) {}
}

public struct C {
    public C(
        public var x: D,
        public var y: String
    ) {}
}

public struct D {
    public D(
        public var x: E,
        public var y: String
    ) {}
}

public struct E {
    public E(
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
    @Frozen
    public func __lens_x_view(source: A) { source.x }
    @Frozen
    public func __lens_x_update(source: A, focus: B) { A(focus, source.y) }
    @Frozen
    public func __lens_y_view(source: A) { source.y }
    @Frozen
    public func __lens_y_update(source: A, focus: String) { A(source.x, focus) }
}

struct BOpticality {
    @Frozen
    public func __lens_x_view(source: B) { source.x }
    @Frozen
    public func __lens_x_update(source: B, focus: C) { B(focus, source.y) }
    @Frozen
    public func __lens_y_view(source: B) { source.y }
    @Frozen
    public func __lens_y_update(source: B, focus: String) { B(source.x, focus) }
}

struct COpticality {
    @Frozen
    public func __lens_x_view(source: C) { source.x }
    @Frozen
    public func __lens_x_update(source: C, focus: D) { C(focus, source.y) }
    @Frozen
    public func __lens_y_view(source: C) { source.y }
    @Frozen
    public func __lens_y_update(source: C, focus: String) { C(source.x, focus) }
}

struct DOpticality {
    @Frozen
    public func __lens_x_view(source: D) { source.x }
    @Frozen
    public func __lens_x_update(source: D, focus: E) { D(focus, source.y) }
    @Frozen
    public func __lens_y_view(source: D) { source.y }
    @Frozen
    public func __lens_y_update(source: D, focus: String) { D(source.x, focus) }
}

struct EOpticality {
    @Frozen
    public func __lens_x_view(source: E) { source.x }
    @Frozen
    public func __lens_x_update(source: E, focus: String) { E(focus, source.y) }
    @Frozen
    public func __lens_y_view(source: E) { source.y }
    @Frozen
    public func __lens_y_update(source: E, focus: String) { E(source.x, focus) }
}

@Test
@Configure[baseline: "reconstruction"]
class StructMutBenchmark {

    @Bench
    func nativeBaseline(): Unit {
        var bnw_ = bow
        bnw_.x.x.x.x.y = "New"
        let bnw = bnw_ 
        test = bnw
    }

    @Bench
    func highOrderComposition(): Unit {
        let x0set = AOpticality().__lens_x_update
        let x0get = AOpticality().__lens_x_view

        let x1set = highOrderComposeLensesSetter(
            x0get,
            x0set,
            BOpticality().__lens_x_update
        )
        let x1get = highOrderComposeLensesGetter(
            x0get,
            BOpticality().__lens_x_view
        )

        let x2set = highOrderComposeLensesSetter(
            x1get,
            x1set,
            COpticality().__lens_x_update
        )
        let x2get = highOrderComposeLensesGetter(
            x1get,
            COpticality().__lens_x_view
        )
        let x3set = highOrderComposeLensesSetter(
            x2get,
            x2set,
            DOpticality().__lens_x_update
        )
        let x3get = highOrderComposeLensesGetter(
            x2get,
            DOpticality().__lens_x_view
        )

        let bnw = highOrderComposeLensesSetter(
            x3get,
            x3set,
            EOpticality().__lens_y_update
        )(bow, "New")
        test = bnw
    }

    @Bench
    func reconstruction(): Unit {
        let bnw = A(B(C(D(E(bow.x.x.x.x.x, "New"), bow.x.x.x.y), bow.x.x.y), bow.x.y), bow.y)
        test = bnw
    }

    @AfterAll
    func aa(): Unit {
        let _ = test
    }
}