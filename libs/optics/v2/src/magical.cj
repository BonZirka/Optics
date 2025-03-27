package lucida

public struct Magical<T>   {}

public struct Lenses<T>    {}
public struct Prisms<T>    {}
public struct Optionals<T> {}

public enum Either<L, R> {
    | Left(L)
    | Right(R)
}

@Frozen
public func magic<T>(_: T): Magical<T> {
    Magical()
}

@Frozen
public func composeForward<S, A, B>(_: Lenses<S>, _: Lenses<A>, _: Magical<B>) {
    { l1view: (S) -> A, l2view: (A) -> B, _: (S, A) -> S, _: (A, B) -> A =>
        { source: S => l2view(l1view(source)) }
    }
}

@Frozen
public func composeBackward<S, A, B>(_: Lenses<S>, _: Lenses<A>, _: Magical<B>) {
    { l1view: (S) -> A, _: (A) -> B, l1update: (S, A) -> S, l2update: (A, B) -> A =>
        { source: S, focus: B => l1update(source, l2update(l1view(source), focus)) }
    }
}

@Frozen
public func composeForward<S, A, B>(_: Prisms<S>, _: Prisms<A>, _: Magical<B>) {
    {p1preview: (S) -> Either<S, A>, p2preview: (A) -> Either<A, B>, _: Any, _: Any =>
        { source: S => 
            if (let Right(prv1) <- p1preview(source) && let Right(res) <- p2preview(prv1)) {
                Right<S, B>(res)
            } else {
                Left<S, B>(source)
            }
        }
    }
}

@Frozen
public func composeBackward<S, A, B>(_: Prisms<S>, _: Prisms<A>, _: Magical<B>) {
    { _: Any, _: Any, p1build: (A) -> S, p2build: (B) -> A =>
        { focus: B => p1build(p2build(focus)) }
    }
}

@Frozen
public func composeForward<S, A, B>(_: Optionals<S>, _: Optionals<A>, _: Magical<B>) {
    { p1preview: (S) -> Either<S, A>, p2preview: (A) -> Either<A, B>, _: Any, _: Any =>
        { source: S => 
            if (let Right(prv1) <- p1preview(source) && let Right(res) <- p2preview(prv1)) {
                Right<S, B>(res)
            } else {
                Left<S, B>(source)
            }
        }
    }
}

@Frozen
public func composeBackward<S, A, B>(_: Optionals<S>, _: Optionals<A>, _: Magical<B>) {
    { p1preview: (S) -> Either<S, A>, p2preview: (A) -> Either<A, B>, p1update: (S, A) -> S, p2update: (A, B) -> A =>
        { source: S, focus: B =>  
            if (let Right(v1) <- p1preview(source) && let Right(_) <- p2preview(v1)) {
                p1update(source, p2update(v1, focus))
            } else {
                source
            }
        }
    }
}

@Frozen
public func composeForward<S, A, B>(_: Prisms<S>, _: Lenses<A>, _: Magical<B>) {
    { p1preview: (S) -> Either<S, A>, l2view: (A) -> B, _: Any, _: Any =>
        { source: S => 
            if (let Right(prv1) <- p1preview(source)) {
                Right<S, B>(l2view(prv1))
            } else {
                Left<S, B>(source)
            }
        }
    }
}
@Frozen
public func composeForward<S, A, B>(_: Lenses<S>, _: Prisms<A>, _: Magical<B>) {
    { l1view: (S) -> A, p2preview: (A) -> Either<A, B>, _: Any, _: Any =>
        { source: S => 
            if (let Right(prv2) <- p2preview(l1view(source))) {
                Right<S, B>(prv2)
            } else {
                Left<S, B>(source)
            }
        }
    }
}

@Frozen
public func composeForward<S, A, B>(_: Lenses<S>, _: Optionals<A>, _: Magical<B>) {
    composeForward<S, A, B>(Lenses<S>(), Prisms<A>(), Magical<B>())
}
@Frozen
public func composeForward<S, A, B>(_: Prisms<S>, _: Optionals<A>, _: Magical<B>) {
    composeForward<S, A, B>(Prisms<S>(), Prisms<A>(), Magical<B>())
}
@Frozen
public func composeForward<S, A, B>(_: Optionals<S>, _: Lenses<A>, _: Magical<B>) {
    composeForward<S, A, B>(Prisms<S>(), Lenses<A>(), Magical<B>())
}
@Frozen
public func composeForward<S, A, B>(_: Optionals<S>, _: Prisms<A>, _: Magical<B>) {
    composeForward<S, A, B>(Prisms<S>(), Prisms<A>(), Magical<B>())
}


