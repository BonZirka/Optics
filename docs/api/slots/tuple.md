# Tuple elements

Access a tuple element using its zero-based position.

Package: `lucida` · [API index](../index.md) · [Source](../../../core/src/macrodsl/tuple_lens_gen.cj)

## Slots

| Form inside `@f` | Meaning |
|---|---|
| `pair._0` | First element |
| `pair._1` | Second element |
| `tuple._N` | Element at the literal position `N`, if it exists |
| `pair._0 <- replacement` | Reconstruct the tuple with a replacement first element |

Here `N` denotes a numeric suffix such as `2`; it is not an expression or
variable. Slots are generated for tuples of arity 2 through 16. Each slot is
a [`Lens`](../structs/lens.md) from the tuple to that element's type.

## Semantics

Tuple slots use `.` for total access. The replacement has the same type as
the selected element, and the remaining elements are preserved. There is no
annotation to apply to the tuple; importing the core library supplies the
registrations.

The spelling `._0` belongs to the optic path syntax. Ordinary Cangjie tuple
indexing uses `[0]` outside `@f`.

## Example

Inside a function, with `import lucida.*` and `import lucida.macrodsl.*`:

```cangjie
let pair = ("Ada", 7)
let name = @f(pair._0) // "Ada"
let changed = @f(pair._1 <- 9) // ("Ada", 9)
let first: Lens<(String, Int64), String> = @f(@typeof(pair)._0)
```

See also: [`@f` blocks](../macros/f.md#blocks),
[`@typeof`](../macros/typeof.md), [`Lens`](../structs/lens.md).
