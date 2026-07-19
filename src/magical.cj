package lucida

import lucida.macrodsl.*

public struct RegistryMagical<T> { }

public func __downcast_method_coerce<T, G>(_: RegistryMagical<T>, _: RegistryMagical<G>): RegistryIsos<T> {
    RegistryIsos()
}

public struct RegistryIsos<T>      {
    @Frozen
    public init() { }
} // (a) -> b, (b) -> a
public struct RegistryLenses<T>    {
    @Frozen
    public init() { }
} // (a) -> b, (a, b) -> a
public struct RegistryPrisms<T>    {
    @Frozen
    public init() { }
} // (a) -> Either a b, (b) -> a
public struct RegistryAffines<T>   {
    @Frozen
    public init() { }
} // (a) -> Either a b, (a, b) -> a
public struct RegistrySetters<T>   {
    @Frozen
    public init() { }
} // (a) -> a, (a, (b) -> b) -> a

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
//
// The walkers themselves are generated by @GeneratePrismForward
// (lucida.macrodsl, generate_prism_forward.cj) — raising the fusion cap is a
// matter of regenerating with a larger N, not hand-unrolling more levels.
@GeneratePrismForward(16)
