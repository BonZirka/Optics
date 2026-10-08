# Setter

An optic that applies a modifier function through a source.

Package: `lucida` · [API index](../index.md) · [Source](../../../core/src/first_class.cj)

Declaration, with the property implementation omitted:

```cangjie
public struct Setter<S, A> {
    public Setter(
        public let modify: (S, (A) -> A) -> S
    ) {}
    public prop modifyId: (S) -> S
}
```

## Members

| Member | Description |
|---|---|
| `Setter(modify)` | Construct an optic from a function value |
| `modify(source, modifier)` | Apply `(A) -> A` through the optic and return the resulting source |
| `modifyId(source)` | Call `modify` with the identity function `{ value => value }` |

`modifyId` is a property returning a function value. A setter provides no
`view` or `preview` member.

## Example

Inside a function, after `import lucida.*`:

```cangjie
let first = Setter<(Int64, String), Int64>(
    { pair, modifier => (modifier(pair[0]), pair[1]) }
)
let changed = first.modify((7, "Ada"), { value => value + 1 }) // (8, "Ada")
let unchanged = first.modifyId((7, "Ada")) // (7, "Ada")
```

## Laws

For an ordinary setter, applying the identity function preserves the source.
Two successive modifications agree with applying those functions in sequence
inside one modification. These laws assume stable functions without side
effects; constructing a setter does not check them.

## Preset replacements from the DSL

A path starting from a type or optic value and ending in `<- replacement`
constructs a `Setter` with a preset replacement:

```cangjie
let pair = (7, "Ada")
let replaceFirst = @f(@typeof(pair)._0 <- 9)
let replaced = replaceFirst.modifyId(pair) // (9, "Ada")
let adjusted = replaceFirst.modify(pair, { value => value + 1 }) // (10, "Ada")
```

This example also requires `import lucida.macrodsl.*`. For this form,
`modify` applies its function to the preset replacement, and `modifyId`
performs that replacement. Its identity behavior differs from an ordinary
setter. The modifier does not receive the previous focus.

See also: [`@f`](../macros/f.md), [`Lens`](lens.md),
[Optic values](../../examples/optic-values.md).
