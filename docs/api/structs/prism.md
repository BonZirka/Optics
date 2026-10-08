# Prism

An optic that can match a focus and construct a source from a focus alone.

Package: `lucida` · [API index](../index.md) · [Source](../../../core/src/first_class.cj)

```cangjie
public struct Prism<S, A> {
    public Prism(
        public let preview: (S) -> Option<A>,
        public let build: (A) -> S
    ) {}
}
```

## Members

| Member | Description |
|---|---|
| `Prism(preview, build)` | Construct an optic from two function values |
| `preview(source)` | Return `Some(focus)` on a match, or `None` on a miss |
| `build(focus)` | Construct a source without taking an old source |

## Semantics

`build` constructs unconditionally. It has no original source to test or
preserve. A partial update through [`@f`](../macros/f.md) first checks for a
match and preserves the original source on a miss. Calling `build` directly
performs only construction.

## Example

Inside a function, after `import lucida.*`:

```cangjie
let some = Prism<Option<Int64>, Int64>(
    { source => source },
    { focus => Some(focus) }
)
let found = some.preview(Some(7)) // Some(7)
let missed = some.preview(Option<Int64>.None) // None
let built = some.build(9) // Some(9)
```

## Laws

For a focus `a` and source `s`:

```text
preview(build(a)) = Some(a)
if preview(s) = Some(a), then build(a) = s
```

These laws assume stable functions without side effects. A successful preview
must retain enough information to reconstruct its source. The constructor
checks function types, not these equations.

See also: [`@Prism`](../macros/prism.md), [`Affine`](affine.md),
[`@DeriveOptics`](../macros/deriveoptics.md#enums), which derives affine case slots.
