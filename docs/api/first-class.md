# First-class optics

Every optic in this library is a plain value. Behind the `@f` chain
syntax is a model of five structs — `Iso`, `Lens`, `Prism`, `Affine`,
`Setter` — each carrying its halves (the read arrow and the rebuild arrow)
as public members. First-class means exactly that: a focus you can hold in a
`let`, pass to a function, store in a collection, and apply to any source it
fits — without the DSL naming it for you.

The two layers meet in both directions. A chain stays syntax:
`@f(o.customer.name <- "Ada")` names a focus and uses it in one
expression. The sourceless forms hand the same focus over as a value —
`@f(@typeof(c).zip)` mints a lens you keep — and a value you hold
re-enters any chain as a segment: `@f(@use(myLens).field)` ([the DSL
reference](dsl.md)). This page is the reference for the
values themselves: the five types, their construction, and the uniform
accessors every kind answers to.

The helpers below carry a double underscore — `__FirstClassConstruction`,
`__FirstClassGetters`. The prefix is the library's generated-name marker,
the same one derived members carry — it keeps these names out of your way.
Both structs are public API: values are built through the first and
read back through the second.

## The types

Five structs, one per kind, in the order the library declares them. Each
kind's members are its halves — the read arrow and the rebuild arrow, in the
[introduction](../introduction-to-optics.md)'s terms.

```cangjie
public struct Iso<S, A> {
    public Iso(
        public let to: (S) -> A,
        public let from: (A) -> S
    ) {}
}
```

`Iso` — the part *is* the whole in another shape: `to` reads it, `from`
rebuilds the whole from the part alone — exact, nothing lost.

```cangjie
public struct Lens<S, A> {
    public Lens(
        public let view: (S) -> A,
        public let update: (S, A) -> S
    ) {}
}
```

`Lens` — a total focus on a part that is *always* there: `view` reads it,
`update` takes the whole and the new part and returns the new whole.

```cangjie
public struct Prism<S, A> {
    public Prism(
        public let preview: (S) -> Option<A>,
        public let build: (A) -> S
    ) {}
}
```

`Prism` — a partial focus on an enum case: `preview` answers in `Option` —
`Some(payload)` on a match, `None` on a miss — and `build` rewraps
a payload into a fresh whole.

```cangjie
public struct Affine<S, A> {
    public Affine(
        public let preview: (S) -> Option<A>,
        public let update: (S, A) -> S
    ) {}
}
```

`Affine` — partial like a prism, with the lens's rebuild: `preview` answers
in `Option`, and `update` needs the source too — the part alone no longer
determines the whole.

```cangjie
public struct Setter<S, A> {
    public Setter(
        public let modify: (S, (A) -> A) -> S
    ) { }

    public prop modifyId: (S) -> S {
        get() {
            { source: S => modify(source, { x: A => x }) }
        }
    }
}
```

`Setter` — the loosest kind: one `modify` map — given the source and a
function over the focus, return the rewritten source. `modifyId` fixes that
function to the identity: a plain `(S) -> S`, the setter's read-back.

The members are the optic: call one like any function value —
`anOptic.update(source, newFocus)` returns a new value with the focus
swapped in; nothing mutates.

## Construction

`__FirstClassConstruction.perform` builds any of the five from its two
halves — one overload per kind, picked by the shape you hand it:

```cangjie
public struct __FirstClassConstruction {
    @Frozen
    public static func perform<S, A>(forward: (S) -> A, backward: (A) -> S): Iso<S, A> {
        Iso(forward, backward)
    }

    @Frozen
    public static func perform<S, A>(forward: (S) -> A, backward: (S, A) -> S): Lens<S, A> {
        Lens(forward, backward)
    }

    @Frozen
    public static func perform<S, A>(forward: (S) -> Option<A>, backward: (A) -> S): Prism<S, A> {
        Prism(forward, backward)
    }

    @Frozen
    public static func perform<S, A>(forward: (S) -> Option<A>, backward: (S, A) -> S): Affine<S, A> {
        Affine(forward, backward)
    }

    @Frozen
    public static func perform<S, A>(_: (S) -> S, backward: (S, (A) -> A) -> S): Setter<S, A> {
        Setter(backward)
    }
}
```

