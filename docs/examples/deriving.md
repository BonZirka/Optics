# Deriving optics

Every struct, class or enum the last three examples walked was derived first:
the `Order` and its `Customer`, `Address` and `City` on the
[lenses](lenses.md) page, the `Shape` enum on the [prisms](prisms.md) page,
`Employee2` and `Meters` on the [chains](chains.md) page. This page is about
the derive itself. `@DeriveOptics` applied to a `struct`, `class` or `enum`
emits the plumbing behind `@Lucida` for that type — a lens per constructor
field, an affine per single-payload case, and, for one-field structs and
classes, an iso — so that chains can walk its fields and cases.

What the derive emits decides what you can focus, so its rules are worth
knowing: which declarations qualify, how visibility carries over, how generic
parameters flow through, and which shapes are rejected outright.

## Structs and classes

The fixture chain starts with a two-field struct:

```cangjie
@DeriveOptics
public struct City {
    public City(public let name: String, public let zip: Int64) { }
}
```

The derive sits on the declaration; nothing else about the type changes. That
one derive is why chains ending on a city work — the same fixture the
[lenses](lenses.md) page pins:

```cangjie
let o = sampleOrder()
@Assert(@Lucida(o.customer.address.city.name) == "Atlanta")
@Assert(@Lucida(o.customer.address.city.zip) == 30301)
```

(`sampleOrder` builds the whole `Order`; every type on the way down is derived
the same way.) The tail of that chain rides on lenses the `City` derive
emitted. The rules it follows:

- **Every `let`/`var` constructor field becomes a lens**, named after the
  field — `name` and `zip` here. A constructor parameter that is not a field
  is rejected: `Primary constructor should contain only field declarations`.
  Plain parameters cannot ride along.
- **Visibility mirrors the field.** `public let name` gets a public lens; a
  field with no access modifier gets one visible to the package; `private`
  fields are rejected:
  `Primary constructor should contain only non-private field declarations`.
- **A primary constructor is required** — it is where the fields come from.
  Deriving a type without one fails:
  `Primary constructor should be specified`.

A `class` derives the same way — the derive accepts `struct`, `class` and
`enum` declarations, and nothing else. Over a class, a lens write still
returns a new object rather than mutating (the [lenses](lenses.md) gotcha).

## Enums

The [prisms](prisms.md) page read and wrote a derived enum through `?.`.
Here is that derive:

```cangjie
@DeriveOptics
public enum Shape {
    | Circle(Nested)
    | Square(Int64)
}
```

`Nested` is a one-field struct whose single field is `n`. One derive, one
optic per case: every single-payload case gets an *affine* — the partial kind
whose read can miss and whose write returns the source untouched on a miss
(the miss is an identity). That is the optic a chain marks with `?.`:
`Circle` gets one focusing its `Nested` payload, `Square` one focusing its
`Int64`, and the case name is the segment name — `c?.Circle`. The
[introduction](../introduction-to-optics.md) casts the kind; the
[prisms](prisms.md) page walks both sides of it.

The derive is strict about case shape, and says so — an unsuitable case is an
error at derive time, never a silently skipped case:

- a case with no payload fails with `@DeriveOptics: enum case 'X' has no associated value; only single-payload cases are supported` (hint: `Give the case exactly one associated value, or hand-write its prism`)
- a case with several payloads fails with `@DeriveOptics: enum case 'X' has N associated values; only single-payload cases are supported` (hint: `Bundle the values into one struct and derive optics for that struct`)

`X` is the case's name and `N` the payload count. The hints are the fix: give
the case exactly one value, or bundle several into a struct and derive that
struct — the bundle's fields get lenses, so the chain continues into them.

## Generics

A generic type derives like a plain one:

```cangjie
@DeriveOptics
public struct GBox<T> {
    public GBox(public let v: T) { }
}
```

One derive covers every instantiation: the parameter propagates to the
emitted `extend <T>` blocks, so the lens for `v` exists for a `GBox<Int64>`
as readily as for a `GBox<String>`:

```cangjie
let b = GBox<Int64>(5)
@Assert(@Lucida(b.v) == 5)
```

The write is the usual lens write — a new `GBox`, nothing mutates:

```cangjie
let updated = @Lucida(b.v <- 7)
@Assert(updated.v == 7)
@Assert(b.v == 5)
```

What the derive will not take is a constraint: a `where` clause on the type
is rejected with `@DeriveOptics: generic constraints ('where' clauses) are not supported yet` (hint: `Remove the constraint or hand-write the optics`).

## Single-field types get isos

A struct or class with exactly one field is a wrapper — `Meters` and the
`Int64` inside it are the same information in different clothes. The derive
recognizes the shape and, alongside the `v` lens, emits an *iso*: the pair of
total conversions between wrapper and payload.

```cangjie
@DeriveOptics
public struct Meters {
    public Meters(public let v: Int64) { }
}
```

That iso is what `coerce<T>()` resolves against — the total segment that
unwraps the wrapper mid-chain (see
[coerce segments](chains.md#coerce-segments)):

```cangjie
let m = Meters(7)
let unwrapped = @Lucida(m.coerce<Int64>())
@Assert(unwrapped == 7)
```

Total means no `Option` and no miss, hence `.` — and `T` must be the field
type: the coerce resolves against exactly the pair the derive produced.
(`GBox<T>` above is a one-field type too, so it gets an iso as well — the
lens for `v` first, the iso alongside.)

## Gotchas

> **Gotcha:** Derived members are `__`-prefixed and are not part of the
> public API. A field you did not mark public does not get an exported optic.

## Where to go next

- [Introduction to optics](../introduction-to-optics.md) — the cast of kinds
  this page named: which are total, which can miss.
- [Lenses](lenses.md), [prisms](prisms.md) and [chains](chains.md) — the
  derived optics in action, one page each.
- [The DSL reference](../api/dsl.md) — every `@Lucida` form on one page.
- Next example: [user optics](user-optics.md) — bringing your own segments,
  marked `.` or `?.`.
