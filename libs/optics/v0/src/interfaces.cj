package lucida

public enum Either<S, A> {
    | Left(S)
    | Right(A)
}

sealed interface Optional<S, A> {
    @Frozen
    prop preview: (S) -> Either<S, A>
    @Frozen
    prop update: (S, A) -> S
}

sealed interface Lens<S, A> <: Optional<S, A> {
    @Frozen
    prop view: (S) -> A
    @Frozen
    prop update: (S, A) -> S
    @Frozen
    prop preview: (S) -> Either<S, A> {
        get() {
            { source: S => Right(view(source))}
        }
    }
}

sealed interface Prism<S, A> <: Optional<S, A> {
    @Frozen
    prop preview: (S) -> Either<S, A>
    @Frozen
    prop build: (A) -> S
    @Frozen
    prop update: (S, A) -> S {
        // TODO(k84372247): It might be wrong...
        get() {
            { _: S, focus: A => build(focus) }
        }
    }
}

@Frozen
public func identityLens<T>(_: T): Lens<T, T> {
    createLens({ source: T => source}, {_: T, focus: T => focus})
}

@Frozen
public func compose<S, A, B>(l1: Lens<S, A>, l2: Lens<A, B>): Lens<S, B> {
    ValueLens(
        { source: S => l2.view(l1.view(source)) },
        { source: S, focus: B => l1.update(source, l2.update(l1.view(source), focus)) },
    )
}

@Frozen
public func compose<S, A, B>(p1: Prism<S, A>, p2: Prism<A, B>): Prism<S, B> {
    ValuePrism(
        { source: S => 
            if (let Right(prv1) <- p1.preview(source) && let Right(res) <- p2.preview(prv1)) {
                Right(res)
            } else {
                Left(source)
            }
        },
        { focus: B => p1.build(p2.build(focus)) },
    )
}

@Frozen
public func compose<S, A, B>(p1: Optional<S, A>, p2: Optional<A, B>): Optional<S, B> {
    ValueOptional(
        { source: S => 
            if (let Right(prv1) <- p1.preview(source) && let Right(res) <- p2.preview(prv1)) {
                Right(res)
            } else {
                Left(source)
            }
        },
        { source: S, focus: B =>  
            if (let Right(v1) <- p1.preview(source) && let Right(_) <- p2.preview(v1)) {
                p1.update(source, p2.update(v1, focus))
            } else {
                source
            }
        },
    )
}

@Frozen
public func createLens<S, A>(view: (S) -> A, update: (S, A) -> S): Lens<S, A> {
    ValueLens(
        view,
        update
    )
}

@Frozen
public func createPrism<S, A>(preview: (S) -> Either<S, A>, build: (A) -> S): Prism<S, A> {
    ValuePrism(
        preview,
        build
    )
}

@Frozen
public func createOptional<S, A>(preview: (S) -> Either<S, A>, update: (S, A) -> S): Optional<S, A> {
    ValueOptional(
        preview,
        update
    )
}

private struct ValueLens<S, A> <: Lens<S, A> {

    @Frozen
    ValueLens(
        private let _view: (S) -> A,
        private let _update: (S, A) -> S
    ) {}

    @Frozen
    public prop view: (S) -> A {
        get() {
            _view
        }
    }

    @Frozen
    public prop update: (S, A) -> S {
        get() {
           _update 
        }
    }

}


private struct ValuePrism<S, A> <: Prism<S, A> {
    @Frozen
    ValuePrism(
        private let _preview: (S) -> Either<S, A>,
        private let _build: (A) -> S
    ) {}

    @Frozen
    public prop preview: (S) -> Either<S, A> {
        get() {
            _preview
        }
    }
    @Frozen
    public prop build: (A) -> S {
        get() {
           _build 
        }
    }
}


private struct ValueOptional<S, A> <: Optional<S, A> {
    @Frozen
    ValueOptional(
        private let _preview: (S) -> Either<S, A>,
        private let _update: (S, A) -> S
    ) {}

    @Frozen
    public prop preview: (S) -> Either<S, A> {
        get() {
            _preview
        }
    }

    @Frozen
    public prop update: (S, A) -> S {
        get() {
           _update
        }
    }
}