The setter overload keeps the forward slot for a uniform call shape and
ignores it — a setter *is* its map.

This is the entry point the DSL lowers to: each sourceless chain form
materializes the two halves and hands them to `perform` — the read form
`@f(@typeof(c).zip)` mints a lens, the partial form
`@f(@typeof(circleVal)?.Circle)` mints an affine, and the write form
`@f(@typeof(c).zip <- 99999)` mints a setter. The suite pins the
affine case:

```cangjie
let circleVal = Shape.Circle(Nested(1))
// Sourceless @typeof form constructs the first-class affine itself.
let aff = @f(@typeof(circleVal)?.Circle)
let rebuilt = aff.update(circleVal, Nested(9))
var rebuiltOk = false
match (rebuilt) {
    case Circle(nn) => rebuiltOk = nn.n == 9
    case _ => ()
}
@Assert(rebuiltOk)
```

(`Shape` and `Nested` are the suite's derived enum and its one-field
payload, as on the [prisms](../examples/prisms.md) page.) `aff` is an
ordinary value — `update` is its own field, called like any function — and
`rebuilt` is a new `Shape` with the payload swapped in.

The structs' constructors are public too, and the suite builds optics by
hand with them:

```cangjie
func isoNeg(): Iso<Int64, Int64> {
    Iso<Int64, Int64>({ x: Int64 => -x }, { x: Int64 => -x })
}

func lensId(): Lens<Int64, Int64> {
    Lens<Int64, Int64>({ s: Int64 => s }, { _: Int64, v: Int64 => v })
}

func prismEven(): Prism<Int64, Int64> {
    Prism<Int64, Int64>(
        { s: Int64 => if (s % 2 == 0) { Some(s) } else { None } },
        { _: Int64 => 8 }
    )
}
```

The same halves go straight to the overload set, under the same
pick-a-kind-by-shape rule:

```cangjie
let lens = __FirstClassConstruction.perform(
    { s: Int64 => s },
    { _: Int64, v: Int64 => v }
)
```

(written for this page — the lambdas are `lensId`'s halves from above; the
suite always arrives at `perform` through the DSL)

## Getters & setters

`__FirstClassGetters` gives the five kinds' halves uniform names —
`forward` for the read arrow, `backward` for the rebuild — one `@Frozen`
overload pair per kind:

```cangjie
public struct __FirstClassGetters {
    @Frozen
    public static func forward<S, A>(x: Iso<S, A>): (S) -> A { x.to }
    @Frozen
    public static func backward<S, A>(x: Iso<S, A>): (A) -> S { x.from }
    @Frozen
    public static func forward<S, A>(x: Lens<S, A>): (S) -> A { x.view }
    @Frozen
    public static func backward<S, A>(x: Lens<S, A>): (S, A) -> S { x.update }
    @Frozen
    public static func forward<S, A>(x: Prism<S, A>): (S) -> Option<A> { x.preview }
    @Frozen
    public static func backward<S, A>(x: Prism<S, A>): (A) -> S { x.build }
    @Frozen
    public static func forward<S, A>(x: Affine<S, A>): (S) -> Option<A> { x.preview }
    @Frozen
    public static func backward<S, A>(x: Affine<S, A>): (S, A) -> S { x.update }
    @Frozen
    public static func forward<S, A>(x: Setter<S, A>): (S) -> S { x.modifyId }
    @Frozen
    public static func backward<S, A>(x: Setter<S, A>): (S, (A) -> A) -> S { x.modify }
}
```

Nothing computes here: each overload hands back the struct's own half
under the uniform name.

