# @use

Insert an existing optic value into a path.

Package: `lucida.macrodsl` · [API index](../index.md) · [Source](../../../core/src/macrodsl/inner_macros.cj)

```cangjie
public macro use(input: Tokens): Tokens
```


## Input and result

| Form | Result |
|---|---|
| `@f(@use(optic).path)` | An optic composed from `optic` and subsequent slots |
| `@f(source.@use(optic))` | Apply the optic to a source value |
| `@f(source.@use(optic) <- replacement)` | Update through the optic |

## Semantics

Use `@use` only inside [`@f`](f.md), at the root or as an interior slot.
Its input must be an identifier bound to an optic value. Bind constructor
calls and other expressions to a variable first. Explicit type arguments on
that identifier are rejected.

The optic's source type must match the focus reached by the preceding path.
The inserted value carries its own optic kind. The resulting kind follows
the [composition table](../composition.md#result-kinds).

## Example

Inside a function, with `import lucida.*` and `import lucida.macrodsl.*`:

```cangjie
let pair = (7, "Ada")
let first = @f(@typeof(pair)._0)
let reused: Lens<(Int64, String), Int64> = @f(@use(first))
let changed = @f(pair.@use(reused) <- 9) // (9, "Ada")
```

See also: [Optic values](../../examples/optic-values.md),
[Composition](../composition.md), [`@ty`](ty.md).
