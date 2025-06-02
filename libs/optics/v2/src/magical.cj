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