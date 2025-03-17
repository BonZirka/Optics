package optics_experiments.bench.laarhoven.depth

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

@Frozen
func composeFunc<A, B, C>(f: (A) -> B, g: (B) -> C): (A) -> C {
    { a: A => g(f(a)) }
}

// interface Functor<T> { }

public struct Const<T, X> /* <: Functor<X> */ {
    @Frozen
    public Const(
        public let value: T
    ) {}
}

public struct Identity<T> /* <: Functor<T> */ {
    @Frozen
    public Identity(
        public let value: T
    ) {}
}

@Frozen
private func fmap<X, Y, A>(_: (X) -> Y, a: Const<A, X>): Const<A, Y> {
    Const(a.value)
}

@Frozen
private func fmap<A, B>(f: (A) -> B, a: Identity<A>): Identity<B> {
    Identity(f(a.value))
}

@Frozen
func createLensReader<S, A>(get: (S) -> A, set: (S, A) -> S): ((A) -> Const<A, A>) -> ((S) -> Const<A, S>) {
    { ret: (A) -> Const<A, A> => { s: S =>
        fmap({ a: A => set(s, a)},
            ret(get(s))
        )} 
    }
}

@Frozen
func createLensWriter<S, A>(get: (S) -> A, set: (S, A) -> S): ((A) -> Identity<A>) -> ((S) -> Identity<S>) {
    { ret: (A) -> Identity<A> => { s: S =>
        fmap({ a: A => set(s, a)},
            ret(get(s))
        )} 
    }
}

@Frozen
public func view<S, A>(
    l: ((A) -> Const<A, A>) -> ((S) -> Const<A, S>),
    s: S
): A { l({ a: A => Const(a)})(s).value }

@Frozen
public func update<S, A>(
    l: ((A) -> Identity<A>) -> ((S) -> Identity<S>),
    s: S,
    a: A
): S { l({ _: A => Identity(a)})(s).value }

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
        let lensA = createLensWriter(AOpticality().__lens_x_view, AOpticality().__lens_x_update)
        let lensB = createLensWriter(BOpticality().__lens_x_view, BOpticality().__lens_x_update)
        let lensC = createLensWriter(COpticality().__lens_x_view, COpticality().__lens_x_update)
        let lensD = createLensWriter(DOpticality().__lens_x_view, DOpticality().__lens_x_update)
        let lensE = createLensWriter(EOpticality().__lens_y_view, EOpticality().__lens_y_update)
        let composition = composeFunc(lensE, composeFunc(lensD, composeFunc(lensC, composeFunc(lensB, lensA))))
        let bnw = update(composition, bow, "New")
        test = bnw
    }

    @Bench
    func reconstruction(): Unit {
        let bnw = A(B(C(D(E(bow.x.x.x.x.x, "New"), bow.x.x.x.y), bow.x.x.y), bow.x.y), bow.y)
        test = bnw
    }

    @AfterEach
    func aa(): Unit {
        let _ = test
    }
}