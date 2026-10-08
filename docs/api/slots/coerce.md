# coerce

Apply a registered iso conversion in an optic path.

Supplied by: `@DeriveOptics` · [API index](../index.md) · [Source](../../../core/src/macrodsl/derive_macro.cj)

## Syntax

| Form inside `@f` | Meaning |
|---|---|
| `source.coerce<T>()` | Convert the source to `T` |
| `source.coerce<T>() <- replacement` | Reconstruct the source using the inverse conversion |
| `@ty(Source).coerce<T>()` | Construct an `Iso<Source, T>` value |

The reserved slot takes exactly one type argument and no value arguments.
Use `.` for total access.

## Semantics

[`@DeriveOptics`](../macros/deriveoptics.md) registers conversions in both
directions between a record with exactly one constructor field and that
field's type. Unwrapping reads the field; wrapping calls the constructor.
No automatic conversion is generated for a record with several fields.

`coerce` uses the registered functions for those types. It is not a general
Cangjie cast and does not provide arbitrary numeric or string conversions.
The resulting optic has the [`Iso`](../structs/iso.md) contract.

## Example

With `import lucida.*` and `import lucida.macrodsl.*`:

```cangjie
@DeriveOptics
public struct Meters {
    public Meters(public let value: Int64) {}
}
```

Inside a function:

```cangjie
let distance = Meters(7)
let number = @f(distance.coerce<Int64>()) // 7
let changed = @f(distance.coerce<Int64>() <- 9) // Meters(9)
let conversion: Iso<Meters, Int64> = @f(@ty(Meters).coerce<Int64>())
```

For a named custom conversion slot, use [`@Iso`](../macros/iso.md).

See also: [Wrapper derivation](../../examples/deriving.md#one-field-wrappers),
[`Iso`](../structs/iso.md).
