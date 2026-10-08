# @typeof

Start an optic path using an expression's type.

Package: `lucida.macrodsl` · [API index](../index.md) · [Source](../../../core/src/macrodsl/inner_macros.cj)

```cangjie
public macro typeof(input: Tokens): Tokens
```


## Input and result

| Form inside `@f` | Result |
|---|---|
| `@typeof(expression).path` | An optic whose source type is the expression's type |
| `@typeof(expression).path <- replacement` | A setter with a preset replacement |

## Semantics

`@typeof` is valid only at the beginning of a path inside [`@f`](f.md).
The expression supplies a type witness. It is not the source on which the
resulting optic performs its reads or updates; those operations receive their
source when called. Prefer a value already in scope, and avoid relying on
side effects in witness expressions.

## Example

Inside a function, with `import lucida.*` and `import lucida.macrodsl.*`:

```cangjie
let pair = (7, "Ada")
let first: Lens<(Int64, String), Int64> = @f(@typeof(pair)._0)
let value = first.view((9, "Grace")) // 9
```

See also: [`@ty`](ty.md), [`@use`](use.md), [Tuple slots](../slots/tuple.md).
