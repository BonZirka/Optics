# Optic values

The core package exposes five structs. Each stores function values as public
members. `S` is the source type and `A` is the focus type; updates retain both
types.

| Type | Constructor arguments and public members |
|---|---|
| [`Lens<S, A>`](../api/structs/lens.md) | `view: (S) -> A`, `update: (S, A) -> S` |
| [`Affine<S, A>`](../api/structs/affine.md) | `preview: (S) -> Option<A>`, `update: (S, A) -> S` |
| [`Iso<S, A>`](../api/structs/iso.md) | `to: (S) -> A`, `from: (A) -> S` |
| [`Prism<S, A>`](../api/structs/prism.md) | `preview: (S) -> Option<A>`, `build: (A) -> S` |
| [`Setter<S, A>`](../api/structs/setter.md) | `modify: (S, (A) -> A) -> S` |

The declarations are in [`first_class.cj`](../../core/src/first_class.cj).
Call a member as an ordinary function value. There is no runtime validation
of the functions passed to a constructor.

## Construct directly

Using the `Address` record from [Getting started](../getting-started.md):

```cangjie
let city = Lens<Address, String>(
    { address: Address => address.city },
    { address: Address, value: String => Address(value, address.zip) }
)
let address = Address("London", 10001)
let changed = city.update(address, "Oslo")
```

For a partial optic, match the result of `preview` against `Some` and `None`.
A prism's `build` creates a source from its argument; it does not test an old
source. An affine's `update` receives the old source and should preserve it
when the optic does not match.

## Construct from a path

```cangjie
let city = @f(@ty(Address).city)
let sameKind = @f(@typeof(address).city)
```

Both are lenses. `@ty` supplies a source type directly; `@typeof` supplies it
through an expression. The expression in `@typeof` is used as a type witness,
not as a source to read or update.

A named optic value can appear in another path:

```cangjie
let personCity = @f(@ty(Person).address.@use(city))
let changedPerson = personCity.update(person, "Oslo")
```

The types at adjacent slots must agree. [Composition](../api/composition.md)
gives the result kind for each pair.

## Setters

A setter accepts a modifying function rather than a replacement value. For
example, a lens can be used to construct a setter:

```cangjie
let citySetter = Setter<Address, String>(
    { address: Address, change: (String) -> String =>
        city.update(address, change(city.view(address)))
    }
)
let changed = citySetter.modify(address, { _: String => "Oslo" })
```

`modifyId` is a convenience property. It calls `modify` with the identity
function `{ value => value }`. For an ordinary lawful setter, that leaves
the source unchanged. It does not expose a focus-reading operation.

## Preset replacements

A path starting from a type or optic value and ending in `<-` constructs a
setter with a preset replacement. Calling its `modifyId` performs that
replacement; `modify` applies a function to the preset value. See
[`Setter`](../api/structs/setter.md#preset-replacements-from-the-dsl) for the complete
example and its distinct identity behavior.

## Contracts by kind

The functions supplied to an optic must satisfy its behavioral contract.
The compiler checks their signatures, not their laws:

- [`Lens`](../api/structs/lens.md#laws): read and update the same focus consistently.
- [`Affine`](../api/structs/affine.md#laws): obey the lens rules on a match and preserve a miss.
- [`Prism`](../api/structs/prism.md#laws): preview and build must agree on matching sources.
- [`Iso`](../api/structs/iso.md#laws): the two conversions must be inverses.
- [`Setter`](../api/structs/setter.md#laws): ordinary modifiers preserve identity and composition.

See the [API index](../api/index.md) for declarations and member signatures, and
[API boundaries](../api/internals.md) for the generated adapters.
