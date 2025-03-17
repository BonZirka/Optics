package optics_experiments.bench.laarhoven.general

import std.deriving.*

import std.unittest.*
import std.unittest.testmacro.*

public var test: Option<A> = None;
public let bow = A(B("Brave", "Old"), "World")

@Derive[ToString]
public struct A {
    public A(
        public var x: B,
        public var y: String
    ) {}
}

@Derive[ToString]
public struct B {
    public B(
        public var x: String,
        public var y: String
    ) {}
}

public struct AOpticality {
    @Frozen
    public func __lens_x_view(source: A) { source.x }
    @Frozen
    public func __lens_x_update(source: A, focus: B) { A(focus, source.y) }
    @Frozen
    public func __lens_y_view(source: A) { source.y }
    @Frozen
    public func __lens_y_update(source: A, focus: String) { A(source.x, focus) }
}

public struct BOpticality {
    @Frozen
    public func __lens_x_view(source: B) { source.x }
    @Frozen
    public func __lens_x_update(source: B, focus: String) { B(focus, source.y) }
    @Frozen
    public func __lens_y_view(source: B) { source.y }
    @Frozen
    public func __lens_y_update(source: B, focus: String) { B(source.x, focus) }
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
        let lensA = createLensWriter(AOpticality().__lens_x_view, AOpticality().__lens_x_update)
        let lensB = createLensWriter(BOpticality().__lens_y_view, BOpticality().__lens_y_update)
        let composition = composeFunc(lensB, lensA)
        let bnw = update(composition, bow, "New")
        test = bnw
    }

    @Bench
    func reconstruction(): Unit {
        let bnw = A(B(bow.x.x, "New"), bow.y)
        test = bnw
    }

    @AfterEach
    func aa(): Unit {
        println(test)
    }
}