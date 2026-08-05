# The @Lucida DSL

`@Lucida` is the library's one macro. Hand it a chain — a source spelled left
to right, segment after segment — and the expression evaluates the focus at
the end. The same syntax writes: mark the chain with `<-` and a new value,
and the expression returns a new whole with that value at the focus —
nothing mutates. This page is the reference for every form the macro
accepts. The kinds behind the segments are the five structs of
[first-class optics](first-class.md); what the macro builds from them is
[composition](composition.md).

## Grammar

```text
@Lucida(<chain>)                        // read: evaluates to the focus
@Lucida(<chain> <- <newValue>)          // write: evaluates to the new whole
@Lucida[unfuse](<chain>)                // read, forced onto the composed path
@Lucida[unfuse](<chain> <- <newValue>)  // write, forced onto the composed path
```

- `<chain>` is the macro's single argument: one chain expression, optionally
  followed by `<-` and the new value. The arrow is the only write spelling —
  a comma form is not rejected, but extra comma-separated arguments compile
  as a read and are silently ignored: `@Lucida(o.name, "Denver")` is the
  read `@Lucida(o.name)`. If a write didn't take, check for the arrow. An
  empty call fails with `@Lucida expects at least one argument`.
- A read evaluates to the focus. If any segment is partial (`?.`), the read
  evaluates to `Option` — `Some(payload)` on a match, `None`
  carrying the original source on a miss.
- A write evaluates to a new whole with `newValue` at the focus; the source
  comes out untouched. A partial write is unconditional: when a segment
  misses, the write returns the source unchanged — the miss is an identity,
  wired in by the kind.
