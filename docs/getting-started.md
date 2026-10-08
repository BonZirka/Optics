# Getting started

This guide builds a small program that changes a person's city while retaining
the original value. It then updates one person in an array. You need a Cangjie
SDK with `cjc` and `cjpm` available in your shell.

The commands and program were checked with Cangjie 1.0.0 on macOS arm64. This
is a verified setup, not a claim that every SDK version is compatible.

## Create a consumer project

Keep your checkout of this repository and the new project next to each other:

```text
workspace/
  Optics/
    core/
    stdlib/
  optics_guide/
    cjpm.toml
    src/
      main.cj
```

From `workspace`, create the source directory:

```sh
mkdir -p optics_guide/src
```

Save this as `optics_guide/cjpm.toml`:

```toml
[package]
name = "optics_guide"
version = "0.1.0"
cjc-version = "1.0.0"
output-type = "executable"
src-dir = "src"

[dependencies]
lucida = { path = "../Optics/core" }
lucida_stdlib = { path = "../Optics/stdlib" }
```

The paths point to the workspace members. `lucida` provides the optic types
and macros. `lucida_stdlib` adds the array selections used below.

## Write the program

Save this as `optics_guide/src/main.cj`:

```cangjie
package optics_guide

import lucida.*
import lucida.macrodsl.*
import lucida_stdlib.*

@DeriveOptics
public struct Address {
    public Address(public let city: String, public let zip: Int64) {}
}

@DeriveOptics
public struct Person {
    public Person(public let name: String, public let address: Address) {}
}

main() {
    let ada = Person("Ada", Address("London", 10001))

    let city = @f(ada.address.city)
    let moved = @f(ada.address.city <- "Oslo")
    println(city)
    println(moved.address.city)
    println(ada.address.city)

    let people = [ada, Person("Bo", Address("Paris", 20002))]
    let updated = @f(people?.at(1).address.city <- "Rome")
    println(updated[1].address.city)
    println(people[1].address.city)

    let missing = @f(people?.at(5).name)
    match (missing) {
        case Some(name) => println(name)
        case None => println("No person at index 5")
    }
}
```

Load your SDK environment using its installation instructions. For an SDK
that provides `envsetup.sh`, the commands have this form:

```sh
source /path/to/cangjie/envsetup.sh
cd optics_guide
cjpm build -i
cjpm run
```

Expected output:

```text
London
Oslo
London
Rome
Paris
No person at index 5
```

## Read the expressions

`@DeriveOptics` generates operations for the fields in each primary
constructor. Those operations tell `@f` how to read a field and how to
reconstruct its containing record with a replacement.

`@f(ada.address.city)` returns a `String`. For this read, ordinary
`ada.address.city` would also work. The optic syntax becomes useful when the
same path is used for an update or combined with a selection that can fail.

`@f(ada.address.city <- "Oslo")` returns a `Person`. It constructs the new
address and then a person containing that address. `<-` is syntax interpreted
by the macro; the expression does not assign to `ada`.

`people?.at(1)` selects an array element if the index is valid. The `?.`
marks `at` as a partial operation. `.address.city` continues through ordinary
fields after that selection succeeds. The array optic copies the array
before replacing the element.

A read through a partial slot returns `Option`. An update through a
partial slot returns the whole source type: on a miss, it preserves the
source. You therefore do not need to handle `None` merely to attempt an
update.

## Continue

[Understanding optics](introduction-to-optics.md) explains how reads and
reconstruction form a reusable operation. [Longer paths and blocks](examples/chains.md)
adds predicate selection and several updates in one expression. Keep the
[`@f` reference](api/macros/f.md) available when looking up a particular form.
