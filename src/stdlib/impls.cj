package lucida.stdlib

import lucida.*
import lucida.macrodsl.*

// Array<T>.at(n) and Array<T>.selectFirst(cond) — both affine, both declared
// as ordinary @Optic carriers; the expansion mints the __method_* members the
// chain emitter looks up, so no hand-written plumbing remains.
//
// selectFirst's backward replaces only the FIRST match, tracked by a mutable
// flag threaded through the map.

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

@Optic[
    source: Array<T>,
    focus: T,
    kind: Affine,
    args: (cond: (T) -> Bool),
    forward: {
        for (x in source) {
            if (cond(x)) {
                return Some(x)
            }
        }
        None
    },
    backward: {
        let replaced = Box(false)
        source.map { x: T => if (!replaced.value && cond(x)) { replaced.value = true; focus } else { x } }
    }
]
public struct selectFirst<T> {}
