# @Iso

A total conversion with an inverse that needs only the focus.

Package: `lucida.macrodsl` · [API index](../index.md) · [Source](../../../core/src/macrodsl/user_optic_macro.cj)

```cangjie
public macro Iso(attr: Tokens, input: Tokens): Tokens
```


## Attributes and bodies

This is shorthand for `@Optic[kind: Iso, ...]`. It takes `source:`,
`focus:`, `forward:`, `backward:`, and optional `args:`. Supplying `kind:` is
an error. The annotated declaration must be an empty struct.

| Body | Function shape | Fixed parameters |
|---|---|---|
| `forward` | `(S) -> A` | `source` |
| `backward` | `(A) -> S` | `focus` |

See [`@Optic`](optic.md) for attribute syntax, parameter naming, generics,
and registration constraints.

## Semantics

The two bodies must be inverses. The backward body has no source parameter.

The slot uses `.swapped()` syntax in a path. Constructing an optic from that path
produces a [`Iso<S, A>`](../structs/iso.md) value.

## Example

With `import lucida.*` and `import lucida.macrodsl.*`:

```cangjie
@Iso[
    source: (Int64, String),
    focus: (String, Int64),
    forward: { (source[1], source[0]) },
    backward: { (focus[1], focus[0]) }
]
struct swapped {}
```

Inside a function:

```cangjie
let pair = (7, "Ada")
let value = @f(pair.swapped()) // ("Ada", 7)
```

See also: [`Iso` members and laws](../structs/iso.md),
[`@Optic`](optic.md), [Custom optics tutorial](../../examples/user-optics.md).
