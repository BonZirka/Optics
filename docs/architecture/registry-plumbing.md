# Registry plumbing

The [macro system](macro-system.md) ends where the type checker begins. The
three macros are procedure macros: functions from tokens to tokens that run
before type checking, so they see tokens, not types — they cannot resolve
`o.customer` to a member, ask whether `Customer` has lenses, or decide which
kind a segment rides. Yet every one of those is a type-level decision, and
the emitted code has to be right about all of them before it can compile.
The bridge between the two is Cangjie's overload resolution: the macros emit
calls whose overload sets *are* the decisions, and the compiler makes the
decisions after the splice. The machinery those calls land on lives in one
file of the runtime package (`magical.cj`): six empty structs — the
registries — the one exchange the runtime itself ships, and the
`magic` entry points that mint a chain's first value; the macros emit the
rest onto these types.

Nothing in that file computes. The registries are phantom types: their type
parameters and their member lists are the entire content, and the values are
born and consumed within a single expansion, carrying no data. That is not a
compromise but the design. A decision the type checker must make has to be
encoded in types, and an empty struct is the cheapest carrier a type can
have — the *type* is the message; the value is only something for the
message to ride on.

This page covers the registries, the downcast exchange, why the matching is
done by the type system rather than the macros, and the entry points that
start a chain. What the macros emit on top of this machinery is
[the macro system](macro-system.md)'s subject; the fused walk that consumes
the bindings is the subject of [the fusion walk](fusion-walk.md), and the
composed path's table is [composition](../api/composition.md)'s.

## The registries

Six structs, one file (`magical.cj`), declared together — the currency
first, then the one exchange the runtime itself provides, then one registry
per optic kind:

```cangjie
public struct RegistryMagical<T> { }

public func __downcast_method_coerce<T, G>(_: RegistryMagical<T>, _: RegistryMagical<G>): RegistryIsos<T> {
    RegistryIsos()
}

public struct RegistryIsos<T>      {} // (a) -> b, (b) -> a
public struct RegistryLenses<T>    {} // (a) -> b, (a, b) -> a
public struct RegistryPrisms<T>    {} // (a) -> Option b, (b) -> a
public struct RegistryAffines<T>   {} // (a) -> Option b, (a, b) -> a
public struct RegistrySetters<T>   {} // (a) -> a, (a, (b) -> b) -> a
```

`RegistryMagical<T>` is the chain's currency. Every emitted member that lets
a chain *continue* lands on it: the suboptic accessors — `__<field>_optics`
from the derive, `__method_<name>_optics` from user optics and the stdlib —
which move the currency from one type's registry to the next, and the
downcasts of the next section, which exchange it for a kind registry. Its
type parameter is the type the walk is currently standing on, and the
emitted accessor calls keep that type moving in lockstep with the chain:
`magic0.__customer_optics(magic0)` returns `RegistryMagical<Customer>`
because the accessor was emitted on `RegistryMagical<Order>` and says so in
its return type.

