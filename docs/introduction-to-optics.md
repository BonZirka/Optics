# Introduction to optics

This page is the *why* behind the [getting started](getting-started.md) example:
where lenses, prisms, affines, isos and setters come from, why chains are
written the way they are, and the one genuinely surprising result — an update
through a focus that misses its match. No formal rules; the ideas, one per
section.

## The pain

Cangjie structs are value types. `var x = S(...)` keeps `var` fields mutable and
`let` fields immutable; `let x = S(...)` freezes everything. A plain nested
struct update is easy to write by hand — that's *not* what optics solve.

The pain arrives when the part you want isn't reachable by a chain of fields:

- **through a collection, an enum, or a class** — "raise the salary of *the*
  Mark" means scanning the array, rebuilding the matching entry, rebuilding the
  array, then the enclosing structs;
- **across shapes (iso/affine)** — you hold the *serialized* form and want to
  change something *inside* the decoded object.

Here is the second one, hand-written:

```cangjie
let decoded = Department.decode(encoded)
let updated = Department(
    decoded.name,
    decoded.employees,
    Info(
        decoded.information.capitalization,
        Address(
            decoded.information.address.country,
            "Melbourne"            // the one change
        )
    )
).encode()
```

One new value — `"Melbourne"`. Everything else is re-read, restated at every
level, re-encoded. The update looks local; the code retypes the whole shape,
twice.

The same change, as an optic, is one expression:

```cangjie
let updated = @f(encoded.serialization<Department>()
    .information.address.city <- "Melbourne")
```

(a segment like `serialization<T>()` is hand-declared, not built in;
[user optics](examples/user-optics.md) shows how)

Focus `encoded.serialization<Department>()`, walk to `.information.address.city`,
set it to `"Melbourne"`: the decode, the per-layer rebuild, and the re-encode
are all the optic's job. And as you'll see at the end, optics take you from one
shape to another, *and back*.

## The idea: a focus

An optic pairs **get** (reach in and extract a part) with **rebuild** (take a
value, a new part, and a new whole with that spot filled). The part is a
*focus*: a named place, decoupled from the shape holding it.

```
      S (a whole value)                      the focus (a name)

   ┌───────────────────────┐          ┌──────────────────────────┐
   │                       │          │   customer.name          │
   │  ┌─────────────────┐  │   get    │                          │
   │  │   a part / hole │  │ ───────▶ │  a *place*, not a value. │
   │  └─────────────────┘  │          │  the same focus names a  │
   │                       │          │  hole in any S that has  │
   └───────────────────────┘          │  it — shape and place    │
              ▲                       │  are decoupled.          │
              │ put                   └──────────────────────────┘
              └──── a new S with ─────┘
               the place refilled; S untouched
```

`@f` names a focus in one expression. The chain's first field — `o` here —
is the *source*: a concrete value the focus is applied to. This is partial
application — pin the source and the answer is already fixed — which is why
reading it looks like a plain field access:

```cangjie
let name = @f(o.customer.address.city.name)
```

The focus itself is the path after the source — `customer.address.city.name` —
and that is the place, not a value: the same focus applies to any value of that
shape. `@ty` makes that place a value: it names the focus *without* pinning a
source, and hands you the path itself as a first-class optic (the explicit
`@ty` spelling of the anchor — the value-rooted form earlier in this
section is the implicit one):

```cangjie
let cityName = @f(@ty(Order).customer.address.city.name)
let mapped = cityName.update(o, "Denver")
```

There is no source in there — only the path. `cityName` *is* the place we
described above: `customer → address → city.name` in any `Order`. `update`
takes a source value and a new part, and returns the new whole. Read
the focus from any `Order` with `cityName.view(o)`; write it with
`cityName.update(o, ...)`. The write form fills the place and returns a new `o`:

```cangjie
let updated = @f(o.customer.address.city.name <- "Denver")
```

"focusing on `o.customer.address.city.name`, set it to `"Denver"`" — the whole
expression returns a new copy of `o` with one leaf swapped; `o` itself is never
touched. The boilerplate from the first section is the `rebuild` half doing its
job for you.

## The cast of kinds

Kinds differ by *guarantees*: how sure you can be the part is there — and, after
a write, what it takes to rebuild the whole. Each optic gets two arrows: the
top one is the read (forward), the bottom one the rebuild (backward):

