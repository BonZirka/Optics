# Declaring custom optics

Use `@Optic` when a path needs an operation that is not an ordinary derived
field or case. A declaration gives the operation a name, types, and read and
rebuild functions. It registers a slot for `@f`; it does not create an
optic variable or an ordinary instance method.

Import `lucida.*` and `lucida.macrodsl.*` in the declaring package.

## Declare a lens

This example uses a record without `@DeriveOptics`:

```cangjie
public struct Account {
    public Account(public let label: String, public let balance: Int64) {}
}

@Lens[
    source: Account,
    focus: Int64,
    forward: { source.balance },
    backward: { Account(source.label, focus) }
]
struct funds {}
```

Inside a function:

```cangjie
let account = Account("Savings", 100)
let amount = @f(account.funds())
let changed = @f(account.funds() <- 150)
let fundsLens = @f(@ty(Account).funds())
```

The carrier `struct funds {}` supplies the slot name. It must be empty;
the macro consumes it and emits the registration declarations. You do not
instantiate `funds`.

`@Lens[...]` is shorthand for `@Optic[kind: Lens, ...]`. The other aliases
are `@Affine`, `@Prism`, and `@Iso`. An alias already fixes the kind, so it
rejects an additional `kind:` field. There is no `@Setter` declaration alias;
a setter can be constructed as a value using `Setter<S, A>`.

## Choose the function shapes

| Kind | `forward` receives and returns | `backward` receives and returns |
|---|---|---|
| Lens | `source: S` → `A` | `source: S`, `focus: A` → `S` |
| Affine | `source: S` → `Option<A>` | `source: S`, `focus: A` → `S` |
| Prism | `source: S` → `Option<A>` | `focus: A` → `S` |
| Iso | `source: S` → `A` | `focus: A` → `S` |

A lens or affine needs the old source during reconstruction. A prism or iso
reconstructs from the focus alone. Choose the kind according to that behavior,
not according to which operator spelling you would prefer at the call site.

## Declare a partial selection

The following affine selects the first array element:

```cangjie
@Affine[
    source: Array<T>,
    focus: T,
    forward: { source.get(0) },
    backward: {
        if (source.size == 0) {
            source
        } else {
            let changed = source.clone()
            changed[0] = focus
            changed
        }
    }
]
struct firstItem<T> {}
```

```cangjie
let numbers = [10, 20]
let first = @f(numbers?.firstItem())
let changed = @f(numbers?.firstItem() <- 30)
```

`first` is `Some(10)`. The update returns an array containing `30, 20`.
The backward function explicitly handles an empty source and copies before
writing. An optic's kind does not make an arbitrary user function immutable.

## Declare a prism

A prism can represent a case of an enum declared elsewhere:

```cangjie
public enum Message {
    | Empty
    | Text(String)
}

@Prism[
    source: Message,
    focus: String,
    forward: {
        match (source) {
            case Text(value) => Some(value)
            case Empty => Option<String>.None
        }
    },
    backward: { Message.Text(focus) }
]
struct textValue {}
```

Use `message?.textValue()` to read or attempt an update. A partial DSL update
preserves `Message.Empty`. If you construct an optic with
`@f(@ty(Message)?.textValue())`, its `build` member can construct a `Text`
without an existing message.

## Add parameters

`args:` declares parameters available to both bodies:

```cangjie
@Lens[
    source: Int64,
    focus: Int64,
    args: (offset: Int64),
    forward: { source + offset },
    backward: { focus - offset }
]
struct shifted {}
```

A call such as `@f(number.shifted(10))` supplies `offset`. This example is
intended for values where the arithmetic does not overflow. Real custom
optics must account for the valid domain of their conversions.

`source`, `focus`, and `_source` are reserved argument names. Arguments use
the declared Cangjie types and ordinary call syntax.

## Name the body parameters explicitly

Bare bodies use the fixed names `source` and `focus`. A body can instead name
its parameters positionally:

```cangjie
@Lens[
    source: Account,
    focus: Int64,
    forward: { account => account.balance },
    backward: { account, amount => Account(account.label, amount) }
]
struct balanceValue {}
```

A forward body has one parameter. A lens or affine backward has two; a prism
or iso backward has one, representing the focus. Use `_` for an unused
parameter. These names replace the fixed names within that body.

## Generics and naming

Declare type parameters on the carrier, as in `firstItem<T>`. Concrete types
inside `source:` or `focus:` remain concrete. Call sites infer the carrier's
parameters from the source; generated members do not accept explicit
method-level type arguments. `where` clauses on carriers are unsupported.

The same slot name can be declared for different source types in one
package. Generated interface names include the declaration's signature, but
dispatch members still use the slot name. Two declarations with the same
name and source may therefore collide, even if their kind or arguments differ.
These collisions can appear as compiler errors in generated members.

## Validate behavior

Check successful reads and updates, misses, preservation of unrelated fields,
and the [laws for the chosen kind](../api/index.md#structs).
Use a real discriminated union or wrapper to demonstrate a lawful prism or
iso; arbitrary conversion functions need not satisfy their round-trip laws.

The standard array operations are implemented with the same mechanism in
[`stdlib/src/impls.cj`](../../stdlib/src/impls.cj).
