# User-declared optics

Every optic so far was minted by a derive: [deriving](deriving.md) sat
`@DeriveOptics` on a type and emitted a lens per constructor field, an affine
per single-payload case, an iso per one-field wrapper. That covers what a
declaration already exposes. When the part you want is none of those — an
array slot at an index, a type you cannot or would rather not derive — you
declare the optic yourself. `@Optic` declares a first-class optic for
your own types: you name it, pick the kind, write its two halves. From then
on it is a chain segment like any derived one, marked `.` or `?.` like any
other ([chains](chains.md)).

All the code below is from the suite's user-optics fixtures.

## Anatomy

The declaration hangs a bracket of fields on an empty carrier struct — the
struct itself is only a nameplate, and is not emitted. `source:` names the
type the optic walks from; `focus:` the part it reaches; `kind:` the
guarantee — `Lens`, `Prism`, `Affine` or `Iso`, the
[introduction](../introduction-to-optics.md)'s cast
minus the setter, which is not declarable here. On the deriving page the
kinds arrived implicitly, as whatever the derive emitted per field or case;
here the name is explicit. `args:` optionally declares value parameters,
passed at the call site. `forward:` and `backward:` are the two bodies — how
to reach the focus from a source, and how to rebuild the source around a new
focus.

Inside the bodies, a few names are not yours to choose — they are the slots
of the lambdas the declaration compiles to:

- `source` names the source value. Every `forward` receives it, and so does the
  `backward` of a `Lens` or `Affine`.
- `focus` names the new focus — the last slot of a `backward`, and the only
  one for the kinds that rebuild from the part alone.
- `args:` names join them, in scope in both bodies. An arg cannot be called
  `source`, `_source` or `focus` — those slots are fixed (`@Optic: arg name 'source' is reserved`).

The kind decides each body's shape:

| Kind | `forward:` computes | `backward:` receives |
|---|---|---|
| `Lens` | the focus, plain — total | `source`, then `focus` |
| `Iso` | the focus, plain — total | `focus` alone |
| `Prism` | `Option<A>` — `Some(payload)` on a match, `None` on a miss | `focus` alone |
| `Affine` | `Option<A>` — partial, like a prism | `source`, then `focus` |

The backward column is the introduction's rebuild arrow: a `Prism` or `Iso`
rebuilds the whole from the part alone, so its backward has no `source` slot,
and a body that mentions one is rejected — `@Optic: backward of kind 'Prism' has no source slot` (hint: `Lens/Affine backwards receive source; Prism/Iso rebuild from focus`).
The generated members are public whatever the carrier's own visibility — the
carrier only names the optic.

Diagnostics name the macro you actually wrote, so a bad `@Prism` field reports
`@Prism: ...` rather than `@Optic: ...`. Since the aliases fix the kind, they
reject a `kind:` field outright (`@Lens: takes no 'kind' field`) — use
`@Optic[kind: ...]` when you want to spell the kind yourself.

## Shorthand: `@Lens`, `@Prism`, `@Affine`, `@Iso`

Most declarations want one kind and nothing else, so each kind has its own
macro that supplies it. These are exactly equivalent to the long form with
`kind:` filled in:

```cangjie
@Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
struct slen {}
```

is the same as the `@Optic[source: String, focus: Int64, kind: Lens, ...]`
above. The remaining fields are identical, and `@Optic` stays available for the
cases where spelling the kind out is clearer. The rest of this page uses the
long form so each example states its own guarantees; the alias is a shorthand,
not a different feature.

## Reusing a name

Two declarations may share an optic name as long as their `source:` types
differ. The generated interfaces are named from the whole signature — kind,
source, focus and args — so each declaration gets its own, and a chain picks
the right one from the type it starts on:

```cangjie
@Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
struct first {}

@Lens[source: Array<Int64>, focus: Int64, forward: { source[0] }, backward: { ... }]
struct first {}
```

`"abc".first()` and `[1, 2, 3].first()` both work; each resolves through its
own source's registry.

Two constraints come with that:

- **Same name, same `source:`** is an error: the dispatch members are keyed to
  the name alone on that source's registry, so nothing can tell the two
  declarations apart. What the rest of the signature agrees on only changes
  how the error reads. Agreeing on everything gives a redeclaration of the
  generated interface; differing in `kind:` gives a return-type clash on
  `__downcast_method_<name>` instead, which is a blunter message than you may
  expect.
