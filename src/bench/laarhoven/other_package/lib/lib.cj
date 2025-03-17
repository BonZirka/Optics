package optics_experiments.bench.laarhoven.other_package.lib

@Frozen
public func composeFunc<A, B, C>(f: (A) -> B, g: (B) -> C): (A) -> C {
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
public func createLensReader<S, A>(get: (S) -> A, set: (S, A) -> S): ((A) -> Const<A, A>) -> ((S) -> Const<A, S>) {
    { ret: (A) -> Const<A, A> => { s: S =>
        fmap({ a: A => set(s, a)},
            ret(get(s))
        )} 
    }
}

@Frozen
public func createLensWriter<S, A>(get: (S) -> A, set: (S, A) -> S): ((A) -> Identity<A>) -> ((S) -> Identity<S>) {
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