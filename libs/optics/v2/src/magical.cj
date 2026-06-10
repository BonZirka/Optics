package lucida

public struct RegistryMagical<T> { }

public func __downcast_method_coerce<T, G>(_: RegistryMagical<T>, _: RegistryMagical<G>): RegistryIsos<T> {
    RegistryIsos()
}

public struct RegistryIsos<T>      {} // (a) -> b, (b) -> a
public struct RegistryLenses<T>    {} // (a) -> b, (a, b) -> a
public struct RegistryPrisms<T>    {} // (a) -> Either a b, (b) -> a
public struct RegistryAffines<T>   {} // (a) -> Either a b, (a, b) -> a
public struct RegistrySetters<T>   {} // (a) -> a, (a, (b) -> b) -> a

@Frozen
public func magic<T>(_: () -> T): RegistryMagical<T> {
    RegistryMagical()
}

@Frozen
public func magic<T>(): RegistryMagical<T> {
    RegistryMagical()
}

@Frozen
public func evalBackward<S, A>(optic: (A) -> S, _: S, target: A): S {
    optic(target)
}
@Frozen
public func evalBackward<S, A>(optic: (S, A) -> S, source: S, target: A): S {
    optic(source, target)
}

@Frozen
public func finalizingSetterForward<S, A>(optic: (A) -> S, target: A): (S) -> S {
    { source: S => optic(target) }
}

@Frozen
public func finalizingSetterForward<S, A>(optic: (S, A) -> S, target: A): (S) -> S {
    { source: S => optic(source, target) }
}

@Frozen
public func finalizingSetterForward<S, A>(optic: (S, (A) -> A) -> S, target: A): (S) -> S {
    { source: S => optic(source, { x: A => target }) }
}

@Frozen
public func finalizingSetterBackward<S, A>(optic: (A) -> S, target: A): (S, (A) -> A) -> S {
    { source: S, modifier: (A) -> A => optic(modifier(target)) }
}

@Frozen
public func finalizingSetterBackward<S, A>(optic: (S, A) -> S, target: A): (S, (A) -> A) -> S {
    { source: S, modifier: (A) -> A => optic(source, modifier(target)) }
}

@Frozen
public func finalizingSetterBackward<S, A>(optic: (S, (A) -> A) -> S, target: A): (S, (A) -> A) -> S {
    { source: S, modifier: (A) -> A => optic(source, { x: A => modifier(target) }) }
}

@Frozen
public func magicFirstClassDowncast<S, A>(_: Lens<S, A>): RegistryLenses<S> { RegistryLenses<S>() }
@Frozen
public func magicFirstClassDowncast<S, A>(_: Prism<S, A>): RegistryPrisms<S> { RegistryPrisms<S>() }
@Frozen
public func magicFirstClassDowncast<S, A>(_: Iso<S, A>): RegistryIsos<S> { RegistryIsos<S>() }
@Frozen
public func magicFirstClassDowncast<S, A>(_: Affine<S, A>): RegistryAffines<S> { RegistryAffines<S>() }
@Frozen
public func magicFirstClassDowncast<S, A>(_: Setter<S, A>): RegistrySetters<S> { RegistrySetters<S>() }

@Frozen
public func magicFirstClass<S, A>(_: Lens<S, A>): RegistryMagical<A> { RegistryMagical<A>() }
@Frozen
public func magicFirstClass<S, A>(_: Prism<S, A>): RegistryMagical<A> { RegistryMagical<A>() }
@Frozen
public func magicFirstClass<S, A>(_: Iso<S, A>): RegistryMagical<A> { RegistryMagical<A>() }
@Frozen
public func magicFirstClass<S, A>(_: Affine<S, A>): RegistryMagical<A> { RegistryMagical<A>() }
@Frozen
public func magicFirstClass<S, A>(_: Setter<S, A>): RegistryMagical<A> { RegistryMagical<A>() }