- **Same name, different `args:`** is allowed over different sources, since the
  members sit on different registries and both declarations stay usable. If you
  meant them to be one optic, the mismatched `args:` will not warn you.

### Naming the slots

When a body needs its own `source` or `focus` — a local, a field, anything —
write it with a leading parameter list and the names bind positionally to
the kind's slots instead:

```cangjie
@Optic[
    source: UBox
    focus: Int64
    kind: Lens
    forward: { s => s.v }
    backward: { s, d => UBox(s.v + d) }
]
struct uRenLens {}
```

- `forward:` takes one name — the source: `{ s => ... }`.
- `backward:` takes two for `Lens`/`Affine` (source, then focus), one for
  `Prism`/`Iso` (the focus): `{ d => UJust(d) }`.
- `_` skips a slot: `forward: { _ => 42 }`, `backward: { _, d => ... }`.

A param-form body does not have `source`/`focus` in scope at all — that is
the point: the body's own names cannot collide with the slots. Bare bodies
keep the fixed names. Arity is checked at declaration time
(`@Optic: forward binds 2 names but this kind has 1 slots`, hint: `Use _ to
skip a slot`), and two names on a sourceless backward still report
`has no source slot`.

## A lens, a prism, an affine

Three of the four kinds, one declaration each, each with the behavior the
kind promises (the iso's slots are the table's `Iso` row).

### A lens

```cangjie
public struct UBox {
    public UBox(public let v: Int64) { }
}

@Optic[
    source: UBox
    focus: Int64
    kind: Lens
    forward: { source.v }
    backward: { UBox(focus) }
]
struct uBoxLens {}
```

`uBoxLens` focuses the `v` of a `UBox` — `source.v` forward, total because a
`UBox` always has its `v`, the [lenses](lenses.md) bargain. The backward
builds a new `UBox` around the new focus; the lens backward ignores its
`source` slot — for a one-field whole, the focus is all there is (a multi-field
struct would rebuild its other fields from `src`). `.` marks the calls:

```cangjie
let b = UBox(3)
@Assert(@f(b.uBoxLens()) == 3)
```

The write returns a new box with the focus replaced — nothing mutates:

```cangjie
@Assert(@f(b.uBoxLens() <- 5).v == 5)
```

### A prism

```cangjie
public enum UMaybe {
    | UJust(Int64)
    | UNothing
}

@Optic[
    source: UMaybe
    focus: Int64
    kind: Prism
    forward: { match (src) { case UJust(v) => Some(v) case _ => None } }
    backward: { UJust(focus) }
]
struct uJust {}
```

`uJust` focuses the payload of the `UJust` case. The forward is the prism
bargain from the [prisms](prisms.md) page: on a match, `Some` with the
payload; on a miss, `None`. The backward rebuilds
from the part alone — a fresh `UJust` around the new payload. `?.` marks the
calls, and a read is an `Option`:

```cangjie
let m = UMaybe.UJust(7)
var ok = false
match (@f(m?.uJust())) {
    case Some(r) => ok = (r == 7)
    case _ => ()
}
@Assert(ok)
```

From the other case, `None` — and the `UNothing`
itself, not a stand-in:

```cangjie
let m = UMaybe.UNothing
let fwd = @f(m?.uJust())
var ok = false
match (fwd) {
    case None =>
        ok = true
    case _ => ()
}
@Assert(ok)
```

Writes follow the same contract as the derived case optics: on a match the write
rebuilds the case around the new payload; from a `UNothing` source the same
write returns the source unchanged — the miss is an identity.

### An affine

```cangjie
@Optic[
    source: Array<T>
    focus: T
    kind: Affine
    args: (n: Int64)
    forward: { if (let Some(f) <- src.get(n)) { Some(f) } else { None } }
    backward: { let a = src.clone(); a[n] = focus; a }
]
struct at2<T> {}
```

`at2` is the hand-written cousin of the library's `at`
([chains](chains.md)): the element at index `n`, if there is one. The
`args:` line declares `n`, the call site passes it (`xs?.at2(1)`), and it is
in scope in both bodies. The forward is the affine's `Option` — `Some(f)`
with the element, `None` when the index is out of
range. The backward is why affine differs from prism: "the element at index
`n`" does not determine the array, so the rebuild takes `src` too — clone
it, poke the new focus in at `n`, and hand back the clone. A new value —
nothing mutates.

