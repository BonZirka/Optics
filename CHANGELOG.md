# Changelog

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
