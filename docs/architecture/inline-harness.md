# `@InlineOptics` — the benchmark harness

> **Not a library feature.** `@InlineOptics` exists to measure `@f`. It lives in
> the test project, not in `lucida`; nothing in `core` or `stdlib` references it,
> and it carries no compatibility promise. If it disappears, the library is
> unchanged.

## The question it answers

`@f` fuses a chain into nested calls at compile time, but the fused expansion is
not the same code as the chain you would have written by hand: it reads every
untouched sibling through the registry, so it carries fixed per-chain overhead
that grows with the shape and has nothing to do with the update itself. The
question is how much that costs, and the only honest way to answer it is to
measure `@f` against the direct expansion of *the same expression*.

`@InlineOptics` is that direct expansion, derived from the DSL rather than
written beside it:

```cangjie
let s = @f(o.y.b.v <- 99)
let i = @InlineOptics[
    shapes: (InlBox, (x, Int64), (y, InlLeaf), (tag, Int64)),
            (InlLeaf, (a, Int64), (b, InlTip)),
            (InlTip, (v, Int64), (w, Int64)),
    root: InlBox
](o.y.b.v <- 99)
// i expands to: InlBox(InlLeaf(InlTip(o.y.b.v, o.y.b.w), o.y.a), o.tag)
```

Two things follow, and they are the whole point:

- **It is an oracle.** The same expression, expanded two ways, must produce the
  same value. Asserted per form in `tests/src/inline_optics.cj`, and for every
  benchmark shape in `tests/src/generated/` — reads included, 15 write and
  15 read expansions, all of them pinned against a hand-written direct form. A
  semantics bug in `@f` shows up as a value mismatch, not as a suspicious timing.
