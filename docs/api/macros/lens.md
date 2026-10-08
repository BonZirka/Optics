# @Lens

A total slot whose update receives the original source.

Package: `lucida.macrodsl` · [API index](../index.md) · [Source](../../../core/src/macrodsl/user_optic_macro.cj)

```cangjie
public macro Lens(attr: Tokens, input: Tokens): Tokens
```


## Attributes and bodies

This is shorthand for `@Optic[kind: Lens, ...]`. It takes `source:`,
`focus:`, `forward:`, `backward:`, and optional `args:`. Supplying `kind:` is
an error. The annotated declaration must be an empty struct.

| Body | Function shape | Fixed parameters |
|---|---|---|
| `forward` | `(S) -> A` | `source` |
| `backward` | `(S, A) -> S` | `source, focus` |

See [`@Optic`](optic.md) for attribute syntax, parameter naming, generics,
and registration constraints.

## Semantics

The backward body must preserve unrelated data in the source.

The slot uses `.firstField()` syntax in a path. Constructing an optic from that path
produces a [`Lens<S, A>`](../structs/lens.md) value.

## Example

With `import lucida.*` and `import lucida.macrodsl.*`:

```cangjie
@Lens[
    source: (Int64, String),
    focus: Int64,
    forward: { source[0] },
    backward: { (focus, source[1]) }
]
struct firstField {}
```

Inside a function:

```cangjie
let pair = (7, "Ada")
let changed = @f(pair.firstField() <- 9) // (9, "Ada")
```

See also: [`Lens` members and laws](../structs/lens.md),
[`@Optic`](optic.md), [Custom optics tutorial](../../examples/user-optics.md).