| Kind | `forward` is | `backward` is |
|---|---|---|
| `Iso` | `to` | `from` |
| `Lens` | `view` | `update` |
| `Prism` | `preview` | `build` |
| `Affine` | `preview` | `update` |
| `Setter` | `modifyId` | `modify` |

The setter is the odd kind out: its `forward` is not a field but the
struct's `modifyId` property — `modify` with the identity function, typed
`(S) -> S` — and its `backward` is `modify` itself. The suite exercises
both on a hand-built setter:

```cangjie
let o = Setter<Int64, Int64>({ s: Int64, f: (Int64) -> Int64 => f(s) })
@Assert(o.modifyId(41) == 41)
@Assert(o.modify(41, { x: Int64 => x + 1 }) == 42)
```

This forward/backward pair is what the generated composition machinery is
built on — [composition](composition.md) covers it kind by kind.

## Option

Every partial read answers in one type — the standard `Option<T>` everyone
already knows:

```cangjie
enum Option<T> { | Some(T) | None }
```

`Some(a)` — the focus, on a match. `None` — the optic did not focus, and
that is all it tells you: no value is handed back, because the source is
the very value you passed in and it is untouched (updates build new values;
originals are never mutated). The prism and affine forwards return it
(`prismEven` above builds both cases by hand). At the call site a partial
read hands you the `Option` to match; a partial write consumes the miss
internally — a miss is an identity — so you never unpack `Some`/`None` to
perform an update ([prisms](../examples/prisms.md) walks the read, the
write, and the miss-is-identity rule on both sides).

## Laws

The five kinds are trusted constructions: the library cannot check, at
compile time, that the halves you pass behave — an optic whose `update`
ignores its focus compiles fine. What a kind *promises* is its law set, and
code may assume it for every optic it receives. Construct an optic that
breaks them and the brokenness is yours; the composed chains and DSL walks
only preserve lawfulness, they cannot manufacture it.

| Kind | Laws (on matched inputs) |
|---|---|
| `Iso` | GetSet, SetGet, SetSet — both arrows are total inverses |
| `Lens` | GetSet, SetGet, SetSet — view then update is identity; update installs the focus; updates commute |
| `Prism` | GetSet, SetGet, SetSet — quantified over the match set: `build(a)` must itself match, and preview it back to `Some(a)` |
| `Affine` | GetSet, SetGet, SetSet — quantified over the match set; a miss is an identity on both arrows |
| `Setter` | SetSet — there is no view; only "setting twice = setting the final value once" |

- **GetSet** — `set(s, view(s)) == s`: reading then writing back changes
  nothing.
- **SetGet** — `view(set(s, a)) == a`: what you write is what you read back.
- **SetSet** — `set(set(s, a1), a2) == set(s, a2)`: only the last write
  matters.

Every composition row (all 25 ordered kind pairs) and every fused chain is
tested against these laws in
[`composition_property_laws.cj`](https://github.com/BonZirka/Optics/blob/dev/src/tests/composition_property_laws.cj)
and
[`composition_laws.cj`](https://github.com/BonZirka/Optics/blob/dev/src/tests/composition_laws.cj)
— the regression suite composes with sign-flipping and miss-planting
instances, the property suite asserts the laws themselves. The one deliberate
departure from the classical texts: case optics and multi-payload prisms are
*kinded as affines* (sourceful backward, miss-is-identity), so their law set
is the affine's.

## Where to go next

- [Composition](composition.md) — combining first-class optics, kind by
  kind, on the forward/backward pair above.
- [The DSL reference](dsl.md) — every `@f` form, including the
  sourceless `@ty`/`@typeof` forms that mint these values.
- [User-declared optics](../examples/user-optics.md) — `@Optic`:
  declaring a first-class optic for your own types.
- [Introduction to optics](../introduction-to-optics.md) — the five kinds
  as ideas: read arrows, rebuild arrows, and why a miss is an identity.
- [Prisms](../examples/prisms.md) — `Option` in action at the call site.