// ===== Fusion type-pinning helpers =====
// Cangjie cannot infer lambda parameter types from the lambda body alone.
// The macro passes a source-providing thunk () -> S whose return type pins S,
// allowing the walk lambda (S) -> R / (S, R) -> S to be typed without an IIFE.

@Frozen
public func pinForward<S, R>(sourceThunk: () -> S, walk: (S) -> R): (S) -> R {
    { s: S => walk(s) }
}

@Frozen
public func pinBackward<S, R>(sourceThunk: () -> S, targetThunk: () -> R, walk: (S, R) -> S): (S, R) -> S {
    { s: S, r: R => walk(s, r) }
}

@Frozen
public func pinBackwardSourceless<S, R>(targetThunk: () -> R, walk: (R) -> S): (R) -> S {
    { r: R => walk(r) }
}

/// Erases backward arity for kind-exact user optics: the fused backward fold
/// always calls this two-argument form; the overload set dispatches on the
/// bound backward's function type (sourceful (S, A) -> S vs sourceless (A) -> S).
public func __bwdApply<S, A>(backward: (S, A) -> S, src: S, focus: A): S {
    backward(src, focus)
}

public func __bwdApply<S, A>(backward: (A) -> S, src: S, focus: A): S {
    backward(focus)
}

/// Total-expectation backward apply for user optics: the macro passes the
/// segment's optics registry as a pure phantom. Sourceful kinds (Lens/Affine)
/// and total sourceless kinds (Iso) have matching overloads; a '.'-marked
/// PRISM write has none — unconditional rebuild on miss is exactly the
/// semantics '.' must not grant a partial optic, so it fails to compile.
public func __bwdApplyTotal<T, S, A>(_: RegistryLenses<T>, backward: (S, A) -> S, src: S, focus: A): S {
    backward(src, focus)
}

public func __bwdApplyTotal<T, S, A>(_: RegistryAffines<T>, backward: (S, A) -> S, src: S, focus: A): S {
    backward(src, focus)
}

public func __bwdApplyTotal<T, S, A>(_: RegistryIsos<T>, backward: (A) -> S, src: S, focus: A): S {
    backward(focus)
}

@Deprecated[message: "@Lucida: '.'-write through a prism — '.'-writes assert a match and would rebuild the source unconditionally on miss. Use '?.' to preserve the source on miss.", strict: true]
public func __bwdApplyTotal<T, S, A>(_: RegistryPrisms<T>, backward: (A) -> S, src: S, focus: A): S {
    backward(focus)
}

// ===== Per-segment forward gates =====
// The macro wraps EVERY segment's forward binding with one of these, so the
// operator mark is checked against the segment's kind registry right at the
// binding site — mid-chain or tail, derived, user, or stdlib. Total-marked
// ('.') segments pass through Lenses/Isos; a Prisms/Affines registry means
// the mark contradicts a partial kind. Partial-marked ('?.') segments pass
// through Prisms/Affines (Either forward); a Lenses/Isos registry means the
// mark contradicts a total kind. Bodies are identities: the gates exist for
// overload resolution, and inlining makes them free at runtime.
public func __fwdApplyTotal<T, S, A>(_: RegistryLenses<T>, forward: (S) -> A): (S) -> A {
    forward
}

public func __fwdApplyTotal<T, S, A>(_: RegistryIsos<T>, forward: (S) -> A): (S) -> A {
    forward
}

@Deprecated[message: "@Lucida: '.' on a partial optic (Prism/Affine) — its forward returns Either, so a total read is impossible. Use '?.' and match Right/Left.", strict: true]
public func __fwdApplyTotal<T, S, A>(_: RegistryPrisms<T>, forward: (S) -> Either<S, A>): (S) -> Either<S, A> {
    forward
}

@Deprecated[message: "@Lucida: '.' on a partial optic (Prism/Affine) — its forward returns Either, so a total read is impossible. Use '?.' and match Right/Left.", strict: true]
public func __fwdApplyTotal<T, S, A>(_: RegistryAffines<T>, forward: (S) -> Either<S, A>): (S) -> Either<S, A> {
    forward
}