```cangjie
let xs = [1, 2, 3]
let updated = @f(xs?.at2(1) <- 9)
@Assert(updated[1] == 9)
@Assert(updated[0] == 1 && updated[2] == 3)
```

Out of range, the miss is an identity: the same array comes back, compared
whole:

```cangjie
let xs = [1, 2, 3]
let updated = @f(xs?.at2(10) <- 9)
@Assert(updated == xs)
```

## Composing

User optics compose with everything else in a chain, mark by mark — here a
user affine under `?.` and a user lens under `.`:

```cangjie
let bs = [UBox(1), UBox(2)]
let updated = @f(bs?.at2(0).uBoxLens() <- 7)
@Assert(updated[0].v == 7 && updated[1].v == 2)
```

`?.at2(0)` may miss; `.uBoxLens()` cannot. On a miss at the partial head the
write returns the source unchanged — the same rule the [chains](chains.md)
page walks through with the library's segments.

## Operator marks

The mark is the call site's promise, and the compiler holds a user optic to
it exactly as it holds a derived one: `.` on the total kinds (`Lens`, `Iso`),
`?.` on the partial ones (`Prism`, `Affine`) — every call on this page
follows that. A mismatch fails to compile:

- `.` on a user `Prism` or `Affine` — `@f: '.' on a partial optic (Prism/Affine) — its forward returns Option, so a total read is impossible. Use '?.' and match Some/None.`
- `?.` on a user `Lens` or `Iso` — `@f: '?.' on a total optic (Lens/Iso) — its forward cannot miss, so there is no Option to unwrap. Use '.' for a plain read.`

Every diagnostic `@f` can produce is collected in
[diagnostics](../api/diagnostics.md).

## Generics

The type parameters live on the carrier — that generic list is the only
source of them:

```cangjie
@Optic[source: GBox<T>, focus: T, kind: Lens, forward: { source.v }, backward: { GBox(focus) }]
struct guBoxLens<T> {}
```

`guBoxLens` rides on the same `GBox<T>` the [deriving](deriving.md) page
derived: one declaration covers every instantiation, and the call site
infers the parameter from the receiver:

```cangjie
let gb = GBox<Int64>(5)
@Assert(@f(gb.guBoxLens()) == 5)
let updated = @f(gb.guBoxLens() <- 9)
@Assert(updated.v == 9)
```

Several parameters thread the same way. `gpairFirst` carries two, with `T`
appearing in `source:` and `focus:` alike:

```cangjie
public struct GPair<T, U> {
    public GPair(public let first: T, public let second: U) { }
}
```

```cangjie
@Optic[source: GPair<T, U>, focus: T, kind: Lens, forward: { src.first }, backward: { GPair(focus, src.second) }]
struct gpairFirst<T, U> {}
```

```cangjie
let gp = GPair<Int64, String>(1, "a")
@Assert(@f(gp.gpairFirst()) == 1)
let updated = @f(gp.gpairFirst() <- 2)
@Assert(updated.first == 2)
@Assert(updated.second == "a")
```

A constraint on the carrier is rejected —
`@Optic: generic constraints ('where' clauses) are not supported`
(hint: `Remove the constraint or hand-write the optics`) — the same rule the
derive follows.

## Gotchas

> **Gotcha:** The carrier struct is empty — it only carries the name and
> type parameters. Any member is rejected
> (`@Optic: carrier struct must be empty`). `src`/`focus` are reserved
> for the generated lambda slots.

## Where to go next

- [Introduction to optics](../introduction-to-optics.md) — the cast of kinds
  a `kind:` field picks from, and the rebuild arrows the backward column
  follows.
- [Deriving](deriving.md) — the derived counterpart: the optics a type gets
  for free, per field and per case.
- [Chains](chains.md) — mixing `.` and `?.` segments, derived and
  user-declared, in one chain.
- [First-class optics](../api/first-class.md) — the values a sourceless
  chain mints, and the accessors they answer to.
- [The DSL reference](../api/dsl.md) — every `@f` form on one page.
