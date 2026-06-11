# Changelog

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
