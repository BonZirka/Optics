# Composition

[API index](index.md) · [`@use`](macros/use.md) · [Optic values guide](../examples/optic-values.md)

Composition combines an optic from `S` to `A` with one from `A` to `B`,
producing an optic from `S` to `B`. The focus type of the first optic must
match the source type of the second.

Using the records from [Getting started](../getting-started.md):

```cangjie
let address = @f(@ty(Person).address)
let city = @f(@ty(Address).city)
let personCity = @f(@use(address).@use(city))
```

The combined value has type `Lens<Person, String>`. It can also be written
as `@f(@ty(Person).address.city)`.

## How a combined lens behaves

Let `outer` be a `Lens<S, A>` and `inner` a `Lens<A, B>`. Its operations can
be described with this pseudocode:

```text
view(source):
    return inner.view(outer.view(source))

update(source, replacement):
    oldPart = outer.view(source)
    newPart = inner.update(oldPart, replacement)
    return outer.update(source, newPart)
```

The read proceeds towards the focus. Reconstruction proceeds back towards
the source, preserving the surrounding data at each level.

## Result kinds

The row is the first optic applied to the source. The column is the optic
applied to its focus.

| First / next | Iso | Lens | Prism | Affine | Setter |
|---|---|---|---|---|---|
| Iso | Iso | Lens | Prism | Affine | Setter |
| Lens | Lens | Lens | Affine | Affine | Setter |
| Prism | Prism | Affine | Prism | Affine | Setter |
| Affine | Affine | Affine | Affine | Affine | Setter |
| Setter | Setter | Setter | Setter | Setter | Setter |

For example, a lens followed by a prism gives an affine. Reading may fail
at the prism, and rebuilding the outer record still requires its old source.
Two prisms can build the entire source from the final focus, so their
composition remains a prism.

The table describes supported combinations of function shapes. It does not
establish that arbitrary functions supplied by a caller satisfy optic laws.

## Partial paths

A composed partial read produces `None` if any partial slot misses. Total
slots after a partial slot run only after a successful match. The
result is one `Option` for the path, not an additional wrapper for every
partial slot.

A value update written with partial slots checks for a match and preserves
the original source on a miss. Direct `Prism.build` calls retain their
construction semantics, so they should not be used as a substitute for this
check.

A field whose value happens to be `Option<T>` is still a total field lens:
reading the field always returns an `Option<T>`. That value must be unwrapped
by a separate partial operation. The current standard optics do not include
that operation.

## Fused and composed execution

Ordinary value paths use the fused emitter where supported. It generates a
read and rebuild sequence for the path instead of combining intermediate
function pairs at runtime.

`@f[unfuse](source.path <- value)` requests the library composition path for
ordinary chains. This is useful for implementation comparisons and regression
tests. First-class optic construction also uses composition because it must
produce reusable function values.

The two forms are intended to agree for the supported optics and expressions.
Do not use effects inside custom optic bodies to infer a required call count
from one emitter's behavior. Blocks have their own emitter; `[unfuse]` does
not select a separate block implementation.

## Implementation reference

[`generate_compositions.cj`](../../core/src/macrodsl/generate_compositions.cj)
generates 25 ordered pairs of `composeForward` and `composeBackward`
overloads, together with the registry upcasts used by subsequent slots.
The generated host is `__OpticsCompositions`.

Those names are internal. Application code can use `@use` to compose optic
values without calling the registry helpers. See
[registry dispatch](../architecture/registry-plumbing.md) and
[fusion](../architecture/fusion-walk.md) when changing the implementation.