```
kind     read (forward)                rebuild (backward)         you'd use it on

Lens     S ──────always──▶ a
         S ◀───────── (S, a)           needs the whole             a struct field

Prism    S ──────maybe───▶ a
         S ◀────────────── a           from the part alone         an enum case

Affine   S ──────maybe───▶ a
         S ◀───────── (S, a)           needs the whole             a prism's payload

Iso      S ──────always──▶ a
         S ◀────────────── a           from the part alone, exact  a one-field wrapper

Setter   S ──────map─────▶ S
         S ◀──(a→b)──────▶ S           a map, whole to whole       anything, as a map
```

The read arrow says whether the part is always there or may be missing. The
rebuild arrow points the other way — back to the whole — and says what a write
needs: for a **prism**, just the part (`a ─▶ S`); for a **lens** or **affine**,
the original whole too (`(S, a) ─▶ S`) — exactly the difference between "rewrap
the payload" and "put the part back where it came from".

- **Lens** — the part is always there (a field). Get never misses.
- **Prism** — the part may not be there (an enum case), but given the part you
  can always rebuild the whole. Get can miss; rebuild is total.
- **Affine** — a prism whose part you keep exploring: read can miss, and now
  rebuilding needs the whole, not just the part, because the part alone no
  longer determines it: `department.employees.selectFirst({e => e.name ==
  "Mark"}).salary` — "the salary of *the* Mark, if he exists".
- **Iso** — the part *is* the whole in another shape: `Meters(7)` and `7` are
  the same information in different clothes; nothing is lost, so rebuild is
  exact.
- **Setter** — the loosest: given a map over the whole, returns a new whole.

More guarantee = more you may legally do with the optic. That ordering is also
why chains need two operators — further down.

## Aha: a miss is an identity

```cangjie
let sq = Shape.Square(5)
let updated = @f(sq?.Circle <- Nested(99))
// updated is still Square(5) — the miss was an identity
```

The chain is partial (`?.Circle` is a partial optic — the library kinds it
an affine; same contract), so a write when the source
doesn't match returns the source **unchanged** — no error, no crash, no
branching to write. The "miss → identity" behavior is wired in by the kind.

## Why two operators

`.` vs `?.` is a kind annotation: `.` marks a **total** segment (Lens/Iso), `?.`
a **partial** one (Prism/Affine). The chain's combined kind falls out of the
marks.

Why annotate at all? **Fusion**: the library compiles the whole chain into one
fused walk instead of composing N optics at runtime, and needs each segment's
kind at compile time — that's what you're spelling (see
[fusion walk](architecture/fusion-walk.md), [design decisions](architecture/design-decisions.md)).
A side effect: impossible chains (`.` on a Prism, `?.` on a Lens) are rejected
at compile time.

## Where optics shine

- **Update-through-a-view.** The same data in two shapes, kept in sync — the
  view-update problem from databases (Furtado, Sevcik, dos Santos, 1979) and,
  in this exact two-way form, Pierce & Foster's *Combinators for bidirectional
  tree transformations* (2007).
- **Reducer-style state trees.** "Next state, this one leaf changed" is a Lens
  chain — one expression to focus, one to rebuild, a miss as an identity.
- **Serialization round-trips.** When the focus is an Iso of the value in hand,
  the update flows straight through the representation boundary.

They don't earn their keep everywhere: over a shallow value the hand-written
rebuild is fine; in a hot loop over a giant flat array plain indexing is
cheaper; and if you honestly want to mutate a `var` field in place, this DSL
returns new values by design — wrong tool.

## Where to go next

- [Getting started](getting-started.md) — the full runnable example.
- Examples, in order: [lenses](examples/lenses.md),
  [prisms](examples/prisms.md), [chains](examples/chains.md),
  [deriving](examples/deriving.md), [user optics](examples/user-optics.md).
- The DSL reference — [api/dsl.md](api/dsl.md).
- What the DSL costs — [benchmarks.md](benchmarks.md), and the
  [harness](architecture/inline-harness.md) that measures it.

---

Curious how `@f` finds the optic behind each segment of a chain? Those
mechanics live in [registry plumbing](architecture/registry-plumbing.md) — not
required reading to use the library.
