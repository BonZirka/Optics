# Registry dispatch

A registry is an empty value whose type tells the compiler which overloads
and generated members are available. It does not contain application data
or store a runtime table of registered optics.

The mechanism connects a syntactic path to ordinary typed functions. A macro
can emit the calls without first resolving the type of every field itself.

## Two kinds of witness

`RegistryMagical<T>` identifies the type currently reached by the path.
Kind registries identify both that type and the operation's kind:

```text
RegistryLenses<T>
RegistryAffines<T>
RegistryIsos<T>
RegistryPrisms<T>
RegistrySetters<T>
```

`magic<T>()` produces a type witness directly. `magic({ => expression })`
lets Cangjie infer `T` from a function's return type. That helper ignores the
function body; it does not evaluate the expression to obtain the witness.

## Follow a field

Suppose `Person.address` has type `Address`. Derivation supplies three
capabilities for that slot:

1. Choose a lens registry for the source type.
2. Obtain the functions that read and replace `address`.
3. Obtain a witness for `Address`, the type reached next.

The following is an illustrative sequence of internal calls:

```cangjie
let owner = magic<Person>()
let kind = owner.__downcast(owner)
let forward = kind.__address_impl_forward
let backward = kind.__address_impl_backward
let next = owner.__address_optics(owner)
```

`next` has type `RegistryMagical<Address>`. The following `.city` slot can
therefore resolve the members emitted for `Address`. `forward` and `backward`
are function values; the registry itself does not hold the person.

These are implementation names. Application code writes the path or uses a
public optic value rather than assembling this sequence.

## Select a kind

| Slot | Kind selection |
|---|---|
| Derived record field | `__downcast` returns `RegistryLenses<Source>` |
| Derived enum case | `__downcast` returns `RegistryAffines<Source>` |
| Custom declared optic | `__downcast_method_name` returns its declared registry |
| `coerce<T>()` | Source and target witnesses select an iso conversion |
| First-class optic | Overloads on the public struct expose its kind and functions |

A `.` or `?.` in the input records an expectation. The registry supplies the
actual kind. The emitter can pass both to an overload that accepts valid
pairs and diagnoses invalid ones.

This matters where function shapes alone are insufficient. A lens and an iso
both have a total forward, while a prism and an affine both have a partial
forward. Their backwards and kind witnesses determine how composition and
reconstruction proceed.

## Custom member names

A declared optic such as `at` supplies methods with names including:

```text
__method_at_impl_forward
__method_at_impl_backward
__method_at_optics
__downcast_method_at
```

The method arguments become parameters of the generated functions that
return those operations. The source witness specializes the generic
extension, so array element types can be inferred at the call site.

Interface names include the signature to allow the same optic name on
different sources. The dispatch names above do not include that signature,
so same-name declarations on one source still need to avoid member clashes.

## Composition dispatch

The generated composition functions first accept two kind witnesses. Their
selected overload then accepts the forward and backward functions for both
slots. This supplies enough type information to construct the combined
functions.

A registry upcast identifies the combined kind for a subsequent slot.
The result follows the [composition table](../api/composition.md#result-kinds):
for example, a lens followed by a prism has affine capabilities.

## Runtime cost and visibility

An empty witness has no application payload. That fact does not prove that
every constructor or call involving it disappears from the binary. Inlining,
module boundaries, and compiler optimization affect the result. Performance
claims need an emitted-code inspection or a measurement.

The helpers are visible to consumer macro expansions through the core
imports. They remain [implementation details](../api/internals.md), including
helpers with names that do not start with `__`.

The relevant sources are [`magical.cj`](../../core/src/magical.cj),
[`derive_macro.cj`](../../core/src/macrodsl/derive_macro.cj), and
[`user_optic_macro.cj`](../../core/src/macrodsl/user_optic_macro.cj).
