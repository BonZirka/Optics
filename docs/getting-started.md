# Getting Started

One complete, runnable program gets you from zero to nested immutable updates.
Save the file, build it with `cjpm build -i`, and run it.

## A runnable example

```cangjie
package getting_started

import lucida.*
import lucida_macro.*
import lucida.stdlib.*

@DeriveOptics
public struct Address {
    public Address(public let street: String, public let zip: Int64) { }
}

@DeriveOptics
public struct Employee {
    public Employee(public let name: String, public let salary: Int64, public let address: Address) { }
}

@DeriveOptics
public struct Company {
    public Company(public let name: String, public let employees: Array<Employee>) { }
}

main() {
    let co = Company(
        "Acme",
        [
            Employee("Ada", 100000, Address("1 High St", 10001)),
            Employee("Bob", 80000, Address("2 High St", 10002)),
        ],
    )
    let ada = co.employees[0]

    // One expression reaching several levels deep (all lenses — always present).
    println(@f(ada.address.street))    // res: 1 High St

    // Update the first employee's salary; the array is untouched otherwise.
    let raised = @f(co.employees?.at(0).salary <- 120000)
    println(raised.employees[0].salary)     // res: 120000
    println(co.employees[0].salary)         // res: 100000

    // selectFirst updates only the matching element.
    let moved = @f(co.employees?.selectFirst({ e: Employee => e.name == "Bob" }).address.zip <- 20002)
    println(moved.employees[1].address.zip) // res: 20002
    println(moved.employees[0].address.zip) // res: 10001
}
```

## What's happening

**Deriving.** `@DeriveOptics` registers optics for each public `let` field of a
struct, so `Employee` gets optics for `name`, `salary`, and `address` — and
`Address` for `street` and `zip`.

**Reading.** `@f(ada.address.street)` walks the chain `ada.address.street`
and evaluates to the value:

```
// res: 1 High St
```

**Writing.** `@f(<chain> <- <newValue>)` returns a *new* value with the
focused part replaced. The array updates show two ways to aim a chain:

- `co.employees?.at(0).salary <- 120000` — the first element's salary:
  `res: 120000` on the result, `res: 100000` on the original.
- `co.employees?.selectFirst({ e => e.name == "Bob" }).address.zip <- 20002` —
  only the matching element changes; `co.employees[0]` is untouched.

**The whole point:** nothing ever mutates. Each update builds a new `Company`
from the old one; `co` keeps its original values throughout. Precisely because
updates are immutable, updating nested data is safe and easy — the parts you
didn't touch are carried over for you.

## Next steps

- [Introduction to optics](introduction-to-optics.md) — why lenses, prisms, and
  friends exist, and the ideas behind the examples.
- Then the examples in order: [lenses](examples/lenses.md),
  [prisms](examples/prisms.md), [chains](examples/chains.md),
  [deriving](examples/deriving.md), [user optics](examples/user-optics.md).

---

Curious what `@f` expands to? It is a compile-time macro. See
[registry plumbing](architecture/registry-plumbing.md) for the internals — not
required reading to use the library.