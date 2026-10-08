# Fields and lenses

A lens reads one value and replaces it while retaining its surroundings.
For a constructor field, `@DeriveOptics` generates those operations.

The snippets below use these declarations and imports:

```cangjie
import lucida.*
import lucida.macrodsl.*

@DeriveOptics
public struct Address {
    public Address(public let city: String, public let zip: Int64) {}
}

@DeriveOptics
public struct Person {
    public Person(public let name: String, public let address: Address) {}
}
```

## Read and replace a field

Inside a function:

```cangjie
let person = Person("Ada", Address("London", 10001))
let name = @f(person.name)
let renamed = @f(person.name <- "Adele")
```

`name` is a `String`. `renamed` is a `Person` whose address is taken from
`person` and whose name is `"Adele"`. The original person's name remains
`"Ada"`.

For an ordinary field read, `person.name` is simpler and has the same result.
Use `@f` when you need its update or composition operations.

## Reach a nested field

```cangjie
let moved = @f(person.address.city <- "Oslo")
```

The generated operations reconstruct an address with the new city, then a
person with that address. The person's name and the address's zip code are
preserved.

The replacement must have the focus type. Replacing `city` with an integer
is a type error. The result keeps the source type; this API does not change
a record's generic type parameters during an update.

## Keep a lens as a value

```cangjie
let city = @f(@ty(Person).address.city)
let currentCity = city.view(person)
let movedAgain = city.update(person, "Rome")
```

`city` has type `Lens<Person, String>`. `@ty(Person)` starts with a type, so
`@f` constructs an optic rather than applying it to a person.

A function can accept that lens:

```cangjie
func replaceText<S>(source: S, field: Lens<S, String>, text: String): S {
    field.update(source, text)
}
```

Calling `replaceText(person, city, "Oslo")` uses the supplied field operation
to rebuild the person. The function does not need the `Person` declaration.

## Write your own lens

A lens can also be constructed directly:

```cangjie
let city = Lens<Address, String>(
    { address: Address => address.city },
    { address: Address, value: String => Address(value, address.zip) }
)
```

This produces an optic value. To register an operation under a name used in
path syntax, use an [optic declaration](user-optics.md).

See [`Lens`](../api/structs/lens.md#laws) for the lens laws and
[composition](../api/composition.md) for combining lenses with other kinds.
