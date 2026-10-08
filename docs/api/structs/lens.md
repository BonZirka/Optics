# Lens

An optic that always provides one focus and updates it using the original source.

Package: `lucida` · [API index](../index.md) · [Source](../../../core/src/first_class.cj)

```cangjie
public struct Lens<S, A> {
    public Lens(
        public let view: (S) -> A,
        public let update: (S, A) -> S
    ) {}
}
```

## Members

| Member | Description |
|---|---|
| `Lens(view, update)` | Construct an optic from two function values |
| `view(source)` | Return the focus |
| `update(source, replacement)` | Return a source containing the replacement focus |

## Semantics

`S` is the source type and `A` is the focus type. `update` preserves these
types. The caller supplies the functions; the constructor does not validate
their behavior or prevent mutation. A field lens should preserve unrelated
fields when it reconstructs the source.

## Example

Inside a function, after `import lucida.*`:

```cangjie
let first = Lens<(Int64, String), Int64>(
    { pair => pair[0] },
    { pair, replacement => (replacement, pair[1]) }
)
let value = first.view((7, "Ada"))       // 7
let changed = first.update((7, "Ada"), 9) // (9, "Ada")
```

## Laws

For source `s` and focus values `a` and `b`:

```text
update(s, view(s)) = s
view(update(s, a)) = a
update(update(s, a), b) = update(s, b)
```

These laws assume stable functions without side effects and equality of the
relevant values. They are contracts for the supplied functions, not compiler
checks. The last law concerns repeated updates to the same focus.

See also: [`@Lens`](../macros/lens.md), [`Affine`](affine.md),
[Composition](../composition.md).
