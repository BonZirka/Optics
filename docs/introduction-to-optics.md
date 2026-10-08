# Understanding optics

An optic describes access to a value within another value. It includes the
operation needed to put an updated value back into its surroundings.

This chapter develops that idea using ordinary functions before introducing
the different optic types. The words **source** and **focus** will be used
throughout: the source is the value you start with; the focus is the value an
optic gives you access to.

## Updating a nested record

Suppose a program uses these records:

```cangjie
@DeriveOptics
public struct Address {
    public Address(public let city: String, public let zip: Int64) {}
}

@DeriveOptics
public struct Person {
    public Person(public let name: String, public let address: Address) {}
}
```

The annotations can be ignored for the moment. To move someone to another
city while preserving the original record, a function can rebuild the two
records explicitly:

```cangjie
func moveTo(person: Person, city: String): Person {
    Person(person.name, Address(city, person.address.zip))
}
```

This is a reasonable solution for one update. It also shows what must be
repeated when several operations reach into the same records: each update
must know how to rebuild every enclosing value and which fields to retain.
A constructor change can require changes in several such functions.

Lucida lets the type declaration supply the field operations once. The
corresponding update is:

```cangjie
let moved = @f(person.address.city <- "Oslo")
```

Use whichever form is clearer for the program. Explicit reconstruction is
often sufficient for a small record. Optics are useful when paths are reused,
passed to other functions, or extended through selections and enum cases.

## A field needs two operations

Access to `Address.city` can be written as two functions:

```cangjie
func readCity(address: Address): String {
    address.city
}

func replaceCity(address: Address, city: String): Address {
    Address(city, address.zip)
}
```

The replacement function needs the old address because the city alone does
not tell it which zip code to retain.

A **lens** stores these two operations together. `Lens<S, A>` uses `S` for
the source type and `A` for the focus type:

```cangjie
let cityLens = Lens<Address, String>(readCity, replaceCity)
let city = cityLens.view(address)
let changed = cityLens.update(address, "Oslo")
```

You can pass `cityLens` to a function that accepts a `Lens<Address, String>`.
The receiving function can read and replace a string without knowing which
address field the lens selects.

## Combining two lenses

A lens from `Person` to `Address` can be combined with a lens from `Address`
to `String`. Reading the combined lens first reads the address, then the city.
Updating it replaces the city in the address, then replaces the address in
the person.

The types line up like this:

```text
Person  ->  Address  ->  String
  source    intermediate    focus
```

This operation is called **composition**. The intermediate type must match:
an optic that produces an address can be followed by one that expects an
address.

The path `person.address.city` expresses this composition. To keep the path
as an optic value, start it with a type instead of a source value:

```cangjie
let personCity = @f(@ty(Person).address.city)
let moved = personCity.update(person, "Oslo")
```

`@DeriveOptics` supplies the field operations, and `@f` combines them.

## Access that can fail

An array index may be out of bounds. An enum value may belong to another
case. These operations cannot always return a focus, so their read operation
returns `Option<A>`.

```cangjie
let name = @f(people?.at(3).name)
```

The result is `Some(name)` when element 3 exists and `None` otherwise. The
`?.` marks the partial `at` slot; the following `.name` is an ordinary
field access on a successfully selected person.

For an update, there is a natural behavior on a miss:

```cangjie
let changed = @f(people?.at(3).name <- "Ada")
```

If element 3 does not exist, the result preserves `people`. A successful
update returns an array with that element replaced. The expression always
has the array's type.

An **affine** combines a partial read with a replacement operation that uses
the original source. `Array.at` is an affine because the replacement must
preserve the other elements.

## Rebuilding without the old source

Some conversions can reconstruct a source from the focus alone. For a
one-field wrapper such as `Meters(Int64)`, the two directions can unwrap and
wrap the number. This is an **iso**, short for isomorphism, when the two
functions undo one another.

A **prism** has a partial read and a reconstruction function that also needs
only the focus. For an enum case `Message.Text(String)`, a prism can try to
extract a string, and can construct a `Text` from any string. Constructing a
`Text` does not require an existing `Message`.

Construction and updating an existing source are different operations. Calling
a prism's `build` constructs its case unconditionally. A partial update in
`@f` checks for a match and preserves an unmatched source. Lucida's derived
enum case optics are affines: their `update` operation itself has this
preserve-on-miss behavior.

## The five types

| Type | Reading | Rebuilding or modifying |
|---|---|---|
| `Lens<S, A>` | Always produces `A` | Needs the old `S` and a replacement `A` |
| `Affine<S, A>` | Produces `Option<A>` | Needs the old `S`; an unmatched source is preserved |
| `Iso<S, A>` | Converts `S` to `A` | Converts `A` back to `S` |
| `Prism<S, A>` | Produces `Option<A>` | Constructs `S` from `A` |
| `Setter<S, A>` | Provides no focus-reading operation | Applies a function `(A) -> A` within `S` |

A setter is useful when a caller only needs to modify data. Its interface can
also describe modification of several values. Lucida does not currently
provide a separate traversal type for reading many focuses.

## The behavior functions must satisfy

The compiler checks function types. It cannot establish that a pair of
functions behaves like a lens. For a field lens, callers normally expect:

- Reading a field and writing that same value back leaves the source unchanged.
- Reading after a replacement returns the replacement.
- Replacing the same field twice has the same result as the final replacement.

The last rule concerns two writes to the same focus. It does not say that
arbitrary updates can be reordered. Each [optic type's reference page](api/index.md#structs)
states its laws more precisely.

Custom optics are responsible for these properties and for avoiding unwanted
mutation. Derived record optics reconstruct the path; they do not deep-copy
unrelated fields or make shared mutable objects immutable.

For practical examples, continue with [fields](examples/lenses.md),
[enum cases](examples/prisms.md), or [arrays and blocks](examples/chains.md).
