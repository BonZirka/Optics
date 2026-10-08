# Longer paths and blocks

A path can combine record fields, enum cases, array selections, and custom
optics. Each slot starts from the value selected by the preceding slot.

These snippets use the `Person` and `Address` declarations from
[Getting started](../getting-started.md), with all three imports shown there.

## Select an array element

```cangjie
let people = [
    Person("Ada", Address("London", 10001)),
    Person("Bo", Address("Paris", 20002))
]
let moved = @f(people?.at(1).address.city <- "Rome")
```

`at(1)` is partial because the index may not exist. The address and city
fields are total once a person has been selected. On a miss, the whole
update preserves the original array.

`at` checks the index before writing and copies the array before replacement.
It does not mutate the input array. A negative index or an index past the end
is a miss.

## Select by a condition

```cangjie
let moved = @f(people?.selectFirst({ p: Person => p.name == "Bo" }).address.city <- "Rome")
```

`selectFirst` updates the first matching element. Later matches retain their
old values. If no element matches, the returned array has the same elements
as the source.

Use a predicate whose result is stable and has no side effects. The current
implementation may evaluate it during both selection and reconstruction;
the number of predicate calls is not a useful application contract.

## Read or update several fields

A block lists paths relative to one source:

```cangjie
let person = people[0]
let fields = @f(person.{ .name; .address.city })
let changed = @f(person.{ .name; .address.city } <- ("Adele", "Oslo"))
```

`fields` is a `(String, String)`. Replacement values follow the same order
as the block entries. A block with two or more entries requires a tuple
literal at the outer update level. A block with one entry returns or accepts
a single value.

Entries are separated by semicolons. Each entry starts with a field access,
including a tuple element such as `._0`.

## Group a shared path

```cangjie
let changed = @f(person.{ .address.{ .city; .zip }; .name } <- (("Oslo", 30003), "Adele"))
```

The nested block reads `address` once, changes both of its fields, and then
rebuilds the person. Its target has the same nesting as the block. A read of
this block returns `((String, Int64), String)`.

Flat entries can also share a field prefix, as in `.address.city` and
`.address.zip`. Nested blocks make the shared traversal explicit. Do not
list the same field path twice; the parser rejects duplicate paths.

## Update a selected element with a block

```cangjie
let changed = @f(people?.at(0).{ .name; .address.city } <- ("Adele", "Oslo"))
```

The block runs only when the final anchor slot, `at(0)`, finds an element.
A read at the same anchor returns an `Option` containing the block result.

Blocks have a narrower supported shape than ordinary chains. They need a
value source, and a partial slot in the anchor should be its final
slot. To update several fields below that selection, place the remaining
paths inside the block, as above. See [block syntax](../api/macros/f.md#blocks).

## Reuse an optic in a path

```cangjie
let address = @f(@ty(Person).address)
let changed = @f(person.@use(address).city <- "Oslo")
```

`@use` inserts an existing optic value. In this example the value is a lens
from `Person` to `Address`, so `.city` continues from an address. The macro
expects an optic identifier; bind a computed optic to a variable first.

[Optic values](optic-values.md) covers construction and direct use.
[The syntax reference](../api/macros/f.md) covers all source forms and the
`[unfuse]` modifier.
