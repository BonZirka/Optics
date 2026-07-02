# The fused walk

When `@Lucida` evaluates a chain — a read like `o.customer.name` or a write
like `o.customer.name <- "Denver"` — the default emission is the *fused
walk*: the macro binds each segment's forward and backward halves once as
locals, then emits one straight-line pass over them. The big idea is that a
chain lowers to *direct nested calls*, not to repeated runtime compositions:
a read becomes one application of a pre-shaped walk
(`__gfwd1(__gfwd0(src))`, where `__gfwdI` is segment *I*'s mark-checked
forward — [mark gates](#mark-gates) below), a write one right-to-left
rebuild, and no per-segment optic value is ever constructed. Both emissions
produce the same results; they differ only in closures allocated.

Which chains fuse is decided at the end of [the macro
system](macro-system.md#fused-or-composed)'s pipeline. This page is the
fused emission itself: what fusion is, the pin helpers that make the emitted
lambdas type-check, the pinned prism walkers that carry partial reads, the
operator-mark gates wrapped around every segment, and the conditions under
which the macro skips fusion and composes instead. The composed path the
fallback takes, and the `[unfuse]` switch that forces it, are
[composition](../api/composition.md#when-to-unfuse)'s subject; the registry
values every binding rides on are [registry
plumbing](registry-plumbing.md)'s.

## What fusion is

Fusion is the compiler trick of eliminating an intermediate structure that
one stage builds only for the next stage to consume. In the
functional-programming literature the elimination of such intermediate data
is called *deforestation*: a pipeline of list transformations, evaluated
naively, builds and immediately discards an entire list per stage, and
deforestation rewrites the pipeline into one pass that never materializes
them. A database query planner makes the same move when it fuses a scan, a
filter and a projection into a single pipeline instead of executing each
stage to completion. What plays the intermediate structure here is a
function value. The composed path is itself a pipeline: per segment it
upcasts the kind the chain has committed to and builds a *new* composed
function from the halves walked so far, one per direction ([the macro
system](macro-system.md#the-composed-walk) shows the expansion). Each of
those composed functions exists only to be handed to the next segment's
composition step — built, consumed, discarded. The fused path never builds
them. It binds the halves the segments already ship with and emits the
application directly, so the only per-segment function values left in the
expansion are the halves themselves — the intermediate composed functions
are gone.

Two properties make the elimination safe to attempt. First, the macro sees
the whole chain at expansion time: it knows every segment's node kind, so it
can choose the walk's shape instead of discovering it at runtime. Second,
fusion is a code-shape decision, not a semantic one — the composed path
remains for every chain the walk cannot carry, and both emissions produce
the same results. A gate that can fail safely is worth having; one that had
to be right about every chain would not be.

The easy way to evaluate a chain would be to always compose — one mechanism,
no special cases. The fused walk exists because the composed closures are a
real runtime cost the macro can see and remove: it holds the entire chain
statically, so the per-segment wrapping can be replaced with the plain
nested calls the wrapping would have ended up applying anyway. What the
macro cannot see — a first-class value's pre-composed halves, or a chain
whose segments it cannot address by name — falls back to composition
([when fusion is skipped](#when-fusion-is-skipped)). Why the system settled
on this division of labor — the model journey from declaration to emission,
and the shape of the emissions themselves — is [design
decisions](design-decisions.md)' subject.

## The pin helpers

Every fused emission binds a walk as a lambda literal — `{ src => ... }`
for a read, `{ src, fcs => ... }` for a write — and a bare lambda literal is
exactly what Cangjie cannot type on its own. The runtime package's pin
helpers (`magical.cj`) are the workaround, and their header comment is the
whole rationale:

```text
// ===== Fusion type-pinning helpers =====
// Cangjie cannot infer lambda parameter types from the lambda body alone.
// The macro passes a source-providing thunk () -> S whose return type pins S,
// allowing the walk lambda (S) -> R / (S, R) -> S to be typed without an IIFE.
```

The three helpers:

```cangjie
@Frozen
public func pinForward<S, R>(sourceThunk: () -> S, walk: (S) -> R): (S) -> R {
    { s: S => walk(s) }
}

@Frozen
public func pinBackward<S, R>(sourceThunk: () -> S, targetThunk: () -> R, walk: (S, R) -> S): (S, R) -> S {
    { s: S, r: R => walk(s, r) }
}

@Frozen
public func pinBackwardSourceless<S, R>(targetThunk: () -> R, walk: (R) -> S): (R) -> S {
    { r: R => walk(r) }
}
```

The mechanism is overload resolution doing type inference by proxy. The
macro emits the walk lambda *unannotated* as an argument to `pinForward` or
`pinBackward`; the helper's parameter types — `(S) -> R`, `(S, R) -> S` —
are what the checker reads the lambda against, and `S` and `R` are pinned by
the thunk arguments' return types, which the macro can produce because the
source and target expressions are concrete tokens. The easy way — an
immediately-invoked lambda with the parameter types written out, or an
explicit annotation at every binding — would require the macro to name types
it does not know: the macro is syntactic, and `S` is whatever the source
expression's type turns out to be after type checking, not something the
macro can spell. The thunks remove the need to spell it.

The thunks are never called. Like the `magic` entry points they share the
trick with, they exist to carry a type — the source and target expressions
ride in as `() -> S` and `() -> R` so that a side-effecting expression is
not evaluated just to pin the anchor. The expansion applies the source (or
source and target) afresh at the tail of the walk, so the user's expressions
are evaluated exactly once each, in the tail call — and the thunks must not
evaluate them a second time on the way in.

Where each helper is used:

- `pinForward({ => source }, { src => walk })` binds the read walk of an
  all-total chain — the plain nested applications of the gated forwards
  (`eval_macro.cj`).
- `pinBackward({ => source }, { => target }, { src, fcs => fold })` binds
  the fused write's fold, then `evalBackward` applies it — the same
  application the composed write tail uses. (`evalBackward`'s two overloads
  pick sourceful or sourceless by the backward's function type; the fused
  backward is always the sourceful `(S, R) -> S` shape.) The generated fused
  write is shown in full in [the DSL
  reference](../api/dsl.md#evaluation)'s evaluation section.
- `pinBackwardSourceless({ => target }, { fcs => walk })` is the family's
  sourceless shape — a walk consuming only the new focus, `(R) -> S`, pinned
  by the target thunk alone. It sits in the macro's naming table
  (`naming.cj`) beside the others, but no current emission calls it: the
  fused write binds its fold with `pinBackward` even for chains containing
  iso segments, because the fold applies a sourceless backward directly
  where the chain coerces.

The limits are the shape of the pin itself: the backward pin fixes the
walk's arity at two (`src`, `fcs`), and the walk body must produce its
result without further type annotations from the macro. Everything that
needs more — Either construction, per-kind dispatch — is pushed into the
library's pre-written walkers (below), whose signatures already carry the
types.

## Prism fusion

A read through an all-total chain is a plain nested call. A read through a
chain with partial segments cannot be: a miss anywhere must yield
`Left(original source)`, and the result of the whole read is an `Either`.
The macro's name for a segment whose forward returns an `Either` is
*either-producing*, and the comment that defines it (`eval_macro.cj`) is
precise about the two sources:

```text
// Either-producing segments: derived prisms and partially-marked user optics
// ('?.') return Either<T_in, A> and occupy the pinned prism slots; totally-marked
// ('.') user optics walk like derived lenses.
```

One clarification before the walkers. "Derived prism" is the node kind a
`?.` mark creates on a derived segment; the registry beneath it may be
`RegistryAffines`, since a case optic is affine-kind — [the macro
system](macro-system.md) covers the derive's registries. The gates below key
on the registry, so the mark check stays kind-exact either way.

Partial reads walk through the pinned prism family, `pinPrismForward1` –
`pinPrismForward8` (`magical.cj`, all `@Frozen`). The smallest member shows
the shape the whole family repeats:

```cangjie
@Frozen
public func pinPrismForward1<S, T1, A1, B>(
    sourceThunk: () -> S,
    fwd1: (T1) -> Either<T1, A1>,
    run0: (S) -> T1,
    cont1: (A1) -> B
): (S) -> Either<S, B> {
    { s: S =>
        match (fwd1(run0(s))) {
            case Right(a1) => Right<S, B>(cont1(a1))
            case Left(_) => Left<S, B>(s)
        }
    }
}
```

The walkers are not curried pipelines — each takes its pieces as one flat
argument list and returns a single lambda, `(S) -> Either<S, B>`. For `K`
either-producing segments, `pinPrismForwardK` takes:

- the source thunk, pinning `S`;
- one `fwdI` per partial segment — the segment's pre-bound forward (its
  gated copy, [mark gates](#mark-gates)), typed `(TI) -> Either<TI, AI>`;
- one run lambda per total stretch *before* each partial segment — the
  first takes the source `s`, the rest take the previous partial's payload
  (the emission names those parameters `__eI`);
- one continuation after the last partial segment — the total stretch
  trailing the chain, or the identity when the chain ends on a partial.

So for a schematic chain `x?.a.b?.c` (two partial segments around one total
segment `b`), the macro emits `pinPrismForward2` with an identity `run0`
(nothing total before `a`), a `run1` applying `b`'s gated forward, and an
identity `cont2` (nothing after `c`). Any `Left` short-circuits to
`Left(original source)` — note the `s` in `Left<S, B>(s)` is the walker's
own parameter, the original source, not an intermediate — and a full match
threads each payload through the next run into `Right(final focus)`.

The family exists because of the same constraint the pin helpers solve, one
level down. The macro cannot emit the nested `match` itself: the library's
walkers spell the `Right`/`Left` constructors out with their type arguments
(`Right<S, B>(...)`), and the macro — which never resolves a type — cannot
name `S` or the payload types. The comment above the family (`magical.cj`)
states the division this forces:

```text
// ===== Fused prism-chain forward =====
// The macro emits only top-level sibling lambdas (segment runs); every lambda's
// parameter and return type is pinned by the concrete pre-bound segment forward
// arguments, never by another lambda's body. Semantics mirror the library's
// composed forward: any prism miss short-circuits to Left(original source),
// a full match yields Right(final focus).
```

The macro emits the *sibling* run lambdas — flat, one per total stretch —
whose parameter and return types the walker's signature provides, and the
library's pre-written body supplies all the nesting. The runs are built from
the gated forwards, so a partial read is mark-checked at every segment,
prisms included.

The cap is real and the family is its reason: the walkers come in fixed
arities, one function per count, each typing its own nesting, and the family
stops at eight. A read with *exactly* eight either-producing segments still
fuses (`pinPrismForward8`); more than eight falls back to composition — the
macro counts the partial segments (`countEitherSegments` in
`eval_macro.cj`) and compares against the largest helper. Reads only: the
backward walk is not capped, because it needs no fixed-arity family at all.
Its partial segments are handled by inline guards — in the emission's own
naming, schematic, for the first partial segment of a chain:

```cangjie
if (let Right(__t0) <- __fwd0(src)) { /* the rest, nested */ } else { src }
```

— which only *destructure* (a pattern position needs no type arguments),
while the forward walk must *construct* `Right`/`Left` (a constructor
position cannot avoid them). The guards nest as deep as the chain does, a
miss at any depth yields the original source, and every emitted type stays
concrete (`emitFusedBackwardBody` in `eval_macro.cj`). The write keeps the
ungated forwards for a separate reason: a `.`-write through an affine is
legal — its backward is sourceful — so gating the forwards would reject a
legal write; the mark is checked on the backward side instead
([mark gates](#mark-gates)).

## Mark gates

The operator mark is a promise the call site makes; the kind is a fact about
the members the segment resolves to. The two are made by different parties —
the user writes `.` or `?.`, the derive or the optic declaration fixed the
kind long before — and something must check that they agree. The macro
cannot: it is syntactic and never resolves a member. The check therefore
happens where all kind decisions in this system happen — in overload
resolution — via the gate functions of `magical.cj`. The header comment is
the section in miniature:

```text
// ===== Per-segment forward gates =====
// The macro wraps EVERY segment's forward binding with one of these, so the
// operator mark is checked against the segment's kind registry right at the
// binding site — mid-chain or tail, derived, user, or stdlib. Total-marked
// ('.') segments pass through Lenses/Isos; a Prisms/Affines registry means
// the mark contradicts a partial kind. Partial-marked ('?.') segments pass
// through Prisms/Affines (Either forward); a Lenses/Isos registry means the
// mark contradicts a total kind. Bodies are identities: the gates exist for
// overload resolution, and inlining makes them free at runtime.
```

Four families, all in `magical.cj`:

- `__fwdApplyTotal` — resolves for a `.`-mark against `RegistryLenses` or
  `RegistryIsos`; the `RegistryPrisms`/`RegistryAffines` overloads are the
  strict-`@Deprecated` traps (a partial optic's forward returns `Either`, so
  a total read is impossible).
- `__fwdApplyPartial` — resolves for a `?.`-mark against `RegistryPrisms` or
  `RegistryAffines`; the `RegistryLenses`/`RegistryIsos` overloads are the
  traps (a total optic's forward cannot miss, so there is no `Either` to
  unwrap).
- `__bwdApply` — the arity eraser for `?.`-marked user segments. A partial
  user optic may be a Prism (sourceless backward) or an Affine (sourceful),
  and the macro cannot tell them apart; the fold always calls the
  two-argument form and the overload set picks by the backward's function
  type:

  ```text
  /// Erases backward arity for kind-exact user optics: the fused backward fold
  /// always calls this two-argument form; the overload set dispatches on the
  /// bound backward's function type (sourceful (S, A) -> S vs sourceless (A) -> S).
  ```

- `__bwdApplyTotal` — the `.`-marked user segment's backward gate. Its own
  doc comment carries the trap's reasoning verbatim:

  ```text
  /// Total-expectation backward apply for user optics: the macro passes the
  /// segment's optics registry as a pure phantom. Sourceful kinds (Lens/Affine)
  /// and total sourceless kinds (Iso) have matching overloads; a '.'-marked
  /// PRISM write has none — unconditional rebuild on miss is exactly the
  /// semantics '.' must not grant a partial optic, so it fails to compile.
  ```

Routing — which segments pass through which gate — differs between reads and
writes, and the asymmetry is the point:

- **Reads** gate every segment on the mark. The emission binds a gated copy
  per segment, `let __gfwdI = __fwdApplyTotal|__fwdApplyPartial(__opticsI,
  __fwdI)` (`emitFwdGateBindings`, `eval_macro.cj`), choosing the family by
  the mark (`?.` → partial, `.` → total) and letting the registry argument
  deliver the verdict. The read walk runs on the gated copies.
- **Writes** keep the ungated forwards — the backward body walks them to
  compute the values entering each segment — and check the mark on the
  backward side instead. Gating the forwards would reject a *legal* write: a
  `.`-write through an affine is fine (its backward is sourceful and keeps
  the source on a miss), even though its forward returns `Either` and a
  total forward gate would trap it. So the fold routes by segment kind:
  derived segments call their backward directly (always sourceful, miss
  guards baked into the derive's emission); coercions call theirs directly
  (always sourceless); a `.`-marked user segment goes through
  `__bwdApplyTotal` — legal for Lens/Affine/Iso registries, the
  strict-deprecated trap for Prisms; a `?.`-marked user segment goes through
  `__bwdApply`, legal either way.

The backward-total gate is also where the phantom registry argument stops
being ceremony and becomes load-bearing. A sourceless backward `(A) -> S`
fits both an Iso — a legal `.`-write — and a Prism — an illegal one. The
function type alone cannot separate two opposite verdicts; only the registry
argument can, and that is what `__bwdApplyTotal` passes as its first
argument. On the forward gates the function shapes already separate the
families (a total forward is never `Either`-returning), and the registry
keeps the check tied to the segment's kind rather than its shape.

The forward gates return the function they were handed — identity bodies —
so the entire mechanism costs nothing at runtime: resolution happens at
compile time, and inlining erases the call. (The backward gates apply their
backward rather than return it; their check is the same shape.) What the
mechanism buys is the
diagnostic: a mark that contradicts the kind resolves *only* to a
strict-`@Deprecated` overload, which fails compilation with a message
written for that exact mismatch — what was illegal, why, and which operator
to use instead. The messages are collected in
[diagnostics](../api/diagnostics.md); why the diagnostic takes the form of
an overload at all is [design decisions](design-decisions.md)' subject. The
gates have no `RegistrySetters` rows because no fused walk can hold one:
setters are not declarable, a first-class setter enters through the composed
path only, and the gate lattice covers exactly the registries a fused chain
can bind.

## When fusion is skipped

The gate itself is small (`eval_macro.cj`): a read or write fuses when
`[unfuse]` is absent and the chain passes `isFusible` — the first node must
be an anchor that is not an `@Optic` splice, and every segment after it must
be derived, user-defined, or a coercion (the emitters restate this check as
`isFusableChain`). Shape selection then runs inside the
emitters: an all-total read walks through `pinForward`; a read with partial
segments walks through the pinned prism family if it has at most eight,
otherwise composes; a write folds through `pinBackward` unless a
non-fusable segment kind appears. Every failure lands on the same composed
path — the same one `[unfuse]` forces — which is what makes the gate safe to
fail.

The triggers, in the order the source checks them:

- **`[unfuse]`** — the attribute skips the gate entirely and forces the
  composed path. It changes the code shape, not the results
  ([composition](../api/composition.md#when-to-unfuse) shows the unfused read
  and write expansions, and covers when to reach for it deliberately).
- **An `@Optic` splice anywhere in the chain** — at the head (`isFusible`
  rejects an `Optic` first node) or mid-chain (the segment-kind check
  rejects it past the anchor). A first-class value already carries its
  composed halves — there are no chain segments to bind, so there is nothing
  to fuse; the walk binds the value's halves directly and composes from there ([registry plumbing](registry-plumbing.md) shows the splice
  emission). Of the kinds a viable chain can carry, this is the only one the
  "derived, user-defined, or coercion" check ever rejects: mid-chain
  `@Type`/`@TypeOf` parse fine but fail outright as errors in the walk's
  dispatch ([the DSL reference](../api/dsl.md#starting-a-chain) documents
  that failure) — they never reach the shape decision at all.
- **More than eight partial segments in a read** — the pinned prism slots
  run out at eight, and a ninth either-producing segment sends the read to
  composition. Exactly eight still fuses. Writes are not capped: the
  backward fold's inline guards nest arbitrarily.
- **Segments the walk cannot carry** — the same kind check, stated from the
  emitter's side (`isFusableChain`): only derived segments, user-declared
  optics used by name, and coercions have members the macro can address by
  name, and only they bind. Anything else composes.

One form never reaches the gate at all: a sourceless chain — rooted at
`@Type`, `@TypeOf` or `@Optic` with no value to apply to — mints a
first-class optic or a `Setter` instead of evaluating a focus. The fused
walkers exist to apply a chain to a source and produce a result; a
sourceless chain stops short of applying, and its composed halves go to
`__FirstClassConstruction.perform`
([the macro system](macro-system.md#the-composed-walk) covers the tail,
[the DSL reference](../api/dsl.md#evaluation) the user-facing forms).

## Where to go next

- [The macro system](macro-system.md) — the emitter side of everything
  above: how the chain is parsed into nodes, how the composed path's CPS
  fold works, and where the fused-or-composed gate sits in the pipeline.
- [Registry plumbing](registry-plumbing.md) — the registry types the gates
  dispatch over and the downcasts that produce them; the
  phantom-argument-as-message pattern the gates lean on.
- [Composition](../api/composition.md) — the composed path this page's
  fallback takes: the per-segment steps fusion eliminates, the upcast
  lattice behind them, and the `[unfuse]` contract.
- [The DSL reference](../api/dsl.md) — the user-facing contract all of this
  implements: the operator table the gates police, and the generated fused
  write in the evaluation section.
- [Diagnostics](../api/diagnostics.md) — the strict-deprecated traps'
  messages, each with its cause and fix, collected on one page.
- [Design decisions](design-decisions.md) — why the diagnostics travel as
  overload sets, and the reasoning behind the emission shapes this page
  describes.