@Frozen
public func composeBackward<S, A, B>(_: Prisms<S>, _: Lenses<A>, _: Magical<B>) {
    { p1preview: (S) -> Either<S, A>, l2view: (A) -> B, p1build: (A) -> S, l2update: (A, B) -> A =>
        { source: S, focus: B =>  
            if (let Right(v1) <- p1preview(source)) {
                p1build(l2update(v1, focus))
            } else {
                source
            }
        }
    }
}
@Frozen
public func composeBackward<S, A, B>(_: Lenses<S>, _: Prisms<A>, _: Magical<B>) {
    { l1view: (S) -> A, p2preview: (A) -> Either<A, B>, l1update: (S, A) -> S, p2build: (B) -> A =>
        { source: S, focus: B =>  
            if (let Right(_) <- p2preview(l1view(source))) {
                l1update(source, p2build(focus))
            } else {
                source
            }
        }
    }
}
@Frozen
public func composeBackward<S, A, B>(_: Lenses<S>, _: Optionals<A>, _: Magical<B>) {
    { l1view: (S) -> A, o2preview: (A) -> Either<A, B>, l1update: (S, A) -> S, o2update: (A, B) -> A =>
        { source: S, focus: B =>  
            let t = l1view(source)
            if (let Right(_) <- o2preview(t)) {
                l1update(source, o2update(t, focus))
            } else {
                source
            }
        }
    }
}
@Frozen
public func composeBackward<S, A, B>(_: Prisms<S>, _: Optionals<A>, _: Magical<B>) {
    { p1preview: (S) -> Either<S, A>, o2preview: (A) -> Either<A, B>, p1build: (A) -> S, o2update: (A, B) -> A =>
        { source: S, focus: B =>  
            if (let Right(v1) <- p1preview(source) && let Right(_) <- o2preview(v1)) {
                p1build(o2update(v1, focus))
            } else {
                source
            }
        }
    }
}
@Frozen
public func composeBackward<S, A, B>(_: Optionals<S>, _: Lenses<A>, _: Magical<B>) {
    { o1preview: (S) -> Either<S, A>, _: (A) -> B, o1update: (S, A) -> S, l2update: (A, B) -> A =>
        { source: S, focus: B =>  
            if (let Right(v1) <- o1preview(source)) {
                o1update(source, l2update(v1, focus))
            } else {
                source
            }
        }
    }
}
@Frozen
public func composeBackward<S, A, B>(_: Optionals<S>, _: Prisms<A>, _: Magical<B>) {
    { o1preview: (S) -> Either<S, A>, p2preview: (A) -> Either<A, B>, o1update: (S, A) -> S, p2build:  (B) -> A =>
        { source: S, focus: B =>  
            if (let Right(v1) <- o1preview(source) && let Right(_) <- p2preview(v1)) {
                o1update(source, p2build(focus))
            } else {
                source
            }
        }
    }
}

@Frozen
public func whatExpect<S, A, B>(_: Lenses<S>,    _: Lenses<A>,    _: Magical<B>): Lenses<S>    { Lenses() }
@Frozen
public func whatExpect<S, A, B>(_: Prisms<S>,    _: Prisms<A>,    _: Magical<B>): Prisms<S>    { Prisms() }
@Frozen
public func whatExpect<S, A, B>(_: Optionals<S>, _: Optionals<A>, _: Magical<B>): Optionals<S> { Optionals() }
@Frozen
public func whatExpect<S, A, B>(_: Lenses<S>,    _: Prisms<A>,    _: Magical<B>): Optionals<S> { Optionals() }
@Frozen
public func whatExpect<S, A, B>(_: Prisms<S>,    _: Lenses<A>,    _: Magical<B>): Optionals<S> { Optionals() }
@Frozen
public func whatExpect<S, A, B>(_: Lenses<S>,    _: Optionals<A>, _: Magical<B>): Optionals<S> { Optionals() }
@Frozen
public func whatExpect<S, A, B>(_: Prisms<S>,    _: Optionals<A>, _: Magical<B>): Optionals<S> { Optionals() }
@Frozen
public func whatExpect<S, A, B>(_: Optionals<S>, _: Lenses<A>,    _: Magical<B>): Optionals<S> { Optionals() }
@Frozen
public func whatExpect<S, A, B>(_: Optionals<S>, _: Prisms<A>,    _: Magical<B>): Optionals<S> { Optionals() }

// Testing idea