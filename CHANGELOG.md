# Changelog

The dated entries retain the dates recorded by the project. Examples in an
entry may describe an older API; use the [current reference](docs/README.md)
for new code. This file records changes, not published release tags.

## Changes present in the current checkout

These changes are present in the code but did not have separate dated entries
in the earlier changelog:

- The repository is a workspace with `core`, `stdlib`, and `tests` members.
  Consumers depend on `core` and optionally `stdlib`.
- Value chains support an interior first-class lens followed by more segments.
  Partial-chain inference and diagnostic reporting received fixes.
- Blocks support final partial anchors, disjoint field paths, and nested
  blocks. Nested grouping allows one traversal of the grouped prefix.
- The `@InlineOptics` direct-expansion harness and generated shape corpus
  reside in the test project. The verification gate compares 30 read/write
  expansions with their expected expressions.
- Documentation has been rewritten for Cangjie programmers learning optics,
  with consumer setup, corrected API boundaries, and explicit limitations.

## 2026-10-02: Standalone custom optics

**Breaking:** `@Optics({ ... })` has been removed. Declare each optic on its
own carrier with `@Optic`, `@Lens`, `@Prism`, `@Affine`, or `@Iso`.

Generated interface names now encode the kind, source type, focus type, and
arguments. This permits same-named optics over different source types in one
package. The encoding retains alphanumeric bytes and escapes underscores
and other bytes, with whitespace normalization.

Dispatch member names still use the optic name. Declarations with the same
name and source can therefore collide even when their signatures differ.
A duplicate declaration appears as a compiler redeclaration error. The empty
carrier is consumed and is no longer emitted as a type.

Kind aliases expand through the common implementation, report their own macro
name in diagnostics, and reject an explicit `kind:` attribute. Cross-declaration
checks formerly performed by the grouping macro are no longer available:
different arguments on different sources can coexist, and some same-source
kind clashes now appear as compiler member errors.

## 2026-09-29: Blocks and declaration bodies

Sibling blocks gained updates and reads. An update supplies a target for each
entry; a read returns the corresponding tuple, or a bare value for one entry.
Tuple element optics work inside these blocks.

The block syntax subsequently changed to semicolon-separated paths, allowing
entries such as `.address.city`. Migrate old space-separated blocks to
`.{ .first; .second }`. Later work, summarized above, relaxed the original
restriction to distinct starting fields and added nested blocks.

`@Optics` grouping and kind aliases were introduced on this date. The grouping
macro was later removed; the kind aliases remain.

Custom forward and backward bodies gained positional parameter names, such
as `forward: { value => value.field }`. `_` can omit an unused slot.

**Breaking:** the fixed source slot in custom bodies changed from `src` to
`source`. Update references to that slot. The reserved argument names are
`source`, `_source`, and `focus`.

## 2026-09-25: Names, partial results, and derivation

**Breaking:** macro names changed:

| Previous form | Current form |
|---|---|
| `@Lucida(...)` | `@f(...)` |
| `@LucidaOptic[...]` | `@Optic[...]` |
| `@Optic(value)` | `@use(value)` |
| `@Type(T)` | `@ty(T)` |
| `@TypeOf(value)` | `@typeof(value)` |

When migrating mechanically, distinguish the old `@Optic(value)` use from
the new declaration macro. Rename the old use form before introducing the
new declaration spelling. `@DeriveOptics` retained its name.

**Breaking:** partial reads changed from `Either<Source, Focus>` to
`Option<Focus>`. Replace `Right(value)` with `Some(value)` and a miss's
`Left(source)` with `None`; retain the original source separately when needed.
`Either` was removed from the library.

Tuple field optics were extended to arities 2 through 16. The generator now
builds reusable token blocks and joins them without repeatedly splicing an
accumulating buffer. Historical timings are preserved in
[compiler observations](docs/compiler-issues.md).

Enum derivation gained payloadless and multiple-payload cases. Their focuses
are `Unit` and tuples respectively. Generated case optics remain affines and
preserve other cases on an update miss.

## 2026-09-10: Type arguments and operator checks

Reconstruction of method calls with multiple type arguments was corrected to
use commas. Generated custom optics still infer carrier parameters through
the source; explicit method type arguments apply only to members that actually
declare method-level generics.

**Breaking at the time:** custom optics began using kind-specific function
shapes. Operators were checked against their kinds, replacing the earlier
uniform affine representation. Partial segments use `?.`; conversions remain
total. Partial results still used `Either` at this point and changed later.

## 2026-09-09: Custom declarations

`@LucidaOptic`, now `@Optic`, introduced named custom operations with a source,
focus, kind, and forward/backward bodies. Generic parameters were declared
on the carrier. `where` constraints were rejected.

The `[unfuse]` modifier exposed the composition path for comparison with
fused value chains.

## 2026-08-27: Partial forward fusion

The earlier `@Lucida` emitter gained helpers for fused prism/affine reads.
The recorded initial family supported eight partial steps and used the older
`Either` result. The current family supports 16 partial steps and uses
`Option`; longer supported partial reads fall back to composition.
