# Changelog

## 2026-10-02 — breaking: `@Optics` removed; generated interfaces are signature-mangled

A user optic is now one standalone declaration. `@Optics({ ... })` is gone,
and the kind macros no longer need a parent block:

```cangjie
@Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
struct slen {}

@Prism[source: Array<Int64>, focus: Int64, forward: { source.get(0) }, backward: { [focus] }]
struct spar {}
```

`@Lens`, `@Prism`, `@Affine` and `@Iso` are plain aliases for
`@Optic[kind: <Kind>, ...]`.

Same-named optics over different source types now coexist in one package with
no namespace to keep them apart. Each declaration mangles its three generated
interfaces from its own signature (kind, source, focus, args) rather than from
the optic name alone. Mangling is by byte: `[A-Za-z0-9]` verbatim, `_` as `_u`,
every other byte as `_x` + two lowercase hex digits. So `Array<T>` mangles to
`Array_x3cT_x3e` and `(T) -> Bool` to `_x28T_x29_x20_x2d_x3e_x20Bool`. An
earlier attempt derived readable names from token values and failed on generic
function types, leaving a bare `-` in an identifier; backtick quoting was tried
and abandoned for the same reason.

Member names are unchanged — `__method_<name>_impl_forward` and
`__downcast_method_<name>` still key off the optic name, because a chain
resolves them by name and cannot know which of several same-named declarations
it meant. Those members live on `RegistryMagical<Source>`, so two same-named
optics must still differ in source type. A true duplicate (same name and same
signature) cannot be detected across macro invocations and surfaces as cjc
`redefinition of declaration '__<name>_impl_...'`.

The empty carrier struct is parsed for its optic name and generic parameters but
no longer re-emitted. It carried no members and was referenced by no generated
code, so once the interfaces were separated it was a second collision point.

`@Optics` existed only to unify same-named optics onto shared interfaces and
host the mixed-args/mixed-kind/duplicate checks. With per-signature interfaces
there was nothing left for it to do, and removing it is what let the kind macros
become standalone aliases.

The kind aliases now expand through the same implementation as `@Optic` rather
than re-expanding it, so a diagnostic blames the macro you wrote — `@Prism:
field 'forward' must be a { ... } block`, not `@Optic: ...`. Since an alias
fixes the kind it also rejects a redundant `kind:` field (`@Lens: takes no
'kind' field`).

Two checks that `@Optics` used to perform no longer happen, because comparing
two declarations needs shared state that separate macro invocations do not
have:

- Same name, different `args:` is now **accepted** rather than rejected. Over
  different sources the members live on different registries, so both
  declarations work; a mismatched `args:` you did not intend goes unwarned.
- Same name and `source:`, different `kind:` still fails, but as a cjc
  return-type clash on `__downcast_method_<name>` rather than a bespoke
  message.

Both are covered by probes in `scripts/check_diagnostics.sh` so the failure
modes cannot change unnoticed.

The byte mangle canonicalises whitespace: a run of spaces or tabs collapses to
one `_x20` and newlines are dropped, so a type written across lines mangles the
same as one written inline and generated identifiers stop growing with the
author's indentation.

## 2026-09-29 — additive: `;`-separated optic chains in blocks

Block entries are now arbitrary optic chains separated by `;` —
`@f(o.{ .i.a; .n } <- (7, 8))` writes through `o.i.a` and `o.n` in one
fused shell (per-chain fused walks threaded through the owner), and the
read form evaluates each chain's fused forward at the owner and returns
the tuple. Each chain must start at a plain field access, and the
starting fields must be pairwise distinct (bespoke diagnostic) so two
chains never write the same field twice. The old space-separated form
now parses as one chain, so multi-field blocks must use `;`.

## 2026-09-29 — additive: tuple access splitting in blocks `@f(tup.{ ._0 ._4 ._9 })`

Blocks compose with the generated tuple lenses (arities 2..16): the block
entries `._i` are the tuple's element optics, so a read returns the focused
sub-tuple and a write rebuilds the 10-tuple with only the listed elements
replaced.

## 2026-09-29 — additive: sibling-block reads `@f(s.{ .f1 .f2 })`

The block form now also reads: without `<-` it evaluates each listed
field's forward at the anchor chain's owner and returns a tuple of the
reads (a bare value for a single field — Cangjie has no 1-tuples).
`@f(o.{ .i .n })` is one fused walk to the owner plus per-field accessor
calls.

