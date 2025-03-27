package lucida

@Frozen
public func highOrderComposeLensesSetter<S, A, B>(v1: (S) -> A, u1: (S, A) -> S, u2: (A, B) -> A): (S, B) -> S {
    { source: S, focus: B => u1(source, u2(v1(source), focus)) }
}

@Frozen
public func highOrderComposeLensesGetter<S, A, B>(v1: (S) -> A, v2: (A) -> B): (S) -> B {
    { source: S => v2(v1(source)) }
}