public func __fwdApplyPartial<T, S, A>(_: RegistryPrisms<T>, forward: (S) -> Either<S, A>): (S) -> Either<S, A> {
    forward
}

public func __fwdApplyPartial<T, S, A>(_: RegistryAffines<T>, forward: (S) -> Either<S, A>): (S) -> Either<S, A> {
    forward
}

@Deprecated[message: "@Lucida: '?.' on a total optic (Lens/Iso) — its forward cannot miss, so there is no Either to unwrap. Use '.' for a plain read.", strict: true]
public func __fwdApplyPartial<T, S, A>(_: RegistryLenses<T>, forward: (S) -> A): (S) -> A {
    forward
}

@Deprecated[message: "@Lucida: '?.' on a total optic (Lens/Iso) — its forward cannot miss, so there is no Either to unwrap. Use '.' for a plain read.", strict: true]
public func __fwdApplyPartial<T, S, A>(_: RegistryIsos<T>, forward: (S) -> A): (S) -> A {
    forward
}

// ===== Fused prism-chain forward =====
// The macro emits only top-level sibling lambdas (segment runs); every lambda's
// parameter and return type is pinned by the concrete pre-bound segment forward
// arguments, never by another lambda's body. Semantics mirror the library's
// composed forward: any prism miss short-circuits to Left(original source),
// a full match yields Right(final focus).

@Frozen
public func pinPrismForward1<S, T1, A1, B>(
    sourceThunk: () -> S,
    fwd1: (T1) -> Either<T1, A1>,
    run0: (S) -> T1,
    cont1: (A1) -> B
): (S) -> Either<S, B> {
    { s: S =>
        match (fwd1(run0(s))) {
            case Right(a1) => Right<S, B>(cont1(a1))
            case Left(_) => Left<S, B>(s)
        }
    }
}

@Frozen
public func pinPrismForward2<S, T1, A1, T2, A2, B>(
    sourceThunk: () -> S,
    fwd1: (T1) -> Either<T1, A1>,
    fwd2: (T2) -> Either<T2, A2>,
    run0: (S) -> T1,
    run1: (A1) -> T2,
    cont2: (A2) -> B
): (S) -> Either<S, B> {
    { s: S =>
        match (fwd1(run0(s))) {
            case Right(a1) =>
                match (fwd2(run1(a1))) {
                    case Right(a2) => Right<S, B>(cont2(a2))
                    case Left(_) => Left<S, B>(s)
                }
            case Left(_) => Left<S, B>(s)
        }
    }
}

@Frozen
public func pinPrismForward3<S, T1, A1, T2, A2, T3, A3, B>(
    sourceThunk: () -> S,
    fwd1: (T1) -> Either<T1, A1>,
    fwd2: (T2) -> Either<T2, A2>,
    fwd3: (T3) -> Either<T3, A3>,
    run0: (S) -> T1,
    run1: (A1) -> T2,
    run2: (A2) -> T3,
    cont3: (A3) -> B
): (S) -> Either<S, B> {
    { s: S =>
        match (fwd1(run0(s))) {
            case Right(a1) =>
                match (fwd2(run1(a1))) {
                    case Right(a2) =>
                        match (fwd3(run2(a2))) {
                            case Right(a3) => Right<S, B>(cont3(a3))
                            case Left(_) => Left<S, B>(s)
                        }
                    case Left(_) => Left<S, B>(s)
                }
            case Left(_) => Left<S, B>(s)
        }
    }
}