## 2026-09-29 — additive: sibling-block updates `@f(s.{ .f1 .f2 } <- (v1, v2))`

A brace block after a chain anchor lists lens fields on the chain's owner
value; the `<-` target is a tuple spread across them in order. The emission
is one fused walk: the anchor chain is probed once, the block's backwards
apply sequentially on the threaded owner, and the anchor fold wraps the
result — so `@f(o.i.{ .a .b } <- (5, 6))` is a single traversal. Only plain
lens fields are allowed inside the block (no `?.`, no nested paths, no
calls); with a single field the target need not be a tuple. Block updates
require a fusible value anchor; `@use(...)` anchors and `[unfuse]` are not
supported.

## 2026-09-29 — additive: `@Optics({ ... })` namespaces for user optics

A namespace collects several optics in one declaration; kind attributes
(`@Lens[...]`, `@Prism[...]`, `@Affine[...]`, `@Iso[...]`) replace the
`kind:` field and validate before the namespace sees them (macros expand
bottom-up and leave a `@__OpticDecl[kind: K, ...]` marker for `@Optics` to
read):

    @Optics({
        @Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
        struct slen {}

        @Lens[source: Array<Int64>, ...]
        struct slen {}
    })

Same-named optics over **different source types** are the point: each name
gets one pair of unified interfaces (`__<name>_impl`, `__<name>_accessors`)
with one conformance per declaration, so the per-optic carrier/interface
redefinition that blocked same-package overloading disappears. Same-named
optics must still differ in source type, share the `args:` list, and agree
on kind per source — violations get bespoke diagnostics. Standalone
`@Optic[...]` declarations are unchanged.

## 2026-09-29 — additive: `@Optic` bodies may rename the slots

A body written with a leading parameter list binds its names to the kind's
slots positionally — `forward: { s => s.v }`, `backward: { s, d => ... }`,
one name for a Prism/Iso backward — and `_` skips a slot. Bare bodies keep
the fixed `source`/`focus` names; nothing breaks.

## 2026-09-29 — breaking: `@Optic` body slot `src` renamed to `source`

Bodies in `@Optic[...]` declarations now name the source slot `source`,
matching the `source:` field spelling (`forward: { source.v }`). The
reserved arg names are `source`, `_source` and `focus`.

Migration: replace `src` with `source` inside `@Optic` bodies
(`sed -i 's/\bsrc\b/source/g'` per optic file is safe — the slot is the
only bare `src` in a body).

## 2026-09-25 — breaking: macro names shortened

- `@Lucida(...)` → `@f(...)`
- `@LucidaOptic[...]` → `@Optic[...]`
- `@Optic(o)` → `@use(o)` (run this replacement first — `@Optic` is reused
  for the declaration macro)
- `@Type(T)` → `@ty(T)` (`type` is a Cangjie keyword)
- `@TypeOf(expr)` → `@typeof(expr)`
- `@DeriveOptics` unchanged

Migration is mechanical — replace old names in this order: `@LucidaOptic` →
`@optic`, `@TypeOf` → `@typeof`, `@Type` → `@ty`, `@Optic` → `@use`,
`@Lucida` → `@f`. All 193 law tests and the 15 diagnostics probes pass under
the new names.

## 2026-09-25 — breaking: `Either<S, A>` replaced by `Option<A>`

Partial reads now answer in the standard `Option<T>` everyone knows —
`Some(focus)` on a match, `None` on a miss — instead of a custom
`Either<Source, Focus>` whose `Left` handed the source back.

- **Why**: a `Left(source)` read like "here is a copy of the object you
  passed in" invites exactly the wrong question (same object or a copy?).
  The source is the value the caller passed in and it is untouched — the
  miss carries nothing, so the question never arises. It also turned out the
  carried source was pure redundancy: every internal consumer already had it
  in scope, and `@LucidaOptic` forwards get simpler (`None` instead of
  `Left(src)`).
- **Migration**: `Right(x)` → `Some(x)`; `Left(src)` → `None` (use your own
  source variable — it is unchanged); `Either<S, A>` → `Option<A>`.
- `Either` is removed from `lucida`; matches on partial reads use
  `case Some(...)` / `case None`.

