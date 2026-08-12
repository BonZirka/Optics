# Lenses

A lens is a total focus on one field of a struct — a part that is *always*
there. It is the simplest optic: one operator (`.`), a read that cannot miss,
and a write that returns a new whole with one spot replaced.

All the code below runs against one sample value from the test suite:

```cangjie
func sampleOrder(): Order {
    Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
}
```

In the tests, `let o = sampleOrder()` pins that value: an `Order` has an `id`
and a `customer`; the customer has a `name` and an `address`; the address has
a `city`; the city has a `name` and a `zip`. Every field is a public `let` on
a struct derived with `@DeriveOptics`, so every step of a chain is a lens —
and `.` is the only operator you will need.

## Reading

Four levels down sits the customer's city name. One expression reads it:

```cangjie
@Assert(@f(o.customer.address.city.name) == "Atlanta")
```

`@f(...)` evaluates the focus: it walks the chain and evaluates to the
value at the end — `"Atlanta"` here. Every segment is a field that is always
there, so the read cannot miss: no `if`, no default, nothing to check.

Any other leaf of the same order reads the same way:

```cangjie
@Assert(@f(o.customer.address.city.zip) == 30301)
@Assert(@f(o.id) == 1)
```

## Writing

The write form replaces the focus and returns the new whole:

```cangjie
let updated = @f(o.customer.address.city.name <- "Denver")
@Assert(updated.customer.address.city.name == "Denver")
@Assert(o.customer.address.city.name == "Atlanta")
```

`@f(<chain> <- <newValue>)` builds a *new* `Order` in which exactly one
leaf differs — everything else is carried over for you: `updated.id` is still
`1`, `updated.customer.name` is still `"Ada"`, the zip is still `30301`. The
last assertion is the one to internalize: `updated` says `"Denver"`, the
original still says `"Atlanta"`. Nothing mutates.

Any leaf can be the target — same syntax, same guarantee. From another order
in the same suite:

```cangjie
let holder = Order(3, Customer("x", Address(City("y", 1))))
let renamed = @f(holder.customer.name <- "y")
@Assert(renamed.customer.name == "y")
```

## Chaining

A deep chain is a single optic — one expression from source to leaf, not
several optics you glue together yourself. The way to see it is a round trip:
read the focus, write back what you read, and check that nothing changed.

```cangjie
let current = @f(o.customer.address.city.zip)
let rewritten = @f(o.customer.address.city.zip <- current)
let once = @f(o.id <- 42)
let twice = @f(once.id <- 42)
```

The suite compares results leaf by leaf (`ordersEqualLeafwise`): `rewritten`
equals `o`, and `twice` equals `once` — setting the same value twice is the
same as setting it once. Reading and writing through the same chain are
inverses of each other; the round trip shows the chain you read with and the
chain you write with agree — one optic.

## Gotchas

> **Gotcha:** Lens writes always rebuild — even over `class` (reference)
> types, `@f` returns a new object. Nothing mutates. If you need mutable
> update, optics for this DSL are not the tool.

## Where to go next

- [Introduction to optics](../introduction-to-optics.md) — where the lens
  sits among prisms, affines, isos and setters, and why.
- [The DSL reference](../api/dsl.md) — every `@f` form on one page.
- Next example: [prisms](prisms.md) — for parts that may not be there.
