# @DeriveOptics

Generate optic slots from a struct, class, or enum declaration.

Package: `lucida.macrodsl` · [API index](../index.md) · [Source](../../../core/src/macrodsl/derive_macro.cj)

```cangjie
public macro DeriveOptics(input: Tokens): Tokens
```


## Input and generated slots

| Declaration | Generated operations |
|---|---|
| Struct or class with primary-constructor fields | A [`Lens`](../structs/lens.md) slot for each field |
| Struct or class with exactly one constructor field | Field lens plus [`Iso`](../structs/iso.md) conversions in both directions |
| Enum | An [`Affine`](../structs/affine.md) slot for each case |

The annotated type remains usable as an ordinary Cangjie type. Import
`lucida.*` and `lucida.macrodsl.*` where you use the generated slots.

## Records

A record must have a primary constructor. Each of its parameters must declare
a non-private field with `let` or `var`. Public fields receive public optic
members; other accepted visibilities receive package-visible members. Fields
and properties declared elsewhere in the body are not added to this list.

A field slot uses `.field`. Its update calls the primary constructor with
the replacement and the other field values from the old source. Updating a
class constructs a new instance. Constructor effects run again, and unrelated
mutable values can remain shared.

## Enums

A case slot uses `?.Case`. It previews the payload on a match and preserves
an unmatched source during an update. Derived cases are affines.

| Case payload | Focus type | Preview result |
|---|---|---|
| No payload | `Unit` | `Option<Unit>` |
| One value of type `A` | `A` | `Option<A>` |
| Several values | Tuple of the payload types | `Option` of that tuple |

## Example

With `import lucida.*` and `import lucida.macrodsl.*`:

```cangjie
@DeriveOptics
public enum Job {
    | Waiting
    | Running(Int64)
}
```

Inside a function:

```cangjie
let job = Job.Running(7)
let payload = @f(job?.Running) // Some(7)
let changed = @f(job?.Running <- 9)
let running: Affine<Job, Int64> = @f(@ty(Job)?.Running)
```

## Constraints

Unconstrained generic declarations are supported. `where` clauses are
currently rejected. Derived updates preserve the source and focus types;
they cannot turn `Box<Int64>` into `Box<String>`.

A one-field record additionally supplies [`.coerce<T>()`](../slots/coerce.md).
Several fields do not supply that conversion because reconstruction needs
values for the other fields.

See also: [Deriving optics tutorial](../../examples/deriving.md),
[`@Optic`](optic.md), [Tuple slots](../slots/tuple.md).
