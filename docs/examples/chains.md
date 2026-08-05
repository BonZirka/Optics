# Chains

A chain is one focus spelled left to right — a source value, then segment
after segment, down to the part you care about: `o.customer.address.city.name`
on the [lenses](lenses.md) page, `sq?.Circle.n` on the [prisms](prisms.md)
page. Each page used one kind of segment; real data mixes them — an array
inside a struct, a field inside a matched case — so this page is about the
operator each segment carries. However long the chain, it is one optic, not a
sequence of steps: one expression reads it, one expression writes it, and one
new value comes back — nothing mutates.

## The two operators

Every segment is marked with the guarantee the optic behind it makes:

| Operator | Meaning | Segments it matches |
|---|---|---|
| `.` | total — the part is always there; read and write cannot miss | derived lens fields, isos — e.g. `coerce<T>()`, `.`-marked user optics |
| `?.` | partial — a read evaluates to `Option`: `Some(payload)` on a match, `None` on a miss | derived case optics, `Array.at`, `Array.selectFirst`, `?.`-marked user optics |

The mark is not decoration — it names the kind, and the compiler checks it.
A partial write is unconditional: when the segment misses, the write returns
the source unchanged. The miss is an identity, wired in by the kind. The
library's `at` and `selectFirst` are partial, so the segment that uses either
carries `?.` — and total segments after it go back to `.`.

## Mixed chains

Start with an array of numbers and one index:

```cangjie
let nums = [10, 20, 30]
let bumped = @Lucida(nums?.at(1) <- 99)
@Assert(bumped[0] == 10)
@Assert(bumped[1] == 99)
@Assert(bumped[2] == 30)
@Assert(bumped.size == 3)
// immutability: the caller's array must be untouched (CoW aliasing bug class)
@Assert(nums[1] == 20)
```

`at` takes an index, and an index can be out of bounds — `nums` has no
element at index `7` — so the segment is partial and carries `?.`. In bounds,
the write lands: `bumped` is a new array
with `99` at index `1`, size still `3`, both neighbors carried over. And
`nums[1]` is still `20` — the write builds a new array rather than editing the
one it was given, so the caller's array comes out untouched; that is the
aliasing hazard copy-on-write semantics exist to prevent.

Out of bounds, there is no element to replace, so the same write returns the
source unchanged:

```cangjie
let untouched = @Lucida(nums?.at(7) <- 99)
@Assert(untouched.size == 3)
@Assert(untouched[0] == 10 && untouched[1] == 20 && untouched[2] == 30)
```

No guard, no branch: write through the focus and let the kind decide. (The
reverse mix — a field first, then the array inside it — works the same; see
[getting started](../getting-started.md).) The read side says which way it
went, in the same `Option` the prisms page introduced:

```cangjie
// source-form read returns Option: Some(focus) / None
var noneOk = false
if (let None <- @Lucida(nums?.at(7))) {
    noneOk = true
}
@Assert(noneOk)
var rightOk = false
if (let Some(fv) <- @Lucida(nums?.at(0))) {
    rightOk = fv == 10
}
@Assert(rightOk)
```

`nums?.at(7)` misses, so the read is `None` — nothing handed back; the
original array is untouched. `nums?.at(0)` matches, so it is `Some(fv)` — the focused element,
`10`.

## selectFirst

`selectFirst` aims at the first element of an array that matches a predicate.
The fixture is a derived struct — `Employee2` has a `name` and a `salary` —
and an array holding three employees, the first two named `"dup"`:

```cangjie
let staff = ArrayList<Employee2>()
staff.add(Employee2("dup", 100))
staff.add(Employee2("dup", 200))
staff.add(Employee2("other", 300))
let arr = staff.toArray()

let raised = @Lucida(arr?.selectFirst({ e: Employee2 => e.name == "dup" }).salary <- 999)
@Assert(raised[0].salary == 999)
@Assert(raised[1].salary == 200)
@Assert(raised[2].salary == 300)
```

Two employees match `"dup"`; only the first is touched — `raised[0]` carries
`999`, `raised[1]` keeps its `200`, `raised[2]` its `300`. This is the full
mix: `?.` marks the partial step, because a match may not exist, and `.` takes
over after it — `salary` is a derived lens on the matched element, and a lens
cannot miss.

No match, no write:

```cangjie
let miss = @Lucida(arr?.selectFirst({ e: Employee2 => e.name == "nobody" }).salary <- 999)
@Assert(miss.size == 3)
@Assert(miss[0].salary == 100)
@Assert(miss[1].salary == 200)
@Assert(miss[2].salary == 300)
```

`"nobody"` matches nothing, so the miss is an identity: the same three
salaries come back, size and all. One expression, two outcomes, decided by the
data alone — and either way, a new value — nothing mutates.

## Coerce segments

Isos are total, so they ride on `.`. The suite derives `Meters`, a one-field
struct whose single field is an `Int64`, and coerces it:

```cangjie
let m = Meters(7)
let unwrapped = @Lucida(m.coerce<Int64>())
@Assert(unwrapped == 7)
```

`coerce<Int64>()` unwraps the derivation: `Meters` and its `Int64` payload are
the same information in different clothes, so the focus evaluates to `7` — a
plain `Int64`, no wrapper. Total means no `Option` and no miss, hence `.`.

And the negative: because `coerce<T>()` is total, it never takes `?.` —
`x?.coerce<T>()` does not compile. Every chain form `@Lucida` accepts is on
the [DSL reference](../api/dsl.md) page.

## Gotchas

> **Gotcha:** Wrong operator for the kind fails at compile time with a bespoke
> message (see [docs/api/diagnostics.md](../api/diagnostics.md)). `.` on a
> partial, `?.` on a total, or `.`-write through a prism — none compile.

## Where to go next

- [Introduction to optics](../introduction-to-optics.md) — why chains need two
  operators: the marks are kind annotations, and the chain compiles to one
  fused walk.
- [Lenses](lenses.md) and [prisms](prisms.md) — the two ingredients this page
  mixes, one page each.
- [The DSL reference](../api/dsl.md) — every `@Lucida` form on one page.
- Next example: [deriving](deriving.md) — what `@DeriveOptics` generates for
  each type, including the single-field isos that `coerce<T>()` rides on; then
  [user optics](user-optics.md) — bringing your own segments, marked `.` or
  `?.`.
