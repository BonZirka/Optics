package lucida.stdlib

import lucida.*
import lucida.macrodsl.*
import std.collection.*

// Array<T>.at(n) is declared exactly like a user optic: the @Optic
// expansion mints the same __method_at_* members the chain emitter looks
// up, so the hand-written plumbing below (interfaces + extends) is gone.
//
// Array<T>.selectFirst(cond) stays hand-written: its backward replaces
// only the FIRST match via a mutable flag threaded through the map, which
// does not fit the single-expression body fields.
@Optic[
    source: Array<T>,
    focus: T,
    kind: Affine,
    args: (n: Int64),
    forward: {
        if (let Some(focus) <- source.get(n)) {
            Some(focus)
        } else {
            None
        }
    },
    backward: {
        if (let Some(_) <- source.get(n)) {
            // Copy before writing: updates must never mutate the caller's array.
            let updated = source.clone()
            updated[n] = focus
            updated
        } else {
            source
        }
    }
]
public struct at<T> {}

sealed interface __Stdlib_optics_impl<T> {
    // Array<T>.selectFirst((T) -> Bool)
    @Frozen
    func __method_selectFirst_impl_forward(_: RegistryMagical<Array<T>>, cond: (T) -> Bool): (Array<T>) -> Option<T>
    @Frozen
    func __method_selectFirst_impl_backward(_: RegistryMagical<Array<T>>, cond: (T) -> Bool): (Array<T>, T) -> Array<T>
}
sealed interface __Stdlib_suboptics_accessors<T> {
    // Array<T>.selectFirst((T) -> Bool)
    @Frozen
    func __method_selectFirst_optics(_: RegistryMagical<Array<T>>): RegistryMagical<T>
}
sealed interface __Stdlib_downcast<T> {
    // Array<T>.selectFirst((T) -> Bool)
    @Frozen
    func __downcast_method_selectFirst(_: RegistryMagical <Array<T>>): RegistryAffines<Array<T>>
}

extend <T> RegistryMagical<Array<T>> <: __Stdlib_downcast<T> {
    @Frozen
    public func __downcast_method_selectFirst(_: RegistryMagical <Array<T>>): RegistryAffines<Array<T>> {
        RegistryAffines()
    }
}
extend <T> RegistryMagical<Array<T>> <: __Stdlib_suboptics_accessors<T> {
    @Frozen
    public func __method_selectFirst_optics(_: RegistryMagical<Array<T>>): RegistryMagical<T> {
        RegistryMagical()
    }
}
extend <T> RegistryAffines<Array<T>> <: __Stdlib_optics_impl<T> {
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