@Frozen
public func pinPrismForward4<S, T1, A1, T2, A2, T3, A3, T4, A4, B>(
    sourceThunk: () -> S,
    fwd1: (T1) -> Either<T1, A1>,
    fwd2: (T2) -> Either<T2, A2>,
    fwd3: (T3) -> Either<T3, A3>,
    fwd4: (T4) -> Either<T4, A4>,
    run0: (S) -> T1,
    run1: (A1) -> T2,
    run2: (A2) -> T3,
    run3: (A3) -> T4,
    cont4: (A4) -> B
): (S) -> Either<S, B> {
    { s: S =>
        match (fwd1(run0(s))) {
            case Right(a1) =>
                match (fwd2(run1(a1))) {
                    case Right(a2) =>
                        match (fwd3(run2(a2))) {
                            case Right(a3) =>
                                match (fwd4(run3(a3))) {
                                    case Right(a4) => Right<S, B>(cont4(a4))
                                    case Left(_) => Left<S, B>(s)
                                }
                            case Left(_) => Left<S, B>(s)
                        }
                    case Left(_) => Left<S, B>(s)
                }
            case Left(_) => Left<S, B>(s)
        }
    }
}

@Frozen
public func pinPrismForward5<S, T1, A1, T2, A2, T3, A3, T4, A4, T5, A5, B>(
    sourceThunk: () -> S,
    fwd1: (T1) -> Either<T1, A1>,
    fwd2: (T2) -> Either<T2, A2>,
    fwd3: (T3) -> Either<T3, A3>,
    fwd4: (T4) -> Either<T4, A4>,
    fwd5: (T5) -> Either<T5, A5>,
    run0: (S) -> T1,
    run1: (A1) -> T2,
    run2: (A2) -> T3,
    run3: (A3) -> T4,
    run4: (A4) -> T5,
    cont5: (A5) -> B
): (S) -> Either<S, B> {
    { s: S =>
        match (fwd1(run0(s))) {
            case Right(a1) =>
                match (fwd2(run1(a1))) {
                    case Right(a2) =>
                        match (fwd3(run2(a2))) {
                            case Right(a3) =>
                                match (fwd4(run3(a3))) {
                                    case Right(a4) =>
                                        match (fwd5(run4(a4))) {
                                            case Right(a5) => Right<S, B>(cont5(a5))
                                            case Left(_) => Left<S, B>(s)
                                        }
                                    case Left(_) => Left<S, B>(s)
                                }
                            case Left(_) => Left<S, B>(s)
                        }
                    case Left(_) => Left<S, B>(s)
                }
            case Left(_) => Left<S, B>(s)
        }
    }
}

@Frozen
public func pinPrismForward6<S, T1, A1, T2, A2, T3, A3, T4, A4, T5, A5, T6, A6, B>(
    sourceThunk: () -> S,
    fwd1: (T1) -> Either<T1, A1>,
    fwd2: (T2) -> Either<T2, A2>,
    fwd3: (T3) -> Either<T3, A3>,
    fwd4: (T4) -> Either<T4, A4>,
    fwd5: (T5) -> Either<T5, A5>,
    fwd6: (T6) -> Either<T6, A6>,
    run0: (S) -> T1,
    run1: (A1) -> T2,
    run2: (A2) -> T3,
    run3: (A3) -> T4,
    run4: (A4) -> T5,
    run5: (A5) -> T6,
    cont6: (A6) -> B
): (S) -> Either<S, B> {
    { s: S =>
        match (fwd1(run0(s))) {
            case Right(a1) =>
                match (fwd2(run1(a1))) {
                    case Right(a2) =>
                        match (fwd3(run2(a2))) {
                            case Right(a3) =>
                                match (fwd4(run3(a3))) {
                                    case Right(a4) =>
                                        match (fwd5(run4(a4))) {
                                            case Right(a5) =>
                                                match (fwd6(run5(a5))) {
                                                    case Right(a6) => Right<S, B>(cont6(a6))
                                                    case Left(_) => Left<S, B>(s)
                                                }
                                            case Left(_) => Left<S, B>(s)
                                        }
                                    case Left(_) => Left<S, B>(s)
                                }
                            case Left(_) => Left<S, B>(s)
                        }
                    case Left(_) => Left<S, B>(s)
                }
            case Left(_) => Left<S, B>(s)
        }
    }
}

