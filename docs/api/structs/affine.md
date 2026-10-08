# Affine

An optic whose focus may be absent and whose update receives the original source.

Package: `lucida` · [API index](../index.md) · [Source](../../../core/src/first_class.cj)

```cangjie
public struct Affine<S, A> {
    public Affine(
        public let preview: (S) -> Option<A>,
        public let update: (S, A) -> S
    ) {}
}
```

## Members

| Member | Description |
|---|---|
| `Affine(preview, update)` | Construct an optic from two function values |
| `preview(source)` | Return `Some(focus)` on a match, or `None` on a miss |
| `update(source, replacement)` | Update a matching source; preserve it on a miss |

## Semantics

The supplied `update` function is responsible for preserving a source that
has no focus. Constructing an `Affine` does not wrap the function in a match
check. `S` and `A` remain the same after an update.

## Example

Inside a function, after `import lucida.*`:

```cangjie
let present = Affine<Option<Int64>, Int64>(
    { source => source },
    { source, replacement =>
        if (source.isSome()) { Some(replacement) } else { source }
    }
)
let found = present.preview(Some(7)) // Some(7)
let missed = present.update(Option<Int64>.None, 9) // None
```

This is a manually constructed optic. The standard slots do not currently
provide an `Option` unwrapping operation.

## Laws

For a matching source, the [lens laws](lens.md#laws) apply with `preview`
returning `Some`. An update should keep the source in the optic's match
domain. On a miss, `update(source, replacement) = source`.

These laws assume stable functions without side effects. A predicate selection
can cease matching after an update changes the selected value; its domain
needs additional restrictions to satisfy the laws.

See also: [`@Affine`](../macros/affine.md), [`Prism`](prism.md).
