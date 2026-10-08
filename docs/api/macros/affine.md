# @Affine

A partial slot whose update receives the original source.

Package: `lucida.macrodsl` · [API index](../index.md) · [Source](../../../core/src/macrodsl/user_optic_macro.cj)

```cangjie
public macro Affine(attr: Tokens, input: Tokens): Tokens
```


## Attributes and bodies

This is shorthand for `@Optic[kind: Affine, ...]`. It takes `source:`,
`focus:`, `forward:`, `backward:`, and optional `args:`. Supplying `kind:` is
an error. The annotated declaration must be an empty struct.

| Body | Function shape | Fixed parameters |
|---|---|---|
| `forward` | `(S) -> Option<A>` | `source` |
| `backward` | `(S, A) -> S` | `source, focus` |

See [`@Optic`](optic.md) for attribute syntax, parameter naming, generics,
and registration constraints.

## Semantics

The backward body must preserve a source with no matching focus.

The slot uses `?.presentValue()` syntax in a path. Constructing an optic from that path
produces a [`Affine<S, A>`](../structs/affine.md) value.

## Example

With `import lucida.*` and `import lucida.macrodsl.*`:

```cangjie
@Affine[
    source: Option<Int64>,
    focus: Int64,
    forward: { source },
    backward: { if (source.isSome()) { Some(focus) } else { source } }
]
struct presentValue {}
```

Inside a function:

```cangjie
let value: Option<Int64> = Some(7)
let changed = @f(value?.presentValue() <- 9) // Some(9)
```

See also: [`Affine` members and laws](../structs/affine.md),
[`@Optic`](optic.md), [Custom optics tutorial](../../examples/user-optics.md).