@Frozen
public func pinPrismForward7<S, T1, A1, T2, A2, T3, A3, T4, A4, T5, A5, T6, A6, T7, A7, B>(
    sourceThunk: () -> S,
    fwd1: (T1) -> Either<T1, A1>,
    fwd2: (T2) -> Either<T2, A2>,
    fwd3: (T3) -> Either<T3, A3>,
    fwd4: (T4) -> Either<T4, A4>,
    fwd5: (T5) -> Either<T5, A5>,
    fwd6: (T6) -> Either<T6, A6>,
    fwd7: (T7) -> Either<T7, A7>,
    run0: (S) -> T1,
    run1: (A1) -> T2,
    run2: (A2) -> T3,
    run3: (A3) -> T4,
    run4: (A4) -> T5,
    run5: (A5) -> T6,
    run6: (A6) -> T7,
    cont7: (A7) -> B
): (S) -> Either<S, B> {
    { s: S =>
        match (fwd1(run0(s))) {
            case Right(a1) =>
                match (fwd2(run1(a1))) {
                    case Right(a2) =>
                        match (fwd3(run2(a2))) {
                            case Right(a3) =>
                                match (fwd4(run3(a3))) {
                                    case Right(a4) =>
                                        match (fwd5(run4(a4))) {
                                            case Right(a5) =>
                                                match (fwd6(run5(a5))) {
                                                    case Right(a6) =>
                                                        match (fwd7(run6(a6))) {
                                                            case Right(a7) => Right<S, B>(cont7(a7))
                                                            case Left(_) => Left<S, B>(s)
                                                        }
                                                    case Left(_) => Left<S, B>(s)
                                                }
                                            case Left(_) => Left<S, B>(s)
                                        }
                                    case Left(_) => Left<S, B>(s)
                                }
                            case Left(_) => Left<S, B>(s)
                        }
                    case Left(_) => Left<S, B>(s)
                }
            case Left(_) => Left<S, B>(s)
        }
    }
}

@Frozen
public func pinPrismForward8<S, T1, A1, T2, A2, T3, A3, T4, A4, T5, A5, T6, A6, T7, A7, T8, A8, B>(
    sourceThunk: () -> S,
    fwd1: (T1) -> Either<T1, A1>,
    fwd2: (T2) -> Either<T2, A2>,
    fwd3: (T3) -> Either<T3, A3>,
    fwd4: (T4) -> Either<T4, A4>,
    fwd5: (T5) -> Either<T5, A5>,
    fwd6: (T6) -> Either<T6, A6>,
    fwd7: (T7) -> Either<T7, A7>,
    fwd8: (T8) -> Either<T8, A8>,
    run0: (S) -> T1,
    run1: (A1) -> T2,
    run2: (A2) -> T3,
    run3: (A3) -> T4,
    run4: (A4) -> T5,
    run5: (A5) -> T6,
    run6: (A6) -> T7,
    run7: (A7) -> T8,
    cont8: (A8) -> B
): (S) -> Either<S, B> {
    { s: S =>
        match (fwd1(run0(s))) {
            case Right(a1) =>
                match (fwd2(run1(a1))) {
                    case Right(a2) =>
                        match (fwd3(run2(a2))) {
                            case Right(a3) =>
                                match (fwd4(run3(a3))) {
                                    case Right(a4) =>
                                        match (fwd5(run4(a4))) {
                                            case Right(a5) =>
                                                match (fwd6(run5(a5))) {
                                                    case Right(a6) =>
                                                        match (fwd7(run6(a6))) {
                                                            case Right(a7) =>
                                                                match (fwd8(run7(a7))) {
                                                                    case Right(a8) => Right<S, B>(cont8(a8))
                                                                    case Left(_) => Left<S, B>(s)
                                                                }
                                                            case Left(_) => Left<S, B>(s)
                                                        }
                                                    case Left(_) => Left<S, B>(s)
                                                }
                                            case Left(_) => Left<S, B>(s)
                                        }
                                    case Left(_) => Left<S, B>(s)
                                }
                            case Left(_) => Left<S, B>(s)
                        }
                    case Left(_) => Left<S, B>(s)
                }
            case Left(_) => Left<S, B>(s)
        }
    }
}