## 2026-09-25 — tuple element lenses up to arity 16

- `@GenerateTupleExtendsLenses` now generates, per arity 2..16, the
  `RegistryLenses` element impls **and** the `RegistryMagical` accessors +
  `__downcast` (previously the latter were hand-written for arities 2-3 only).
  The DSL reaches elements as `._0` .. `._15`, total segments riding on `.`.
- The generator is a memoized CPS walk: each arity's accumulated pair block
  is evaluated exactly once (memoized per (level, arity)) and the per-arity
  extends are joined in one flat pass. The original CPS formulation
  re-spliced its grown buffer through nested `quote()` interpolations, which
  cost 6.4 s at arity 16 and 117 s at arity 20 in macro evaluation alone;
  the memoized form does the same output in 0.1 s. Details and the remaining
  compiler-side costs are recorded in [compiler notes](compiler-issues.md).
- 20+ law tests cover whole-tuple and element reads/writes, nested tuples,
  chains through element structs, enum-case tuple focuses, first-class
  lenses, and a user-declared optic with a tuple focus.

## 2026-09-25 — enum derive covers every case shape

- `@DeriveOptics` no longer rejects payloadless or multi-payload enum cases.
  Every case derives a case optic: a single-payload case focuses the payload
  itself, a multi-payload case focuses the **tuple of payloads** (the update
  value is a tuple literal), and a payloadless case focuses `Unit` — reading
  it doubles as a match check.
- All case optics remain affine-kind (`?.`-marked, miss-is-identity).
- The two derive-time errors for case shape are gone, along with their
  diagnostics-gate probes.

## 2026-09-10 — call-site type arguments fixed for multi-parameter members

- The `@Lucida` walk reconstructs segment calls with their explicit type
  arguments before classification. The raw splice emitted type argument lists
  with `&` separators (supertype-list semantics), so `x.m<A, B>()` failed at
  macro time with `expected expression after '<'`. Type arguments are now
  comma-joined (`libs/macro-optics/v2/src/parsing.cj`).
- Note: macro-generated user optics are non-generic members whose parameters
  are pinned by the receiver — explicit call-site type arguments on them are
  rejected by the compiler. Manual registries with member-level generics (see
  `bench/examples/salary_bump.cj`) pass them explicitly and remain supported.

## 2026-09-10 — operator-enforced kind-exact optics (v2, breaking)

User-declared optics (`@LucidaOptic`) and stdlib optics are now kind-exact with
the `.`/`?.` operator deciding semantics at every call site:

- `.` = total read/write (plain result). `?.` = partial (forward returns
  `Either<S, A>` carrying the original source on miss).
- `.` on a partial optic, `?.` on a total optic, and `.`-writes through a prism
  fail to compile with bespoke messages (strict-`@Deprecated` diagnostic
  overloads). Marks are checked per segment against the kind registry —
  mid-chain or tail, derived, user, or stdlib optics alike.
- Coerce segments (`x.coerce<T>()`) are fixed-total; `x?.coerce<T>()` is
  rejected at macro time.
- Uniform affine members are gone: `.` on a partial optic no longer returns
  `Either`; use `?.`.
- Migration is mechanical: change `.` to `?.` at partial call sites
  (`nums.at(1)` → `nums?.at(1)`, `xs.selectFirst(...)` → `xs?.selectFirst(...)`).

## 2026-09-09 — user-declared optics

- `@LucidaOptic[source: S, focus: A, kind: Lens|Iso|Prism|Affine, forward: {...},
  backward: {...}] struct <name>` declares a first-class optic.
- Generated members are kind-exact and register with the matching kind registry
  so `[unfuse]` composition stays kind-correct.
- `@Lucida[unfuse]` call-site mark keeps chains off the fusion walk (mark is
  operator-agnostic).
- Generic sources/focuses: declare the parameters on the carrier struct
  (`@LucidaOptic[source: Box<T>, focus: T, ...] struct boxLens<T> {}`); call
  sites infer them from the receiver. Multi-parameter carriers are supported.
  `where` constraints are rejected at macro time.

## 2026-08-27 — prism fusion in the `@Lucida` walk

- Fused walks support prism/affine segments via `pinPrismForward1..8`
  (curried Either-forward pipelines); a chain is capped at 8 either-producing
  segments.