- `[unfuse]` is the only modifier. It changes the code shape, not the
  results ([when to unfuse](composition.md#when-to-unfuse)). Any other
  attribute is rejected: `@Lucida: unknown modifier 'X'`.

A chain is ordinary member-access syntax — `.` and `?.` between segments —
and it takes one of two shapes, which decides what the expression is:

- **Rooted at a value** — `o.customer.address.city.name`, `call().x` — the
  chain anchors at the value's type. A read evaluates the focus; a write
  applies to the value and returns the new whole. The same read rules apply
  to partial writes: `@Lucida(sq?.Circle <- Nested(99))` rebuilds on a
  match, returns the source unchanged on a miss.
- **Sourceless** — rooted at `@Type`, `@TypeOf` or `@Optic` — the chain names
  a focus without a source. A read mints the first-class optic of the
  chain's kind; a write mints a `Setter` with the new value baked in
  ([first-class optics](first-class.md)).

One example of each — the first two and the last two are verbatim from the
suite; the middle two spell the sourceless forms (the suite's own lens-mint
read is `@Lucida(@TypeOf(probeInstance).f)`):

```cangjie
@Lucida(o.customer.address.city.name)              // read: "Atlanta"
@Lucida(o.customer.address.city.name <- "Denver")  // write: a new Order
@Lucida(@TypeOf(c).zip)                            // mints a lens
@Lucida(@TypeOf(circleVal)?.Circle)                // mints an affine
@Lucida(@TypeOf(c).zip <- 99999)                   // mints a Setter
@Lucida[unfuse](o.customer.address.city.name)      // same read, composed path
```

## Chain segments

Every segment is one of the forms below. The first four continue a chain;
two anchors start one; `@Optic(o)` begins **or continues** one;
`coerce<T>()` continues one.

| Segment | Meaning |
|---|---|
| `field` | derived lens — a constructor field of a struct or class derived with `@DeriveOptics`; total, rides on `.` |
| `_0` … `_15` | tuple element lens — an element of a tuple riding the chain (a tuple-typed field, a multi-payload case's focus, a user optic's tuple focus); total, rides on `.`. Arity 2-16 generated (raising the bound is one generator argument, but high-arity generic declarations get build-time expensive — [compiler notes](../compiler-issues.md)); an update value for the whole tuple is a tuple literal |
| `CaseName` | derived case optic — a case of a derived enum; the focus is the payload for single-payload cases, a tuple of payloads for multi-payload cases, and `Unit` for payloadless ones; partial, rides on `?.` (the library kinds a case optic as an *affine* — same partial contract, same miss-is-identity) |
| `name()` / `name(args)` | user-declared method optic, declared with `@LucidaOptic` and called by name — total kinds (`Lens`, `Iso`) under `.`, partial kinds (`Prism`, `Affine`) under `?.`; generic ones take type arguments |
| `Array.at(i)` / `Array.selectFirst(pred)` | the library's own affines on `Array<T>` — the element at index `i`, the first element matching `pred`; partial, `?.` |
| `@Type(T)` | start anchor — begin the chain from the type `T` itself |
| `@TypeOf(expr)` | start anchor — begin from the type of `expr`; the anchor a value-rooted chain starts from implicitly |
| `@Optic(o)` | splice anchor — begin a chain with, or splice into a chain, the first-class optic value `o` (any of the five kinds, setters included; a chain that is only `@Optic(o)` hands the value back as a first-class optic) |
| `expr.coerce<T>()` | iso coercion between a one-field derivation and its field type; total, rides on `.` |

Notes the table leans on:

- `@Type`, `@TypeOf` and `@Optic` are themselves macros, valid only inside
  `@Lucida` — used anywhere else, each rejects itself:
  `@Type: macro should be contained inside '@Lucida'` (likewise for
  `@TypeOf` and `@Optic`).
- A derived case optic is affine-kind: its read can miss and its write
  returns the source untouched on a miss. That is why the segment carries
  `?.` and not `.` ([deriving](../examples/deriving.md) names the kind;
  [prisms](../examples/prisms.md) walks it).
- `Array.at` and `Array.selectFirst` are method optics the library declares
  on `Array<T>` — the same plumbing a `@LucidaOptic` declaration emits, so
  they mark and compose exactly like user-declared segments
  ([chains](../examples/chains.md) works both).
- `coerce<T>()` resolves against the iso a one-field derive emits, so `T`
  must be that field's type, spelled with exactly one type argument
  ([deriving](../examples/deriving.md)).

## Operators

Every segment carries one of two operators, and the mark names the
guarantee the optic behind it makes:

| Operator | Meaning | Segments it matches |
|---|---|---|
| `.` | total — the part is always there; read and write cannot miss | derived fields, `coerce<T>()`, `.`-marked user optics |
| `?.` | partial — a read evaluates to `Option`: `Some(payload)` on a match, `None` on a miss | derived case optics, `Array.at`, `Array.selectFirst`, `?.`-marked user optics |

A spliced `@Optic(o)` carries no mark of its own — the spliced optic's kind
decides the read: a spliced lens reads total, a spliced prism or affine
reads partial (the composed shapes are on
[composition](composition.md)).

The mark is an annotation, and the compiler holds each segment to it: the
macro checks every mark against the segment's kind, so a mismatch does not
compile.

- `.` on a partial optic — a total read of an optic whose read can miss:

  `@Lucida: '.' on a partial optic (Prism/Affine) — its forward returns Option, so a total read is impossible. Use '?.' and match Some/None.`

- `?.` on a total optic — a partial read of an optic that cannot miss:

  `@Lucida: '?.' on a total optic (Lens/Iso) — its forward cannot miss, so there is no Option to unwrap. Use '.' for a plain read.`

- `?.` on `coerce<T>()` is rejected at parse time, with the same reasoning:

  `@Lucida: '?.' on a total optic (coerce) — its forward cannot miss, so there is no Option to unwrap. Use '.' for a plain read.`

Writes obey the same marks with one deliberate asymmetry. A partial write is
unconditional — the miss is an identity — so a `.`-write through an
affine-kind optic is legal: its backward is sourceful and guarded, and a
miss keeps the source. A `.`-write through a `Prism`-kind optic, whose
backward rebuilds from the focus alone, is rejected:

`@Lucida: '.'-write through a prism — '.'-writes assert a match and would rebuild the source unconditionally on miss. Use '?.' to preserve the source on miss.`

The mark belongs to the segment, not the chain: after a `?.` segment the
chain returns to `.` for the total segments that follow
([chains](../examples/chains.md) walks mixed chains end to end). Every
diagnostic `@Lucida` can produce is collected in
[diagnostics](diagnostics.md).

## Starting a chain

A chain starts in exactly one of four ways:

- **A value** — any member access rooted at an expression:
  `o.customer.name`, `call().x.y`. The chain anchors at the value's type;
  the macro inserts the `@TypeOf` anchor for you.
- **`@Type(T)`** — the type itself, no value needed.
- **`@TypeOf(expr)`** — the type of an expression.
- **`@Optic(o)`** — a first-class optic value you already hold (the only
  anchor that may also appear mid-chain).

Everything else is rejected at the head of the chain. The derived and
user-declared segments are continuations — they need an owner — and
`coerce<T>()` cannot lead either:

- a derived field first — the walk fails with
  `@Lucida: a derived field optic cannot start a chain here`
  (hint: `Start the chain with the owning value, @Type, @TypeOf or @Optic`);
- a user-declared optic first —
  `@Lucida: user-defined method optics cannot start a chain` (same hint);
- `coerce<T>()` first — rejected at parse time with
  `Cannot make 'coerce<Type>()' method first`; the walk carries the same
  guard as a backstop, `@Lucida: 'coerce<Type>()' cannot start a chain`.

The start anchors are start-only in the other direction too. `@Type` or
`@TypeOf` in the middle of a chain fails with
`@Lucida: @Type is only allowed at the start of a chain` or
`@Lucida: @TypeOf is only allowed at the start of a chain`. And malformed
calls fail with their own messages: an argument that is not a chain at all
gets `Unknown expression, passed to @Lucida macro`; a write with nothing
before or after the arrow gets
`@Lucida expects a lens chain before '<-'` or
`@Lucida expects a value after '<-'`.

## Evaluation

The macro walks the chain once at compile time and emits code — either a
*fused walk* (the default) or a library composition. Which one you get is a
code-shape decision, not a semantic one; the results are the same.

- **Reads** fuse when the chain allows: each segment's halves are bound
  once, then read in one straight-line pass (`pinForward` for total chains,
  `pinPrismForward1`–`pinPrismForward8` for chains with partial segments —
  up to eight of them). Chains that splice a `@Optic` value in, or carry
  more than eight
  partial segments, fall back to the composed path: one
  `__OpticsCompositions.composeForward` step per segment.
- **Writes** evaluate through the backward: on the composed path one
  `__OpticsCompositions.composeBackward` step per segment, applied by
  `evalBackward(backward, source, newValue)`; on the fused path, one
  guarded backward fold bound by `pinBackward` and applied by the same
  `evalBackward`. The write returns the new whole.
- **Sourceless forms** stop short of applying: the composed halves are
  handed to `__FirstClassConstruction.perform`, which mints the optic
  (reads) or the `Setter` (writes)
  ([first-class optics](first-class.md)).

The fused write of `@Lucida(o.customer.name <- "Denver")` comes out as the
bindings below (generated code — the names are the macro's and the
library's, not calls to write by hand):

```cangjie
let __magical0 = magic({ => o })                       // the anchor: o's type
let __optics0  = __magical0.__downcast(__magical0)
let __fwd0 = __optics0.__customer_impl_forward
let __bwd0 = __optics0.__customer_impl_backward
let __magical1 = __magical0.__customer_optics(__magical0)
let __optics1  = __magical1.__downcast(__magical1)
let __fwd1 = __optics1.__name_impl_forward
let __bwd1 = __optics1.__name_impl_backward
let __fusedBackward = pinBackward({ => o }, { => "Denver" }, { src, fcs =>
    let __t0 = __fwd0(src)
    __bwd0(src, __bwd1(__t0, fcs))                     // right-to-left rebuild
})
evalBackward(__fusedBackward, o, "Denver")
```

(Each segment binds both halves even when the fold reads only one — here
`__fwd1` goes unread.)

`[unfuse]` skips the fused shape and emits the composed form — one
`composeForward`/`composeBackward` call per segment — which is also the
fallback shape ([composition](composition.md) documents the composed calls;
[the fusion walk](../architecture/fusion-walk.md) documents the fused one).

## Where to go next

- [First-class optics](first-class.md) — the five kinds the segment table
  resolves to, and the values the sourceless forms mint.
- [Composition](composition.md) — the kind-pair table a chain walks one
  step at a time, and what `[unfuse]` switches to.
- [Lenses](../examples/lenses.md), [prisms](../examples/prisms.md) and
  [chains](../examples/chains.md) — the segments in action, one kind at a
  time, then mixed.
- [Deriving](../examples/deriving.md) — what `@DeriveOptics` emits per
  type: the lenses, case affines and isos the first rows of the table ride
  on.
- [User-declared optics](../examples/user-optics.md) — bringing your own
  segments, marked `.` or `?.`.
- [Diagnostics](diagnostics.md) — every message `@Lucida` can produce,
  collected on one page.
- [The fusion walk](../architecture/fusion-walk.md) — what the fused path
  emits, segment by segment.