The five kind registries host the optics themselves — the `impl` members
that carry the actual forward and backward functions. One per kind, with the
kind's source type as the type parameter; the trailing comments above are
the kinds' arity contracts, verbatim from the source. The [derive
emissions](macro-system.md#deriveoptics) land field lenses on
`RegistryLenses`, enum cases and stdlib segments on `RegistryAffines`, and
single-field iso pairs on `RegistryIsos`; a [user-declared
optic](macro-system.md#lucidaoptic) lands on the registry its `kind:` field
names.

The split between the two groups is the point. The currency exists because
the macro cannot know a segment's kind when it emits the call — it emits the
same `currMagical.__downcast(currMagical)` for every derived segment and
lets the receiver's type answer. The kind registries exist because so many
decisions key on the kind once it *is* known: which impl members may resolve
(a lens forward has no `Option` to unwrap; a prism's does), which row of the
[composition table](../api/composition.md#the-composition-table) answers a
compose call, which join `opticsUpcast` computes, and — on the fused path —
whether an operator mark is legal at all. A single registry per type would
host every kind's members in one namespace and make all of that invisible to
the checker; the kind has to be *in the type*, and that means one type per
kind.

`RegistrySetters<T>` completes the set without ever hosting a member.
Setters are not declarable
([macro-system](macro-system.md#lucidaoptic) explains why) — so the derive
emits none,
user optics cannot declare one, and the stdlib has none. The registry's
whole life is as a key: `magicFirstClassDowncast` hands a first-class
`Setter` there (below), and the generated [composition
overloads](../api/composition.md#upcasting) use it as the join type of
setter-involving pairs. The composed write itself dispatches on the
backward's function shape, not on the registry. The sixth struct exists so
the overload lattice has a row for every kind — uniformity of the table, not
a hosting need.

## The downcast

The walk holds a `RegistryMagical`; the impl members live on kind
registries. The downcast is the exchange — and it is more than a cast,
because its return type *is* the kind decision and its overload set *is*
the set of types the chain may continue through. The walk's emission never
spells a kind registry's name: every kind-registry value it holds is the
return of a downcast, and every currency value comes from `magic`, an
accessor's return, or a bridge — the registry types are decided by return
types, never by annotation.

Who emits what:

| Emitted by | Member | On | Returns |
|---|---|---|---|
| `@DeriveOptics`, struct or class | `__downcast` | `RegistryMagical<T>` | `RegistryLenses<T>` |
| `@DeriveOptics`, enum | `__downcast` | `RegistryMagical<T>` | `RegistryAffines<T>` |
| `@Optic` | `__downcast_method_<name>` | `RegistryMagical<S>` | the declared kind's registry |
| stdlib (`at`, `selectFirst`) | `__downcast_method_at`, `__downcast_method_selectFirst` | `RegistryMagical<Array<T>>` | `RegistryAffines<Array<T>>` |
| the runtime, for `coerce<T>()` | `__downcast_method_coerce` (free function) | takes two `RegistryMagical` | `RegistryIsos<T>` |

The per-type downcasts all follow one shape; the stdlib's pair
(`impls.cj`) shows the full interface-and-extend ceremony, typed for arrays
rather than a user type:

```cangjie
sealed interface __Stdlib_downcast<T> {
    // Array<T>.at(n)
    @Frozen
    func __downcast_method_at(_: RegistryMagical <Array<T>>): RegistryAffines<Array<T>>
    @Frozen
    func __downcast_method_selectFirst(_: RegistryMagical <Array<T>>): RegistryAffines<Array<T>>
}

extend <T> RegistryMagical<Array<T>> <: __Stdlib_downcast<T> {
    @Frozen
    public func __downcast_method_at(_: RegistryMagical <Array<T>>): RegistryAffines<Array<T>> {
        RegistryAffines()
    }
    @Frozen
    public func __downcast_method_selectFirst(_: RegistryMagical <Array<T>>): RegistryAffines<Array<T>> {
        RegistryAffines()
    }
}
```

The interface is the publishing channel — an extension member added by a
bare `extend` stays package-local, and the stdlib's registry extends must be
callable from the user's package ([the macro
system](macro-system.md#three-extend-blocks) explains the channel) — and the
sealed interface keeps user code from implementing it. The body is the same
everywhere: construct the kind registry, return it.

At the call site the walk passes the currency to its own downcast —
`let optics0 = magic0.__downcast(magic0)`, the same value twice. The
argument is redundant type-wise (the receiver already carries `T`), and it
is there for shape: the downcast and the impl members that take a registry
argument plus real arguments (`__method_at_impl_forward(_: RegistryMagical<Array<T>>, n: Int64)`) share one call shape. The derived lens impls are
the exception — plain members fetched bare (`optics0.__customer_impl_forward`),
no argument — which is exactly what makes the downcast's extra argument
redundant rather than necessary.

The coercion downcast is the odd one out: a free top-level function rather
than a member, declared once by the runtime rather than emitted per type.
Both differences follow from its job. It must exist for *every* pair
`<T, G>` before any user code is written — there is no macro invocation to
emit it for a specific type, so the library ships one generic function that
covers all pairs, and being a top-level public function it is visible from
every package without the interface channel per-type members need. And it
takes *two* witnesses, the leaving registry and the arriving one — the
arriving registry is minted by the explicit-type `magic<Target>()` (below)
and doubles as the next segment's currency. The impl members the exchange
fetches take both witnesses too, and the pair — not the registry alone — is
what resolves direction; the next section shows why that matters.

## Why the type system does the matching

The macro is syntactic, so it does not decide — it asks. Every registry
call it emits is a question posed to an overload set, and the member that
resolves is the answer. Consider what the composed expansion of
`@f(o.customer.name)` holds:

- `magic0` is bound by `magic({ => o })`, so its type is
  `RegistryMagical<Order>` — the anchor's type parameter came from the
  thunk's return type.
- `magic0.__downcast(magic0)` resolves against the members emitted on
  `RegistryMagical<Order>` — exactly one, the derive's, returning
  `RegistryLenses<Order>`. Had `Order` not derived anything, the member
  would not exist and the chain would fail to compile: the overload set of
  the downcast *is* the set of types the chain can enter.
- `optics0.__customer_impl_forward` resolves only because `optics0`'s type
  is `RegistryLenses<Order>` — the type the downcast returned. The kind
  commitment is the return type: from this binding, only lens members of
  `Order` are nameable. A prism member on the same source type lives on
  `RegistryPrisms<Order>`, which this binding cannot reach.

The same question-and-answer shape runs the composed path's table.
`__OpticsCompositions.composeForward` and `composeBackward` take their two
registries first, and one `@Frozen` overload pair per ordered kind pair —
twenty-five rows — is distinguished purely by those argument types.
`opticsUpcast` is the purest case: its twenty-five overloads each return a
fresh registry of the join kind, and [composition](../api/composition.md#upcasting)
says it outright — it computes a type, not a value.

The coercion exchange shows the trick under the most pressure, because
there the overload set can contain *two candidates for the same member name
on the same registry*. Deriving `Meters` over `Int64` emits the to-side iso
impl on `RegistryIsos<Int64>`; deriving a second wrapper over `Int64` —
say, `Seconds` — emits
another. Both extend the same type with `__method_coerce_impl_forward` —
only the phantom argument pair tells them apart. The emitted call passes
the leaving and arriving registries, `__optics0.__method_coerce_impl_forward(__magical0, __nmagic0)`, and the second argument's type —
`RegistryMagical<Meters>` versus `RegistryMagical<Seconds>` — selects the
direction. The registry alone (`RegistryIsos<Int64>`) is identical in both
candidates; the pair carries the from-and-to message. This is the registry
pattern's whole wager in one call: values say nothing, argument and return
types say everything.

It is useful to name the model: this is compile-time virtual dispatch. One
call site, many candidate members, resolved by type — like a vtable
dispatch, except the discriminator is a type parameter instead of a runtime
tag, and the vtable is an overload set instead of a table. The difference
in kind is that nothing is deferred: a segment whose members do not exist
fails at compile time, at the emitted call site, inside the expansion the
macro produced — which is why the failures are precise enough for
[diagnostics](../api/diagnostics.md) to collect.

The operator-mark gates are the same mechanism in its most user-visible
form. `__fwdApplyTotal`, `__fwdApplyPartial` and `__bwdApplyTotal` overload
over the kind registries, and each illegal mark–kind pair resolves only to
a strict-`@Deprecated` overload whose message is the diagnostic. How the
fused walk routes segments through those gates, and why the write side
gates asymmetrically, belong to [the fusion walk](fusion-walk.md); why the
diagnostic takes the form of an overload at all is [design
decisions](design-decisions.md)' subject. Even the composed write tail
resolves by shape rather than registry — `evalBackward`'s two overloads
pick the sourceful or sourceless backward by its function type — so the
pattern reaches every stage of the expansion.

The limits are the flip side of the static guarantee. Resolution sees only
types, so there is no runtime polymorphism here and no way to query the
machinery at runtime; a kind must have been emitted somewhere — derive,
user macro, stdlib, or the library itself — before a chain that uses it can
compile. And because the registry type is the whole message, two optics of
the same kind on the same source share one registry; they are told apart by
member name, never by type.

## Magic entry points

The registries' dispatch needs a first value to resolve against. The entry
points mint it (`magical.cj`, both `@Frozen`, since the emission addresses
them by exact name from other modules):

```cangjie
@Frozen
public func magic<T>(_: () -> T): RegistryMagical<T> {
    RegistryMagical()
}

@Frozen
public func magic<T>(): RegistryMagical<T> {
    RegistryMagical()
}
```

`magic<T>(thunk)` anchors a chain rooted at a value: the `@typeof` anchor
emits `magic({ => o })`, and the thunk's return type pins `T`. The
parameter is unnamed and unread — the lambda's *type* is the entire
payload. Passing the source expression as a thunk rather than a value keeps
a side-effecting expression from being evaluated just to pin the anchor:
the expansion applies the source afresh at the tail of the walk, so the
anchor binding must not evaluate it on the way. (The fused walk's pinning
helpers lean on the same thunk trick — [the fusion
walk](fusion-walk.md) covers them.) The bare `magic<T>()` serves the two
places the type is already explicit: the `@ty(T)` anchor, which names the
type and has no expression to infer from, and the coercion segment's
arriving registry, where the target type is equally explicit —
`magic<Target>()` mints the registry that `__downcast_method_coerce`
consumes and the next segment continues from.

A spliced first-class optic enters the same world through two bridges, one
overload per kind, both `@Frozen`:

```cangjie
@Frozen
public func magicFirstClassDowncast<S, A>(_: Lens<S, A>): RegistryLenses<S> { RegistryLenses<S>() }
@Frozen
public func magicFirstClassDowncast<S, A>(_: Prism<S, A>): RegistryPrisms<S> { RegistryPrisms<S>() }
@Frozen
public func magicFirstClassDowncast<S, A>(_: Iso<S, A>): RegistryIsos<S> { RegistryIsos<S>() }
@Frozen
public func magicFirstClassDowncast<S, A>(_: Affine<S, A>): RegistryAffines<S> { RegistryAffines<S>() }
@Frozen
public func magicFirstClassDowncast<S, A>(_: Setter<S, A>): RegistrySetters<S> { RegistrySetters<S>() }
```

```cangjie
@Frozen
public func magicFirstClass<S, A>(_: Lens<S, A>): RegistryMagical<A> { RegistryMagical<A>() }
// ... Prism, Iso, Affine, Setter — all returning RegistryMagical<A>
```

The two bridges answer two different questions about the same value, and
the difference between them is where each types the registry.
`magicFirstClassDowncast` asks *what kind is this, and what does it read
from* — its registry is typed at the optic's **source**, the witness the
compose and upcast rounds key on ([composition](../api/composition.md#calling-composeforward--composebackward)
documents it as the bridge the registry round is built on).
`magicFirstClass` asks *where does the chain continue* — its currency is
typed at the optic's **focus**, because the next segment's members must
resolve against the focus type's emissions, exactly as they would after an
accessor had moved the currency there. For `@f(@use(myLens).field)`
the shape of the emission is:

```cangjie
let optics0 = magicFirstClassDowncast(myLens)
let optics0ImplForward  = __FirstClassGetters.forward(myLens)
let optics0ImplBackward = __FirstClassGetters.backward(myLens)
// the currency for the next segment — typed at myLens's focus:
let magic1 = magicFirstClass(myLens)
```

The halves come from the value itself (`__FirstClassGetters`), not from a
registry lookup — a first-class value already carries its composed halves,
which is also why a spliced optic forces the composed path — a value
already in hand has no chain segments to fuse
([composition](../api/composition.md#when-to-unfuse) lists the fallback).
The bridges are ordinary public functions, and they are how the suite
composes optics by hand without the DSL at all — the registry world is not
reserved for generated code
([composition](../api/composition.md#first-class-composition) drives it
directly).

## Where to go next

- [The macro system](macro-system.md) — the emitter side of the same
  system: what each macro parses and emits, and why the emissions take the
  shapes this page resolves.
- [The fusion walk](fusion-walk.md) — the fused emission that consumes
  these bindings segment by segment, including the mark gates and the
  pinning helpers this page deferred.
- [Composition](../api/composition.md) — the table the composed path walks,
  keyed on these registries: the twenty-five-row overload set and the
  upcast lattice behind `opticsUpcast`.
- [First-class optics](../api/first-class.md) — the five kinds and their
  halves: the values `magicFirstClass` and `magicFirstClassDowncast`
  bridge into the registry world.
- [Design decisions](design-decisions.md) — why the diagnostic overloads
  exist at all, and the reasoning behind the registry pattern itself.
