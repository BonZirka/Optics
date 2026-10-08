# @ty

Start an optic path from an explicit source type.

Package: `lucida.macrodsl` · [API index](../index.md) · [Source](../../../core/src/macrodsl/inner_macros.cj)

```cangjie
public macro ty(input: Tokens): Tokens
```


## Input and result

| Form inside `@f` | Result |
|---|---|
| `@ty(Type).path` | An optic whose source type is `Type` |
| `@ty(Type).path <- replacement` | A setter with a preset replacement |

## Semantics

`@ty` is valid only at the beginning of a path inside [`@f`](f.md). Its input
must be a plain type identifier, such as `Point`. The current parser does not
accept built-in type keywords such as `Int64` or explicit generic applications
such as `Box<Int64>`. Use [`@typeof`](typeof.md) with a value of the desired
type for these cases and for tuples.

The remaining slots determine the focus type and optic kind. This form
constructs an optic value without supplying a source value to read or update.

## Example

With `import lucida.*` and `import lucida.macrodsl.*`:

```cangjie
@DeriveOptics
public struct Point {
    public Point(public let x: Int64, public let y: Int64) {}
}
```

Inside a function:

```cangjie
let x: Lens<Point, Int64> = @f(@ty(Point).x)
let changed = x.update(Point(2, 3), 8)
```

See also: [`@typeof`](typeof.md), [`@use`](use.md),
[Preset replacements](../structs/setter.md#preset-replacements-from-the-dsl).
