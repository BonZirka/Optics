# Iso

An optic that converts between a source and a focus in both directions.

Package: `lucida` · [API index](../index.md) · [Source](../../../core/src/first_class.cj)

```cangjie
public struct Iso<S, A> {
    public Iso(
        public let to: (S) -> A,
        public let from: (A) -> S
    ) {}
}
```

## Members

| Member | Description |
|---|---|
| `Iso(to, from)` | Construct an optic from two function values |
| `to(source)` | Convert the source to its focus |
| `from(focus)` | Convert a focus back to a source |

## Semantics

Both directions are total. `from` receives no old source. The functions
should be inverses; the constructor does not validate that property.

## Example

Inside a function, after `import lucida.*`:

```cangjie
let swap = Iso<(Int64, String), (String, Int64)>(
    { pair => (pair[1], pair[0]) },
    { pair => (pair[1], pair[0]) }
)
let focus = swap.to((7, "Ada")) // ("Ada", 7)
let restored = swap.from(focus) // (7, "Ada")
```

## Laws

```text
from(to(source)) = source
to(from(focus)) = focus
```

Equality means equality of the relevant values, assuming stable functions
without side effects. A lossy conversion does not satisfy these equations
merely because a function is supplied in each direction.

See also: [`@Iso`](../macros/iso.md), [`coerce`](../slots/coerce.md),
[Composition](../composition.md).
