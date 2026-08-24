# Design decisions

The three siblings own the machinery as it stands: [the macro system](macro-system.md)
describes what the three macros parse and emit, [registry
plumbing](registry-plumbing.md) the phantom registries the emissions land on,
and [the fusion walk](fusion-walk.md) the fused evaluation. None of them is
allowed to say "we tried something else first". This page is that record:
why Lucida is shaped the way it is — the roads not taken, the workarounds
in force, and the price each one costs. Where a sibling explains how a
mechanism works, this page links it and explains why the mechanism is worth
what it costs.

Two facts about Cangjie run through nearly every decision below, so they are
worth stating once, up front:

- **Declaration macros are purely syntactic.** They receive tokens and return
  tokens; there is no name resolution, no access to other declarations, no
  type information at macro time. Anything the compiler must decide happens
  after the splice, in overload resolution — or it does not happen.
- **A call through a stored closure never inlines.** A function value held in
  a struct field is opaque to the optimizer at the call site. A library whose
  optics are data pays an indirect call per segment per direction, forever.
  Everything in this library refuses to store behavior in values.

The repo carries its own history, and this page cites it as evidence: `libs/`
holds every generation of the library side by side, each earlier one kept out
of the build by a commented dependency line in the root `cjpm.toml`, and the
first week's notes (`notes/day1.md`) record the starting point in one line —
the most primitive kind of optics: get + set.

## The model journey

The library's model changed twice before it settled. Each stage is grounded in
a package that still sits in the tree, so every claim below can be checked
against the remains.

### Getters and setters

The first model is the textbook one: a lens is a pair of functions, a prism
adds a test, and the kinds form an interface hierarchy
(`libs/optics/v0/src/interfaces.cj`):

```cangjie
sealed interface Lens<S, A> <: Optional<S, A> {
    @Frozen
    prop view: (S) -> A
    @Frozen
    prop update: (S, A) -> S
    // ... plus a default preview for the Optional parent
}
```

Values implement the interfaces by holding the halves in fields:

```cangjie
private struct ValueLens<S, A> <: Lens<S, A> {
    @Frozen
    ValueLens(
        private let _view: (S) -> A,
        private let _update: (S, A) -> S
    ) {}
}
```

The chain entry point dispatched on the interface —
`magic<T, G>(_: Optional<T, G>): Magical<G>` — already returning a phantom
token typed at the focus. That dispatch-on-a-value shape is the stage's
undoing. Both halves are *data*: every read and every rebuild calls through a
stored closure, an indirect call the optimizer cannot see through, and every
composition builds a new closure to wrap the previous one. The shape itself is
the barrier — no optimizer setting removes it, because the call target is not
known until the field is loaded.

