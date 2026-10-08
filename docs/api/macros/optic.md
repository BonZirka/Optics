# @Optic

Declare a named optic slot by supplying its types, kind, and functions.

Package: `lucida.macrodsl` · [API index](../index.md) · [Source](../../../core/src/macrodsl/user_optic_macro.cj)

```cangjie
public macro Optic(attr: Tokens, input: Tokens): Tokens
```


## Attributes

| Attribute | Required | Meaning |
|---|---|---|
| `source: S` | Yes | Source type |
| `focus: A` | Yes | Focus type |
| `kind: Kind` | Yes | `Lens`, `Affine`, `Prism`, or `Iso` |
| `args: (name: Type, ...)` | No | Parameters supplied by calls to the slot; available in both bodies |
| `forward: { ... }` | Yes | Body that obtains the focus |
| `backward: { ... }` | Yes | Body that updates or constructs the source |

The input declaration must be an empty struct. Its name becomes the slot
name; its type parameters become the declaration's generic parameters. The
macro consumes this carrier and emits registrations. It does not create an
optic variable or an ordinary method to call outside `@f`.

## Function shapes

| Kind | Forward body | Backward body | Path spelling |
|---|---|---|---|
| [`Lens`](../structs/lens.md) | `(S) -> A` | `(S, A) -> S` | `.name(args)` |
| [`Affine`](../structs/affine.md) | `(S) -> Option<A>` | `(S, A) -> S` | `?.name(args)` |
| [`Prism`](../structs/prism.md) | `(S) -> Option<A>` | `(A) -> S` | `?.name(args)` |
| [`Iso`](../structs/iso.md) | `(S) -> A` | `(A) -> S` | `.name(args)` |

Bare forward bodies bind `source`. Bare backward bodies bind `focus`, plus
`source` for Lens and Affine. The backward `focus` is the supplied replacement.

A body can explicitly name its parameters: `{ s => ... }` for forward,
`{ s, a => ... }` for a Lens or Affine backward, or `{ a => ... }` for a Prism
or Iso backward. Use `_` for an unused parameter. Explicit names replace the
fixed names in that body. `source`, `focus`, and `_source` are reserved names
in `args:`.

## Example

With `import lucida.*` and `import lucida.macrodsl.*`:

```cangjie
@Optic[
    source: Int64,
    focus: Int64,
    kind: Iso,
    forward: { source },
    backward: { focus }
]
struct identityValue {}
```

Inside a function:

```cangjie
let number: Int64 = 7
let value = @f(number.identityValue()) // 7
let optic: Iso<Int64, Int64> = @f(@typeof(number).identityValue())
```

## Semantics and constraints

The supplied bodies must satisfy the chosen kind's behavior and laws. An
Affine backward must preserve a source on a miss. An Iso's functions must
be inverses. The macro checks declaration shape; the compiler checks types.
Neither validates these behavioral contracts.

Generic parameters belong on the carrier. Call sites infer them from the
source; explicit method-level type arguments and carrier `where` clauses
are unsupported. A name can be reused for different source types, but two
registrations for the same name and source can collide even when their
arguments or kind differ.

## Kind aliases

[`@Lens`](lens.md), [`@Affine`](affine.md), [`@Prism`](prism.md), and
[`@Iso`](iso.md) take the same attributes except `kind:`, which they reject.
Each fixes that kind. `Setter` is available as a [struct](../structs/setter.md),
not as an `@Optic` kind or declaration alias.

See also: [Custom optics tutorial](../../examples/user-optics.md),
[`@DeriveOptics`](deriveoptics.md), [Diagnostics](../../diagnostics.md#custom-declarations).
