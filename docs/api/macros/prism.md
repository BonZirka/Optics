# @Prism

A partial slot that constructs a source from the focus alone.

Package: `lucida.macrodsl` · [API index](../index.md) · [Source](../../../core/src/macrodsl/user_optic_macro.cj)

```cangjie
public macro Prism(attr: Tokens, input: Tokens): Tokens
```


## Attributes and bodies

This is shorthand for `@Optic[kind: Prism, ...]`. It takes `source:`,
`focus:`, `forward:`, `backward:`, and optional `args:`. Supplying `kind:` is
an error. The annotated declaration must be an empty struct.

| Body | Function shape | Fixed parameters |
|---|---|---|
| `forward` | `(S) -> Option<A>` | `source` |
| `backward` | `(A) -> S` | `focus` |

See [`@Optic`](optic.md) for attribute syntax, parameter naming, generics,
and registration constraints.

## Semantics

The backward body has no source parameter. A partial DSL update checks for a match before rebuilding; direct `build` constructs unconditionally.

The slot uses `?.someValue()` syntax in a path. Constructing an optic from that path
produces a [`Prism<S, A>`](../structs/prism.md) value.

## Example

With `import lucida.*` and `import lucida.macrodsl.*`:

```cangjie
@Prism[
    source: Option<Int64>,
    focus: Int64,
    forward: { source },
    backward: { Some(focus) }
]
struct someValue {}
```

Inside a function:

```cangjie
let value: Option<Int64> = Some(7)
let some: Prism<Option<Int64>, Int64> = @f(@typeof(value)?.someValue())
let built = some.build(9) // Some(9)
```

See also: [`Prism` members and laws](../structs/prism.md),
[`@Optic`](optic.md), [Custom optics tutorial](../../examples/user-optics.md).