The barrier was found the honest way: a family of inlining benchmarks, one of
them crossing a package boundary on purpose, compared optics written as
lambda-valued members against the same optics written as `@Frozen` functions.
Replacing the stored lambdas with functions was its own commit ("Replaced
lambdas with functions"); the functions won, and the lesson became a design
rule: the library emits `@Frozen` functions and never stores optics in fields.
The rewrite lives on as the `libs/optics/v1` generation.

### The van Laarhoven encoding

The proper encodings from the literature were tried next, in a parallel
package that still sits in the tree (`libs/optics/v1-laarhoven/src/interfaces.cj`).
The van Laarhoven representation makes an optic a polymorphic function over
containers, and Cangjie can spell the surface of it:

```cangjie
@Frozen
public func createLensReader<S, A>(get: (S) -> A, set: (S, A) -> S): ((A) -> Const<A, A>) -> ((S) -> Const<A, S>) {
    { ret: (A) -> Const<A, A> => { s: S =>
        fmap({ a: A => set(s, a)},
            ret(get(s))
        )}
    }
}
```

with `Const<T, X>` and `Identity<T>` as the containers and `fmap` overloaded
for each. The encoding fell short twice, and both failures are visible in the
file itself. The engine of the van Laarhoven encoding is higher-kinded
polymorphism — `Const` is a functor in its *second* parameter — and the file
carries the attempt to say so as a comment: `// interface Functor<T> { }`,
with each struct declared `/* <: Functor<X> */`. Cangjie generics cannot
abstract over a type constructor, so `fmap` must be re-overloaded per
container, and the encoding's universally-quantified argument — the `ret` that
in the literature accepts *any* functor, making one lens value serve every
use — has no spelling. The reader/writer split is itself the evidence: two
functions where the literature has one, because each container must be spelled
out and chosen by the caller. And where the code did type-check, the optic was
still a closure value: the first model's inlining barrier, one level up and
unimproved.

A flat-composition variant was built alongside it (the
`libs/optics/v1-laarhoven-flat` generation) — the walk's composition
generated as one function instead of nested wraps, up to a fixed arity — which
bought back some of the call shape but kept the expressiveness ceiling.

What survived from this stage is not the encoding but its *trick*: hand the
compiler a function argument and let a type parameter of that argument carry
the decision. The registries are exactly that trick, rebuilt on the one
type-level channel that runs after a macro splice — overload resolution.

### Deforested optics and registries

The current model answers both barriers at once. Do not store behavior in
values — emit it as code: an optic's halves are `@Frozen` functions emitted
onto phantom registry types, addressed by exact name
([the macro system](macro-system.md) shows the emissions). Do not abstract the
composition — generate it: shared generic combinators per kind pair were
written first and abandoned, and the commit that commented them out says why
in its message ("Removed abstraction. It does not inline without it"). The
composition table is now generated — one specialized row per ordered kind
pair, each mirroring "the historically hand-written implementation 1:1", as
the host file's own header puts it. The fused walk finishes the job by
eliminating even the composed intermediates for chains the macro can see
end to end ([the fusion walk](fusion-walk.md)); the name of that elimination —
deforestation — is where this stage's name comes from.

Two small things survived every generation and are worth noticing, because
they mark the continuity: the chain's currency is still called `Magical` —
`RegistryMagical<T>` today, minted by `magic<T>()` exactly as in the first
library, where `magic` dispatched on the interface types — and the miss type
`Option`, born as the first model's `Optional.preview` result, is still what a
partial read returns ([first-class optics](../api/first-class.md)).

## No static assertions → diagnostic overloads

Cangjie has no static assertion a library can invoke, and after a macro splice
the compiler's verdict on a mismatched call is type-inference noise inside
generated code — technically precise, practically unreadable, and pointing at
an expansion the user never wrote. Misuse that deserves a sentence would
instead surface as a generic mismatch deep in the emission.

An earlier revision of the user optics made this pressure concrete. They
shipped with uniform affine shapes — every user optic reading as
`(S) -> Option<A>` and rebuilding sourcefully — so that the token-level
walk never needed to know a segment's kind. That worked, and it was wrong:
total reads returned `Option` needlessly, and every user optic composed as the
weakest kind, making composition kind-blind — a trade the
[changelog](../../CHANGELOG.md) records the removal of. The repair was
kind-exact shapes, which moved the kind decision to the call site: the
`.`/`?.` operator mark *promises* total or partial, and something must check
the promise against the kind the segment actually resolves to. The macro
cannot — it is syntactic ([registry plumbing](registry-plumbing.md) covers
why) — so the check happens where all post-splice decisions happen: in
overload resolution, via the gate functions (`__fwdApplyTotal`,
`__fwdApplyPartial`, `__bwdApply`, `__bwdApplyTotal`).

The diagnostic form follows from the resolution rules. Each illegal
mark–kind pair resolves *only* to an overload declared strict-deprecated:

```cangjie
@Deprecated[message: "@f: '.'-write through a prism — '.'-writes assert a match and would rebuild the source unconditionally on miss. Use '?.' to preserve the source on miss.", strict: true]
public func __bwdApplyTotal<T, S, A>(_: RegistryPrisms<T>, backward: (A) -> S, src: S, focus: A): S {
    backward(focus)
}
```

`strict: true` turns deprecation from a warning into a hard error, and the
message attribute is the diagnostic — written for that exact mismatch, naming
what was illegal and which operator to use instead. The wrong pair cannot
resolve to anything else: the legitimate overloads' parameter types exclude
it, so the trap is the *only* candidate, and the compiler prints its message.
This is the closest thing to a static assertion the language offers, and it
costs nothing at runtime — the gates' bodies are identities or plain
applications, and inlining erases the wrapping
([mark gates](fusion-walk.md#mark-gates)).

The limits are the form's edges. It is compile-time only: runtime behavior has
no error paths, because misses are values, not errors. It covers exactly the
pairs the gates wrap — plus the one parse-time special case (`?.` on a
coercion, [below](#what-coerce-costs)) — and nothing else; other failures
inside an expansion surface as ordinary compiler errors. The messages are
collected in [diagnostics](../api/diagnostics.md), which is the reference this
section is the rationale for.

## Purely syntactic macros → explicit-carrier generics

Generic user optics were first built with implicit inference: write
`source: GBox<Int64>` and the macro would treat any identifier in a
type-argument position as a type parameter to declare. The feature was built in `fee9e87` and reverted in `fb445d3`. It failed the
moment a user wrote a concrete
type: `GBox<Int64>` inferred a parameter literally named `Int64`, silently
widening the optic to any `GBox<X>`; a declaration with two concrete type
arguments failed with a misleading "single type parameter" error.

The root cause is not fixable, because it is the language's macro model: a
declaration macro sees tokens, not types, and `Box<T>` and `Box<Int64>` are
the same token shape — an identifier in angle brackets. No syntactic rule can
separate "a parameter" from "a concrete type spelled with an identifier";
deciding between them requires name resolution the macro does not have. Any
implicit rule is a guess, and the guess is wrong precisely when the user is
not writing a parameter.

The explicit route is the only signal the macro can see reliably, so it is the
design: type parameters come from the carrier struct's generic list —
`@Optic[...] struct boxLens<T> {}`
([user-declared optics](../examples/user-optics.md)) — and the receiver pins
them at call sites, the compiler inferring `T` from the receiver's registry
exactly as it would for any generic extension member.

The limit is the flip side of the reliability. A call site cannot name a
generic user optic's parameters explicitly: the generated members are
non-generic members of a generic extension, so explicit type arguments on them
are rejected by the compiler — the receiver, not the call, pins `T`. Manual
registries with member-level generics still accept explicit arguments (the
serialization benchmark in `src/bench/examples/` is built that way), but for
generated optics the carrier is the whole story. Multi-parameter carriers work
the same way — the parameters thread through the same emission header — and a
`where` clause on the carrier is rejected, for the same reason the derive
rejects one: the constraint would have to be re-derived onto every emitted
member, without being able to verify it, at macro time
([generics, and what is rejected](macro-system.md#generics-and-what-is-rejected)).

The explicit route also has a mechanical consequence worth recording here
because it was learned the hard way elsewhere: the carrier's generic list, as
the token API returns it, has no separator commas — the re-join is part of the
emission ([the comma section](#commas-supertype-lists-and-the-walks-reconstruction)
covers what that costs).

## What `coerce` costs

The coercion segment `x.coerce<T>()` is the one piece of the chain grammar the
library owns outright, and owning it reserves three things.

**The name.** Any `coerce<T>()` call in a chain *is* the coercion node — the
walk matches the identifier before anything else — so a user method optic
named `coerce` can be declared but never called in a chain. The price is paid
because the coercion has no user declaration to hang a member on: it must
exist for every type pair before any user code is written, which rules out
per-type emission, and the walk is syntactic, which rules out recognizing it
any way but by name. A reserved segment name is the only spelling that works;
leaving the name to users would make the grammar ambiguous at exactly the
point the macro has the least information.

**Single-field types only.** The iso pairs `coerce` resolves against are
emitted by the derive only for types with exactly one field. That is not
generosity the library withheld; it is what the pair *is*: a field swap —
`{ source => source.field }` forward, `{ focus => Wrapper(focus) }` backward.
A two-field type has no unique projection to build the backward from, and the
derive cannot invent a canonical one without guessing which slot a focus
occupies. So it emits nothing, and `coerce` on a multi-field type fails as an
ordinary unresolved-member error inside the expansion rather than a bespoke
message — a diagnostic-surface gap [open problems](#open-problems) records.

**No partial mark.** `x?.coerce<T>()` is rejected at parse time, before any
code is generated. Coercion is fixed-total: its forward cannot miss, so there
is no `Option` to unwrap and the partial mark promises semantics that do not
exist. The rejection happens at parse time for a reason worth keeping in mind
elsewhere: the segment's call is synthesized by the walk, and synthesized
tokens carry no source positions, so a later resolution failure would point
nowhere readable. Parsing rejects while a real token from the user's code is
still in hand.

What the price buys is the only segment that works with zero declarations on
the user side: derive a single-field wrapper and `coerce<Int64>()` composes it
into any chain, in either direction, with no members of your own.

## Enum case shapes

Derived enum optics cover every case shape. The forward binds the payloads
positionally and wraps them as one focus: the payload itself for a
single-payload case, a tuple for a multi-payload case, `Unit` for a
payloadless case — whose read doubles as a match check. The rebuild answers
the mirrored question — unpack the focus, rebuild the case — and the model
keeps its one-currency property: the accessor moves the chain's currency to
`RegistryMagical<Focus>` whatever the focus is.

The earlier design rejected zero- and multi-payload cases outright, on the
argument that a tuple focus turns diagnostics and chains into anonymous
slots. The cost was real but smaller than the cost of rejection:
Option-shaped enums and mixed-arity status enums — most real-world enums —
could not derive at all. The tuple focus won; where named access matters,
the payloads ride in a user-named struct and the chain walks into its fields
by name.

One deliberate nuance: case optics land on `RegistryAffines`, not
`RegistryPrisms`, because the affine contract is what a case can actually
honor — partial forward, *sourceful* backward whose miss is an identity. That
sourcefulness is the repair for the rebuild problem on the miss path: on a
miss the source is kept because nothing could be rebuilt from the focus alone
([prisms](../examples/prisms.md) walks the contract).

## The `__`-prefix and hygiene

Cangjie's macro API has no fresh-symbol facility — no gensym. Every identifier
a macro emits is a string its author chose, and nothing in the language can
keep a generated name from colliding with a user name. Hygiene, in the
strong sense, is not something these macros can *have*
([macro hygiene, today](macro-system.md#macro-hygiene-today) states exactly
what the current strategy covers and where it stops). What they have instead
is a namespace: the `__` prefix, reserved by documentation and used by every
emitted member, every sealed interface, and the runtime helpers the walk calls
by name. The reservation works because it is total at the member layer — a
user who avoids `__`-prefixed identifiers cannot collide with anything the
derive, the optic macro, or the runtime emits onto types.

The known gap is one layer down, and it is recorded here because it is a
decision rather than an oversight: the composed path's per-segment bindings
(`magic0`, `optics0ImplForward`) carry no prefix, while the fused path's
(`__magical0`, `__t0`) carry it. The exposure is the composed expansion's own
scope: a user identifier named exactly like a generated binding would be
shadowed by the emission. The window is small — the bindings live inside an
immediately-invoked lambda, and the user's expressions enter as thunks beside
them, not statements among them — but it is real, and it is the visible seam
of the no-gensym model: the prefix is a convention, and a convention has
edges. (Two reservations are made by parsing rather than prefixing: `coerce`, by
the chain grammar, and `source`/`focus`/`_source` as arg names, because they are the
slots of generated lambdas — [both prices](#what-coerce-costs) are paid for
the same reason.)

The sustainable answer is the one already in force: keep every generated name
in the reserved namespace and keep the reservation documented
([macro hygiene, today](macro-system.md#macro-hygiene-today) states the
strategy). A stronger fix waits on the language — fresh symbols in the macro
API — and until then the convention is the mechanism by decision, not debt.

## Type-witness dispatch

The registries are phantom witnesses: empty structs whose type parameters and
member lists are the entire content, with the values mere riders for the
types ([registry plumbing](registry-plumbing.md) documents the mechanism).
This section is why the dispatch is built this way and not the ways it was
tried.

The first library dispatched through real interfaces — `Optional`, `Lens`,
`Prism`, with value structs implementing them and `magic` overloading on the
interface type. Dispatch worked; everything around it did not. The optics were
closure-storing values, with the inlining barrier that implies, and the
interface route to genericity dead-ends at the same place the van Laarhoven
encoding did: Cangjie has no higher-kinded polymorphism, so there is no way to
abstract over the kinds themselves — each kind's members must live somewhere
concrete, and nothing can unify them from above.

What replaced it uses the channel that *does* exist and runs at the right
time. The macros emit calls before type checking; overload resolution runs
after; so the calls' overload sets *are* the kind decisions, made by the
compiler against the emitted members. A registry's type parameter says which
type the chain stands on; which registry a call resolves against says which
kind the segment rides. The design's wager — values say nothing, argument and
return types say everything — pays for itself twice over: the failure mode is
a compile-time error at the emitted call site, never a runtime miss, and the
same mechanism extends from dispatch proper (`__downcast`'s return type is the
kind decision) to the enforcement gates of the previous section, where the
registry argument is load-bearing even when the function shapes alone would
distinguish the candidates — a sourceless backward fits both an Iso's legal
`.`-write and a Prism's illegal one, and only the phantom tells them apart.

The limits are the flip side of the static guarantee, and they are accepted
deliberately. Resolution sees only types: there is no runtime polymorphism and
no way to query the machinery at runtime. A kind must have been emitted
somewhere before a chain can use it. And two optics of the same kind on the
same source share one registry — they are told apart by member name, never by
type.

## Commas, supertype-lists, and the walk's reconstruction

Two token-API behaviors shape the emission code, and both bit in production
before they were documented:

- The declaration-side API that returns a type's generic parameters yields
  *bare identifiers without separator commas*: the `<T, U>` of a two-parameter
  carrier arrives as the two identifier tokens `T`, `U`, and splicing them
  into an extend header renders `<T U>` — not Cangjie.
- The expression-side API behind the walk's parsed calls splices
  `typeArguments` with `&` separators — supertype-list semantics, `&` being
  how Cangjie spells a supertype constraint. The reconstructed call for
  `x.m<A, B>()` rendered `<A & B>`, which fails to parse.

The second one was a real bug: `x.m<A, B>()` failed at macro time with
`expected expression after '<'`, recorded in the changelog's call-site entry.
What made it cost more than the fix is the failure's *shape* — the user's
tokens were fine; the reconstruction, not the input, was broken — and the
error pointed at synthesized tokens that carry no source positions, so nothing
in the message could say that. Both re-emissions re-join parameter lists with
commas now — the user-optic carrier's header and the walk's reconstructed
calls share one helper for it (`commaSeparated`) — and the failure mode above
is why the re-join is treated as part of the emission, never as a given
([generic carriers](macro-system.md#generic-carriers) states the mechanism and
the general lesson).

The reason this is worth a section on a page about decisions is the class of
trap it exemplifies: token-level APIs preserve *lexemes*, not *grammar*. A
separator is grammar. Any emission that reassembles a list from token fields
must re-supply the grammar the fields dropped, and the failure mode is a parse
error far from the cause. The two workarounds are the same lesson learned
twice — once on the declaration side, once on the walk's side — and the
helper's existence is the lesson's monument.

## Open problems

- **Polymorphic optics.** Every kind is monomorphic: `Iso<S, A>`'s halves use
  one pair (`to: (S) -> A`, `from: (A) -> S`), a lens rebuilds into the same
  `S` it read from, and each registry carries a single source type parameter.
  The polymorphic encoding — read `S -> A`, rebuild `B -> T` — has no shape in
  the first-class structs, no registry, and no emission that would carry two
  source-side parameters through the walk. The registries could grow a second
  parameter; the emission surface (derive, user optics, stdlib, gates) is the
  part that would actually cost.
- **Diagnostic surface.** Macro-time diagnostics can only point at tokens the
  macro holds, and synthesized tokens carry no positions — the reason the
  coerce rejection is parse-time and the reason reconstruction bugs used to be
  unreadable. Some failures still surface as ordinary unresolved-member errors
  inside an expansion (coercion on a multi-field type, a body that cannot type)
  rather than bespoke messages; each would need a macro-time check that does
  not false-positive, which is exactly what the purely syntactic model makes
  hard.
- **Stdlib coverage.** The chain's built-in segments are two — `at` and
  `selectFirst`, both affine over arrays — plus generated tuple lenses up to
  arity three (experimental: emitted by the runtime, not yet exercised by the
  test suite or documented in the segment table). Each new segment is an
  interface-and-extend ceremony per type
  ([registry plumbing](registry-plumbing.md#the-downcast)), mechanical but
  unplanned; the list grows when a chain needs it to.

## Where to go next

- [The macro system](macro-system.md) — the emissions this page explains the
  shape of: what each macro parses, emits, and rejects.
- [Registry plumbing](registry-plumbing.md) — the phantom-registry mechanism
  [type-witness dispatch](#type-witness-dispatch) gives the rationale for.
- [The fusion walk](fusion-walk.md) — the fused emission and the mark gates
  whose diagnostic form [the overload section](#no-static-assertions--diagnostic-overloads)
  justifies.
- [Diagnostics](../api/diagnostics.md) — every message the strict-deprecated
  traps and the macros produce, collected on one page.
- [First-class optics](../api/first-class.md) — the five kinds whose shapes
  bound [the open problems](#open-problems) above.
