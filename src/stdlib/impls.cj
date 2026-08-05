package lucida.stdlib

import lucida.*
import std.collection.*

sealed interface __Stdlib_optics_impl<T> {
    // Array<T>.at(n)
    @Frozen
    func __method_at_impl_forward(_: RegistryMagical<Array<T>>, n: Int64): (Array<T>) -> Option<T>
    @Frozen
    func __method_at_impl_backward(_: RegistryMagical<Array<T>>, n: Int64): (Array<T>, T) -> Array<T>

    // Array<T>.selectFirst((T) -> Bool)
    @Frozen
    func __method_selectFirst_impl_forward(_: RegistryMagical<Array<T>>, cond: (T) -> Bool): (Array<T>) -> Option<T>
    @Frozen
    func __method_selectFirst_impl_backward(_: RegistryMagical<Array<T>>, cond: (T) -> Bool): (Array<T>, T) -> Array<T>
}
sealed interface __Stdlib_suboptics_accessors<T> {
    // Array<T>.at(n)
    @Frozen
    func __method_at_optics(_: RegistryMagical<Array<T>>): RegistryMagical<T>
    @Frozen
    func __method_selectFirst_optics(_: RegistryMagical<Array<T>>): RegistryMagical<T>
}
sealed interface __Stdlib_downcast<T> {
    // Array<T>.at(n)
    @Frozen
    func __downcast_method_at(_: RegistryMagical <Array<T>>): RegistryAffines<Array<T>>
    @Frozen
    func __downcast_method_selectFirst(_: RegistryMagical <Array<T>>): RegistryAffines<Array<T>>
}

extend <T> RegistryMagical<Array<T>> <: __Stdlib_downcast<T> {
    @Frozen
    public func __downcast_method_at(_: RegistryMagical <Array<T>>): RegistryAffines<Array<T>> {
        RegistryAffines()
    }
    @Frozen
    public func __downcast_method_selectFirst(_: RegistryMagical <Array<T>>): RegistryAffines<Array<T>> {
        RegistryAffines()
    }
}
extend <T> RegistryMagical<Array<T>> <: __Stdlib_suboptics_accessors<T> {
    @Frozen
    public func __method_at_optics(_: RegistryMagical<Array<T>>): RegistryMagical<T> { 
        RegistryMagical()
    }
    @Frozen
    public func __method_selectFirst_optics(_: RegistryMagical<Array<T>>): RegistryMagical<T> { 
        RegistryMagical()
    }
}
extend <T> RegistryAffines<Array<T>> <: __Stdlib_optics_impl<T> {
    @Frozen
    public func __method_at_impl_forward(_: RegistryMagical<Array<T>>, n: Int64): (Array<T>) -> Option<T> {
        { source: Array<T> => 
            if (let Some(focus) <- source.get(n)) {
                Some(focus)
            } else {
                None
            }
        }
    }

    @Frozen
    public func __method_at_impl_backward(_: RegistryMagical<Array<T>>, n: Int64): (Array<T>, T) -> Array<T> {
        { source: Array<T>, focus: T =>
            if (let Some(_) <- source.get(n)) {
                // Copy before writing: updates must never mutate the caller's array.
                let updated = source.clone()
                updated[n] = focus
                updated
            } else {
                source
            }
        }
    }
    @Frozen
    public func __method_selectFirst_impl_forward(_: RegistryMagical<Array<T>>, cond: (T) -> Bool): (Array<T>) -> Option<T> {
        { source: Array<T> => 
            for (x in source) {
                if (cond(x)) {
                    return Some(x)
                }
            }
            None
        }
    }
    @Frozen
    public func __method_selectFirst_impl_backward(_: RegistryMagical<Array<T>>, cond: (T) -> Bool): (Array<T>, T) -> Array<T> {
        { source: Array<T>, focus: T =>
            let updated = Box(false)
            source |> map { x: T => if (!updated.value && cond(x)) { updated.value = true; focus } else {x} } |> collectArray
        }
    }
}
