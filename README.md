# Lucida

Lucida is a Cangjie library for reading and updating nested data. An update
returns a rebuilt value, so callers can keep the original.

```cangjie
package example

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

main() {
    let person = Person("Ada", Address("London", 10001))
    let moved = @f(person.address.city <- "Oslo")

    println(moved.address.city)  // Oslo
    println(person.address.city) // London
}
```

The expression after `@f` describes a path through the data. Lucida generates
the code that follows that path and rebuilds its enclosing values. This is
useful when an update crosses several records, an enum case, or an array
selection and the rest of the value should be preserved.

The library represents these paths with **optics**: operations that describe
how to read a value and how to put a replacement back into its source. You can
use the path syntax directly or keep an optic in a variable and pass it to
other functions.

## Start here

- [Getting started](docs/getting-started.md): dependencies, a complete program,
  and build commands.
- [Understanding optics](docs/introduction-to-optics.md): the model, explained
  using ordinary Cangjie functions.
- [API reference](docs/api/index.md): declarations, members, and behavior of
  each optic type, macro, and standard slot.
- [Documentation index](docs/README.md): examples, reference, and implementation
  notes.

## What is supported

`@DeriveOptics` supplies field optics for records, case optics for enums, and
conversions for records with one constructor field. `@Optic` and its kind
aliases declare custom operations. The `lucida_stdlib` package supplies array
index and predicate selections. Tuple element optics cover arities 2 through 16.

The `@f` syntax supports reads, replacements, blocks of several updates, and
composition with optic values. Use `.` for a total slot and `?.` for a
slot that may not find a value. A partial read returns `Option`; a partial
update preserves the source on a miss.

An update does not deep-copy the entire object graph. Derived optics rebuild
records along the path and retain the other fields. Custom optics supply their
own functions and must preserve the behavior they claim to implement.

## Project status

The workspace contains `core` (`lucida` and `lucida.macrodsl`), `stdlib`
(`lucida_stdlib`), and `tests`. `examples` is a separate consumer project.

After loading the Cangjie SDK environment, run:

```sh
./scripts/check.sh
```

The gate builds the workspace and example consumer, runs the law and feature
tests, compares generated benchmark expressions, and checks expected compiler
diagnostics. See [development](docs/development.md) for setup and failure logs.

The current implementation has limits, including unsupported `where` clauses
in optic declarations and no built-in optic for unwrapping `Option` fields.
[Benchmarks](docs/benchmarks.md) record the cost of generated updates; fusion
does not imply that an update costs the same as handwritten reconstruction.

The supported application surface is the five optic types, the documented DSL
and declaration macros, and the standard optics. Generated names and registry
helpers are implementation details, even where they are publicly visible.
See [API boundaries](docs/api/internals.md) and the [changelog](CHANGELOG.md).

Licensed under [MIT](LICENSE).