- **It is a baseline.** The yardstick is generated from the expression under
  test, so "what `@f` could have compiled to" is not a separate hand-written
  benchmark that can drift from the DSL, and not an estimate. Every timed read
  also dirties the leaf it reads, so the baseline cannot be hoisted into a
  register and report a speedup that the real program would never see
  ([why](../benchmarks.md#reads-checked-not-timed)).

The expansion is checked, not timed. For every generated shape the hand-written
rebuild lives in `expected_expansions.txt`, and `scripts/check_codegen.sh` diffs
it against what the macro actually emits — same tokens, modulo whitespace and the
fresh `__ioN` binders an emitter has to invent. So "the harness compiles the DSL
to the program the baseline spells out" is an assertion in the gate rather than
two rows that happened to land within a couple of percent of each other. Timing
it as well would only measure the noise floor; there was a real difference once,
and the gate caught it: block updates used to wrap the update tuple in a
`match` to destructure it, which compiles and optimizes away but is not what
anyone writes.

The expansion is a measurement artifact. There is no fast path in the shipped
API; users get `@f` and whatever the optimizer does with it.

What it measures, on the current generated matrix: fused `@f` is 10–51% slower
than the direct expansion on total chains, 187% slower on a prism write, 168% on
a wide sibling block, 126% on a sibling block behind a case, 15% on a coercion,
and *unable to express* an update through an `Option`-typed field at all. The
full table is in [the benchmarks](../benchmarks.md).

## Where it lives, and why it is a macro at all

It lives in the test project, not in `lucida`: `tests/src/inline/` is a macro
package (`tests.inline`) holding the macro and a copy of the DSL's chain parser,
`tests/src/inline_optics.cj` asserts it against `@f`, and `tests/src/generated/`
is the shape matrix it exists to measure. Nothing under `core/` knows the word
`@InlineOptics`.

It is a macro because a macro sees the token stream at the call site, which is
the only place the expression's segment structure exists — there is no HIR to
inspect. A build script would have to re-parse the DSL from source text.

Being outside `lucida` costs something real, and the cost is a duplicated
parser. `lucida.macrodsl`'s parser is package-internal, so reusing it would mean
making it public — turning private macro machinery into API surface with a
compatibility promise, which is a worse trade than a copy in the test tree.
`tests/src/inline/parser.cj` is therefore a copy of
`core/src/macrodsl/parsing.cj`, and the honest consequence is that two parsers
now exist for one grammar and can drift. What catches drift is mechanical:
`tests/src/inline_optics.cj` expands every form both ways and compares values,
and `scripts/check_diagnostics.sh` pins the failure surface, so a grammar change
in core that the copy misses fails the gate instead of quietly changing a
benchmark. **When core's parser changes, change the copy.**

The other thing the boundary costs is the first-class anchors. `@use`, `@ty` and
`@typeof` expand only inside `@f` — their guard is in `core` and names `@f` — so
with the harness outside `core` their guard fires first and the harness never
sees them. Those rows in the coverage table below are gaps for that reason, not
because the parser copy lacks the syntax.

The consequence for callers is that the layout is supplied by hand: a macro
cannot see struct declarations. `shapes:` and `root:` below are the price of
that, and they are also what makes the harness trustworthy — the caller states
the layout, the harness does not infer it, and a wrong layout produces a
mismatch rather than a plausible-looking number.

## Coverage

The harness is only as good as the `@f` forms it can expand. Current state:

| `@f` form                              | Harness | Notes                                              |
|----------------------------------------|---------|----------------------------------------------------|
| Derived field lens, chains             | yes     | The baseline case; emits plain field reads         |
| Enum case (`o?.Held`, read and write)  | yes     | Partial write hoists one `match` over the chain    |
| Segments below a case                  | yes     | A struct or tuple payload continues into its fields |
| Sibling block (`o.{ .a; .b.v } <- ..`) | yes     | Shared prefixes rebuild once                       |
| Block anchored on a case (`o?.Held.{ .a; .b }`) | yes | The guard wraps the block's whole rebuild          |
| Block anchored on a partial that is not the last segment | no | `@f` rejects it too; see the diagnostic below   |
| User-declared `@Optic` body            | yes     | Forward/backward bodies come from `registry:`      |
| Registered method segment (`xs.at(1)`) | yes     | Needs a `registry:` entry naming the bodies       |
| First-class optic mid-chain (`@use`)  | **no**  | `@use` only expands inside `@f`; see above         |
| `coerce<T>()`                         | yes     | Mechanical for a derived iso; see below            |
| `Array.at(i)`, `Array.selectFirst`    | partial | Needs a `registry:` entry written per call site    |
| Tuple element lenses (`_0`, `_1`, ..)  | **no**  | See below                                          |
| Sourceless `@use`/`@typeof`/`@ty`     | **no**  | See below                                          |

The last three rows are gaps in the harness, not rejections in the library — with
the exception of the `@use` row, which is a gap caused by living outside `core`.
`@f` supports all of them; the harness cannot expand them, so their performance
is currently unmeasured and their semantics unchecked.

- **Tuple element lenses** need the arity of a tuple, and the shape list has no
  way to say "this type is a tuple of N": a shape entry is a named type with
  named fields. Adding one means a tuple shape convention and a rebuild step
  that emits a tuple literal instead of a constructor call. Until then
  `s?.Both._0 <- 5` is rejected rather than mistranslated.
- **Sourceless chains** do not update anything: `@f(o.@use(x) <- v)` constructs
  a `Setter` value, it is not an update. A harness whose output is a rebuild has
  no rebuild to emit. Checking that path means asserting on the *minted value*,
  which is a different kind of test and is not implemented. They are also
  unreachable for a second reason: `@use`/`@ty`/`@typeof` expand only inside
  `@f`, so a chain spelled with them fails in `core` before the harness is
  entered. A probe pins that message, so the boundary is asserted rather than
  assumed.
- **The stdlib `Array` affines** do have a direct form, but it is a `match` plus
  an index test written by hand per call site. The harness takes one on trust
  through `registry:`, which is enough to check equivalence but means the
  benchmark numbers for those segments are only as good as the entry.

**Blocks behind a partial segment** are the case worth spelling out, because the
anchor decides where the `match` goes. `o?.Held.{ .a; .b } <- (..)` spends its
`?.` on the case, so the block's owner is the *payload*: the guard matches on the
enum, and the hit arm rebuilds the case around the block's constructor call while
the miss arm hands back the source unchanged. That is one `match`, and the
codegen gate pins it against the same hand-written form:

```cangjie
// @InlineOptics(v?.Held.{ .a; .b } <- (x, y))
match (v) {
    case Held(p) => Held(Leaf(p, x, y))
    case _ => v
}
```

Only the anchor's *last* segment may be partial. `o.f?.On.e.{ .q }` would have
to keep rebuilding below the case after the guard closed, which is a different
program, so both reject it:

```
a sibling block anchor cannot cross a partial segment
```

`?.` is also read the way `@f` reads it — as applying to the optic *before* it.
`x?.s` is "unwrap `x`, then read `s`", and `x` is a struct, so it is refused even
when `s` happens to be an `Option`:

```
'?.' on a total optic (Lens/Iso) — 'InlOptI' cannot miss
```

An `Option`-typed field is already partial, so it is reached with `.s`, and a
registered partial with `value?.at(1)`.

**Coercions** are the one form that needed no new metadata. A coercion resolves
against a one-field derivation and its field type, so its forward is the field
read and its backward is the single-argument constructor — the same pair the
rebuild already emits for that field. The harness checks the shape really is
that pair and then treats the segment as a field rebuild:

```
'Wrap' is an iso to 'Unit', not to 'Int64'
a coercion needs a one-field shape; 'Pair' has 2
```

Both are rejections `@f` would also hit, at the registry instead of the shape
list, so the harness fails where the library fails rather than diverging.

## Attributes

### `shapes:` (required)

Every type the chain can walk through, with its fields **in constructor order**:

```cangjie
shapes: (TypeA, (field1, FieldType1), (field2, FieldType2)), (TypeB, (g, T))
```

Field types may be generic (`Array<Int64>`); a generic type is a leaf, since a
rebuild never descends into it.

An enum lists its cases instead, each with its payload in declaration order. A
payloadless case carries an empty `()`:

```cangjie
shapes: (InlSlot, (Empty, ()), (Held, (v, Int64)))
```

An `Option`-typed field is spelled `Option<InnerType>` so a `?.` segment knows
what it focuses:

```cangjie
shapes: (InlSlotBox, (slot, Option<InlSlot>))
```

### `root:` (required)

The type of the chain's source expression. Without it the harness cannot tell
which shape to start from.

### `registry:` (optional)

Maps an optic name to inlining metadata. Two forms:

```cangjie
// A derived-field optic, e.g. @typeof(o).y
registry: (name, OwnerType, field)

// A hand-written optic: forward and backward bodies, plus the focus type
registry: (name, body, { source => FWD }, { source, focus => BWD }, FocusType)
```

The body form is what makes `@Lens`/`@Optic` carriers expandable. Forward runs
against the *old* focus so the segment below it can still be rebuilt; backward
wraps the new focus.

## What the harness accepts

- Backward chains over derived fields — `o.a.b.c <- v`.
- Forward reads — `o.a.b.c`.
- Enum cases — `o?.Held` (read) and `o?.Held <- v` (write), including chains
  that continue into a struct or tuple payload — `g?.On.n`, `s?.Both`.
- Partial segments over `Option`-typed fields — `o.slot?.v`.
- Coercions over a derived iso — `o.w.coerce<Unit>()`, alone or with segments
  below it — `o.w.coerce<Unit>().n`.
- Sibling blocks — `o.{ .a; .b.v } <- (1, 2)`, including nested blocks.
- Registered segments mid-chain, given their registry entry — a method call
  such as `xs.at(1)` or a hand-written optic's body. Not `@use`: see the
  coverage table.
- `@ty`/`@typeof`/`@use` anchors, which expand before `@InlineOptics` runs.

Pass the optical expression itself, not `@f(...)`. A nested macro expands before
`@InlineOptics` runs, so wrapping the expression in `@f` fails with a message
from `@f` rather than a useful one.

## Two details worth knowing

**Partial segments.** `?.` marks the *following* segment as partial, and every
partial segment opens one failure channel. On a miss there is nothing to focus:
a read yields the `None` the channel produces, and a write returns the source
unchanged. A partial read whose chain is otherwise total focuses the payload
directly, so one `?.` costs exactly one `Option`; each further partial segment
nests one more, matching how `@f` composes adjacent affines.

The write case is why the expansion hoists the whole `match` over the entire
chain rather than wrapping the levels above it. Both produce the same value, but
the wrapping form allocates a fresh object to copy an unchanged one, and the
benchmark would charge `@f` for the harness's mistake. `tests/src/inline_optics.cj`
pins the miss case directly.

**Chains that continue below a case.** The payload is the subject for the rest
of the walk, in both directions: a read of `g?.On.n` matches the case and then
reads `n` off the binder, and a write rebuilds `n` and closes the case over the
result. Two bugs lived here — the read stopped at the payload, and the write
wrapped the case around the new focus instead of the rebuilt chain — and both
were found by adding coercion coverage, which is the only DSL form that puts a
segment below a case and still fits in the shape list.

**Blocks.** A block rebuilds the anchor once and writes every entry into it.
Entries sharing a prefix collapse into a single rebuild of that level. Blocks
rebuild every field they do not name, so neither the anchor nor an entry may
depend on a value that can be absent; both are rejected rather than dropped.

## Diagnostics

Every rejection carries a hint naming the supported spelling.
`scripts/check_diagnostics.sh` pins each message with a `probe: name — message`
pair; the full list, grouped by cause, is in the harness's section of
[the diagnostics reference](../api/diagnostics.md#inlineoptics).

Metadata:

- `missing required field 'shapes'` / `field 'shapes' is empty` — the attribute
  is absent or has no entries;
- `'shapes' listed no types`, `shape 'T' has no fields`,
  `enum shape 'T' has no cases` — an entry that names a type but not its layout;
- `no shape registered for type 'T'` — the chain walks into a type the metadata
  never described (hint: add `(T, (field, FieldType), ...)`);
- `shape 'T' has no field 'f'` — a derived field the metadata omits;
- `field 'f' takes a single type name` — a field type the parser cannot read;
- `the source value's type is unknown` — no `root:`, and no anchor that implies
  one.

Chains:

- `has no field 'f'` / `enum 'T' has no case 'C'` — a misspelled or wrongly-kinded
  segment;
- `'?.' needs an Option-typed value` / `'?.' needs 'T.f' to be an Option` —
  a partial segment over something that cannot be absent (hint: declare the field
  as `(f, Option<PayloadType>)`);
- `case 'C' needs a partial segment` — a case written totally, as `o.C`; it needs
  `o?.C`, because a case can miss;
- `optic 'x' focuses 'T', but the chain is at 'U'` — a registry entry used where
  its owner does not fit;
- `no inlining metadata registered for 'x'` — a registered segment with no
  `registry:` entry (the hint shows both entry forms);
- `cannot inline coerce<T> on 'T'` — the shape is not a one-field derivation of
  the named type;
- `a sibling block anchor cannot cross a partial segment` /
  `a sibling block entry cannot cross a partial segment` — a block over a chain
  that can be absent.

Value forms:

- `this chain mints an optic value, not a read` — the chain is led by
  `@use`/`@typeof`/`@ty` with nothing to read through;
- `this chain mints a Setter value, not an update` — the same, on the update side
  (`o.@use(x) <- v`).

## Where the numbers are

[the benchmark matrix](../benchmarks.md#testssrcgenerated--shape-matrix-dsl-vs-hand-written)
— `@f` fused and `@f` unfused, against the hand-written rebuild across depth,
width, enum, `Option` and block shapes. This harness is not a row in it: it
*is* the hand-written rebuild, which `scripts/check_codegen.sh` enforces. What it
does contribute is the `Option8` shape, which `@f` cannot express at all.