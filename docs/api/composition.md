# Composition

Optics compose. Two first-class optics — each a value carrying its halves,
the read arrow and the rebuild arrow ([first-class optics](first-class.md)) —
combine into one pair of composed functions, and because that is all a chain
in the `@Lucida` DSL does per segment, a chain *is* composition: one upcast
and one composition step per extra mark. This page is the reference for the
composition machinery itself — the full table of kind pairs, the lattice that
resolves mixed kinds, and the `[unfuse]` switch that forces the library path
over the fused walk.

The whole table is generated at compile time. One macro invocation is the
entire implementation:

```cangjie
@GenerateCompositions
public struct __OpticsCompositions {}
```

`@GenerateCompositions` fills the struct with a `@Frozen` static overload pair
for every ordered kind pair — `composeForward` and `composeBackward` — plus
the `opticsUpcast` overloads of [upcasting](#upcasting). The double underscore
is the library's generated-name marker, the same one derived members and the
first-class helpers carry; the struct itself is public API.

## The composition table

Five kinds, ordered pairs: twenty-five combinations, each emitting one
`composeForward` and one `composeBackward` overload. Composition is ordered —
the pair `(Iso, Lens)` composes Iso∘Lens: the first kind is the *outer* optic,
applied to the source first; the second is the *inner* optic, focused deeper.
The table below is the generator's own list, in its own order:

| # | Outer (applied first) | Inner |
|---|---|---|
| 1 | `Iso` | `Iso` |
| 2 | `Lens` | `Lens` |
| 3 | `Prism` | `Prism` |
| 4 | `Affine` | `Affine` |
| 5 | `Setter` | `Setter` |
| 6 | `Iso` | `Lens` |
| 7 | `Lens` | `Iso` |
| 8 | `Iso` | `Prism` |
| 9 | `Prism` | `Iso` |
| 10 | `Prism` | `Lens` |
| 11 | `Lens` | `Prism` |
| 12 | `Iso` | `Affine` |
| 13 | `Affine` | `Iso` |
| 14 | `Iso` | `Setter` |
| 15 | `Setter` | `Iso` |
| 16 | `Lens` | `Affine` |
| 17 | `Prism` | `Affine` |
| 18 | `Affine` | `Lens` |
| 19 | `Affine` | `Prism` |
| 20 | `Lens` | `Setter` |
| 21 | `Setter` | `Lens` |
| 22 | `Prism` | `Setter` |
| 23 | `Setter` | `Prism` |
| 24 | `Affine` | `Setter` |
| 25 | `Setter` | `Affine` |

Rows 1–5 compose a kind with itself; the remaining twenty are the ten
unordered cross-kind pairs, each in both orders — `Lens∘Prism` and
`Prism∘Lens` are different rows because the outer and inner slots swap,
though both resolve to the same join kind.

### Calling composeForward / composeBackward

Both functions take their arguments in two rounds. The first call hands over
two *registries* — compile-time witnesses carrying each optic's kind and
source type. The second call hands over the four halves: the two forwards,
then the two backwards — outer optic first in each pair. The result is the
composed function itself. The
suite composes a pair of isos like this:

```cangjie
let o1 = isoNeg()
let o2 = isoNeg()
let fwd = __OpticsCompositions.composeForward(
    magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
    __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
    __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
let bwd = __OpticsCompositions.composeBackward(
    magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
    __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
    __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
@Assert(fwd(5) == 5)
@Assert(bwd(7) == 7)
```

The registry round is bridged by one overload per kind:

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

Each overload hands back a fresh registry typed by the optic's source type —
exactly the witness the compose overloads key on. The halves round needs no
bridge at all: the four slots are plain function values, and
`__FirstClassGetters` merely hands back an optic's own halves under uniform
names ([first-class optics](first-class.md#getters--setters)).

### What comes out

The composed functions keep the halves' shapes, partitioned by the pair:

- **Total pairs** — only `Iso` and `Lens` involved: `composeForward` gives a
  total read `(S) -> B`, and `composeBackward` a rebuild taking source and
  focus, `(S, B) -> S`.
- **A setter anywhere**: the composed read is `(S) -> S` — a setter's read
  arrow is `modifyId`, so "reading" through it rewrites and returns the
  source — and the rebuild is `(S, (B) -> B) -> S`, the focus slot widened to
  a modifier function.
- **A prism or affine anywhere (no setter)**: the composed read is partial,
  `(S) -> Option<B>` — a miss anywhere short-circuits to `None` —
  and the rebuild takes source and focus, `(S, B) -> S`.

The four Iso/Prism rows (1, 3, 8, 9) are the exception in the rebuild slot:
both halves rebuild from the focus alone, so the composed rebuild is
sourceless, `(B) -> S`.

Read the two results together and they are exactly the halves of one optic of
the pair's *join* kind — `Iso∘Prism` yields a prism's halves, `Lens∘Prism` an
affine's. The lattice of the next section is that rule made systematic;
`__FirstClassConstruction.perform` accepts the pair by shape, as it accepts
any halves.

The suite pins the shapes on hand-built instances — all `Int64 -> Int64`:

```cangjie
// Canonical instances, all Int64 -> Int64:
//   prismEven: matches even numbers; builds constant 8
//   affPos:    matches n > 0; update replaces focus
func prismEven(): Prism<Int64, Int64> {
    Prism<Int64, Int64>(
        { s: Int64 => if (s % 2 == 0) { Some(s) } else { None } },
        { _: Int64 => 8 }
    )
}

func affPos(): Affine<Int64, Int64> {
    // Lawful affine: update preserves source when the optic does not focus.
    // (Matches the guarding convention of the library's own stdlib impls.)
    Affine<Int64, Int64>(
        { s: Int64 => if (s > 0) { Some(s) } else { None } },
        { s: Int64, v: Int64 => if (s > 0) { v } else { s } }
    )
}

func isoNeg(): Iso<Int64, Int64> {
    Iso<Int64, Int64>({ x: Int64 => -x }, { x: Int64 => -x })
}

func lensId(): Lens<Int64, Int64> {
    Lens<Int64, Int64>({ s: Int64 => s }, { _: Int64, v: Int64 => v })
}
```

An `Iso∘Prism` composition reads partially and rebuilds totally:

```cangjie
let o1 = isoNeg()
let o2 = prismEven()
let fwd = __OpticsCompositions.composeForward(
    magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
    __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
    __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
let bwd = __OpticsCompositions.composeBackward(
    magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
    __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
    __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
// -4 maps through iso to +4 (even -> Some(4)); -3 maps to +3 (odd -> None)
@Assert(isSomeWith(fwd(-4), 4))
@Assert(isNone(fwd(-3)))
// backward: i1from(p2build(5)=8) = -8 (total)
@Assert(bwd(5) == -8)
```

(`isSomeWith`/`isNone` are the suite's `Option` matchers.)

And a miss never writes — the composed rebuild returns the source unchanged,
a new value with nothing changed:

```cangjie
// affPos(3) focuses, prismEven rejects 3 -> whole chain does not focus -> set must be identity.
let o1 = affPos()
let o2 = prismEven()
let bwd = __OpticsCompositions.composeBackward(
    magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
    __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
    __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
@Assert(bwd(3, 5) == 3)
```

## Upcasting

Mixed kinds resolve by a strength lattice:

```text
Setter < Affine < {Lens, Prism} < Iso
```

The generator ranks the kinds by strength — `Setter` weakest, then `Affine`,
then `Lens` and `Prism` tied, `Iso` strongest — and resolves the *join* of two
kinds as the weakest kind that can do both jobs:

- a kind joins with itself to itself;
- anything joined with `Iso` is the other kind — an iso can play any role;
- `Lens` and `Prism`, tied in strength, join to `Affine` — partial like a
  prism, rebuilding like a lens;
- otherwise the weaker kind wins.

`opticsUpcast` makes the lattice callable. Overloads cover every ordered pair
— both argument orders, twenty-five in all — and each returns a fresh registry
of the join kind. The suite's regression test is a compile-time assertion: the
declaration of `r` compiles only if two setters really do join to a setter.

```cangjie
// §1.2 regression: composing two setters must upcast to a SETTER registry.
// Assigned type RegistrySetters makes this a compile-time assertion.
@Test
class UpcastLaws {
    @TestCase
    func settersComposeToSetters(): Unit {
        let r: RegistrySetters<Int64> =
            __OpticsCompositions.opticsUpcast(RegistrySetters<Int64>(), RegistrySetters<Int64>())
        @Assert(true)
    }
}
```

That is all `opticsUpcast` does — it computes a type, not a value. The DSL
leans on it at every segment: as a chain walks, the kind expected so far is
joined with the incoming segment's kind, and the next composition step is
picked from the join's row of the table.

The lattice itself is a rule of the macro generator — `@GenerateCompositions`
bakes the resolved overloads in at compile time. There is no runtime lattice
to query, only the resolved table.

## First-class composition

Nothing in the table requires the DSL — the compose overloads are ordinary
public functions, and the halves they consume are ordinary functions. Build
optics from lambdas, bridge them, and compose:

```cangjie
let o1 = isoNeg()
let o2 = lensId()
let fwd = __OpticsCompositions.composeForward(
    magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
    __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
    __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
let bwd = __OpticsCompositions.composeBackward(
    magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
    __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
    __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
@Assert(fwd(5) == -5)
@Assert(bwd(3, 9) == -9)
```

(`isoNeg` and `lensId` are the suite's hand-built instances from above; the
lambdas can equally be written inline — the overloads see four function
values, nothing more.) The registry round is the only ceremony, and it exists
so that overload resolution — not the caller — picks the row of the table.

## When to unfuse

Reading or writing through a chain normally emits a *fused walk*: the macro
binds each segment's halves once and emits one straight-line pass over them —
no per-segment optic values, no intermediate wrapping. The `[unfuse]`
attribute skips that and forces the library path of this page: the chain is
composed, step by step, from `composeForward`/`composeBackward` and
`opticsUpcast`.

```cangjie
@TestCase
func unfusedForward(): Unit {
    let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
    @Assert(@Lucida[unfuse](o.customer.address.city.name) == "Atlanta")
}
```

(the `Order`/`Customer`/`Address`/`City` model is the examples tier's — see
[lenses](../examples/lenses.md))

```cangjie
@TestCase
func unfusedBackward(): Unit {
    let o = Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
    let updated = @Lucida[unfuse](o.customer.address.city.name <- "Denver")
    @Assert(updated.customer.address.city.name == "Denver")
    @Assert(o.customer.address.city.name == "Atlanta")
    @Assert(updated.id == 1)
}
```

Semantics are identical — `[unfuse]` changes the code shape, not the results:
the write still returns a new value — nothing mutates.

The macro also falls back on its own, no attribute needed, whenever the fused
walk does not apply:

- **A spliced first-class optic** — `@Optic(o)` anywhere in the chain always
  takes the library path; the fused walk does not support the splice.
- **Reads with more than eight either-producing segments** — each partial
  segment (`?.` on a derived case, a `?.`-marked user optic) is pinned to a
  slot in the fused read walk, and the slots run out at eight; longer chains
  fall back automatically. Writes are not capped.
- **Segments the walk cannot carry** — derived fields, user-declared optics
  used by name (not `@Optic` splices), and coercions fuse; anything else
  falls back.

So `[unfuse]` is for opting in deliberately — keeping a specific call site on
the composed path for benchmarking (the bench suite keeps a serialization
chain on the composed path this way), or because a segment's shape demands
it and you want to say so at the call site.
What the fused path actually emits is the subject of [the fusion
walk](../architecture/fusion-walk.md).

## Where to go next

- [First-class optics](first-class.md) — the five kinds and their halves: the
  values being composed here.
- [The fusion walk](../architecture/fusion-walk.md) — the fused path
  `[unfuse]` bypasses.
- [Chains](../examples/chains.md) — composition as the DSL presents it:
  implicit, one upcast and one step per segment.
- [User-declared optics](../examples/user-optics.md) — declaring first-class
  optics of your own, which then compose like any other kind.
