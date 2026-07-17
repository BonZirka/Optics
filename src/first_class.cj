package lucida

public enum Either<L, R> {
    | Left(L)
    | Right(R)
}

public struct Iso<S, A> {
    public Iso(
        public let to: (S) -> A,
        public let from: (A) -> S 
    ) {}
}

public struct Lens<S, A> {
    public Lens(
        public let view: (S) -> A,
        public let update: (S, A) -> S 
    ) {}
}

public struct Prism<S, A> {
    public Prism(
        public let preview: (S) -> Either<S, A>,
        public let build: (A) -> S 
    ) {}
}

public struct Affine<S, A> {
    public Affine(
        public let preview: (S) -> Either<S, A>,
        public let update: (S, A) -> S 
    ) {}
}

public struct Setter<S, A> {
    public Setter(
        public let modify: (S, (A) -> A) -> S
    ) { }

    public prop modifyId: (S) -> S {
        get() {
            { source: S => modify(source, { x: A => x }) }
        }
    }
}

public struct __FirstClassGetters {
    @Frozen
    public static func forward<S, A>(x: Iso<S, A>): (S) -> A { x.to } 
    @Frozen
    public static func backward<S, A>(x: Iso<S, A>): (A) -> S { x.from } 
    @Frozen
    public static func forward<S, A>(x: Lens<S, A>): (S) -> A { x.view } 
    @Frozen
    public static func backward<S, A>(x: Lens<S, A>): (S, A) -> S { x.update } 
    @Frozen
    public static func forward<S, A>(x: Prism<S, A>): (S) -> Either<S, A> { x.preview } 
    @Frozen
    public static func backward<S, A>(x: Prism<S, A>): (A) -> S { x.build } 
    @Frozen
    public static func forward<S, A>(x: Affine<S, A>): (S) -> Either<S, A> { x.preview } 
    @Frozen
    public static func backward<S, A>(x: Affine<S, A>): (S, A) -> S { x.update } 
    @Frozen
    public static func forward<S, A>(x: Setter<S, A>): (S) -> S { x.modifyId } 
    @Frozen
    public static func backward<S, A>(x: Setter<S, A>): (S, (A) -> A) -> S { x.modify } 
}

public struct __FirstClassConstruction {
    @Frozen
    public static func perform<S, A>(forward: (S) -> A, backward: (A) -> S): Iso<S, A> {
        Iso(forward, backward)
    }

    @Frozen
    public static func perform<S, A>(forward: (S) -> A, backward: (S, A) -> S): Lens<S, A> {
        Lens(forward, backward)
    }

    @Frozen
    public static func perform<S, A>(forward: (S) -> Either<S, A>, backward: (A) -> S): Prism<S, A> {
        Prism(forward, backward)
    }

    @Frozen
    public static func perform<S, A>(forward: (S) -> Either<S, A>, backward: (S, A) -> S): Affine<S, A> {
        Affine(forward, backward)
    }

    @Frozen
    public static func perform<S, A>(_: (S) -> S, backward: (S, (A) -> A) -> S): Setter<S, A> {
        Setter(backward)
    }
}
