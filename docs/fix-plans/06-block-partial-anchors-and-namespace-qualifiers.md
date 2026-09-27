# 06 — blocks: partial anchors; namespaces: qualifiers

## A. Partial anchors for sibling blocks (RESOLVED)

The anchor's last segment being partial (affine/prism) makes the owner
exist only on a forward hit. Writes wrap the sibling steps and the anchor
fold in a Some-guard over the last probe (`miss = source`); reads use
`__anchorOpt.map({ owner => ... })` — map supplies the Option, avoiding a
None literal whose type argument is unknowable at macro time, and the
lambda returns the bare tuple (tuples are not Equatable, so consumers
compare unwrapped). The last probe's binding moves inside the guard; the
registry bindings stay top-level (type-level only).
Blocks require a fusible, total anchor (parseBlockAnchor + the
isFusible/isFusableChain guards in evalOptics' SiblingBackward/
SiblingForward cases). A partial anchor (`?.at(0)`) needs the block fold
composed with the pinned-prism machinery: the anchor's forward produces
Option — the owner exists only on a hit. Direction: wrap the whole block
emission in the Some-guard (the pattern emitFusedBackwardBody already
uses for trailing partials) — owner = the unwrapped probe, miss = source.
Do this only after 05: the guard composes with the same upcast lambdas.

## B. Namespace qualifiers
Two @Optics blocks reusing an optic name in one package collide on the
unified interface names (`__<name>_impl`). Direction: accept an optional
block attribute `@Optics[ns] { ... }` and mangle the interface names to
`__<ns>_<name>_impl` while keeping member names
(`__method_<name>_impl_forward` — the chain emitter depends on them)
unchanged. The emitOpticsNamespace/emitOpticNameGroup pair in
user_optic_macro.cj takes the qualifier as a parameter; the duplicate/
mixed-kind/mixed-args checks become per-namespace.

## Verification
A: `@f(j.caches?.at(0).{ .dir; .size } <- (...))` compiles and passes.
B: two namespaces reusing a name compile; a chain still dispatches by
source type. scripts/check.sh green after each.

## C. Disjoint sub-paths from one start field (RESOLVED)

`x.{ .pair._0; .pair._1; .n } <- (1, 2, 3)` is rejected by the
distinct-start rule, even though the two chains write DIFFERENT tuple
elements: the threading makes each backward see the previous chain's
rebuilt value, so purely-Derived prefixes that diverge compose
correctly. Relax the check: two entries may share a start field when
every segment up to the point where their paths diverge is a plain
Derived field (pure field paths). Keep the rejection when a user optic
sits at or before the divergence — its backward may read other fields
(e.g. the raise lens folds pay.cents), so disjointness is not provable
at macro time.

### Status
RESOLVED. blockChainsConflict(parsing.cj) walks two accepted chains in
lockstep: a divergence at plain Derived fields is disjoint (allowed);
a non-Derived segment while both chains are alive, or one chain being a
prefix of the other, conflicts. The check runs after the entry's node
list is built, against the chains accepted so far. Verified by the
in-block spread (`.{ .tb._0; .tb._1; .n } <- (10, 11, 12)`) and the
conflict probe (renamed to "block chains conflicting overlap").

## D. Nested blocks (RESOLVED)

The target semantics: `@f(box.{ .tb.{ ._0; ._1 }; .n } <- ((1, 2), 3))` —
the entry `.tb.{ ... }` shares the prefix `tb` (traversed ONCE — a print
effect in the target must appear once), the inner block operates on the
prefix's focus, and the prefix's backward folds over the inner block's
combined result. With this sharing, ANY optic is allowed in a shared
prefix: its backward applies once to the combined inner result, so the
composition is lawful by construction for sourceful backwards (quirks
from source-discarding backwards are accepted, not diagnosed).

The attempt established, before the edits tangled:
1. **The scanner must be depth-aware**: its loop exited at the FIRST
   RCURL, truncating a nested entry at the inner `}`. Exit only at the
   block's own closing brace (depth 0); same for the blockEnd helper.
2. **The parse tree**: `BlockEntry(prefix, inner: ?BlockSpec, target: ?Expr)`
   + `BlockSpec(entries)`; `appendBlockEntry` splits the entry at
   DOT+LCURL, parses the prefix, and recurses for the inner spec.
3. **The emission** (both walks): the threaded entry for a nested one
   binds the prefix's leaf bindings + probes inside the enclosing shell,
   the focus = the last probe, the inner block emitted against
   `[TypeOf(focus)]` with child targets from a runtime destructure
   (`let (__s0, __s1) = <target element>` — the parent's target element is
   bound once, satisfying the print-once requirement), and the prefix fold
   via buildBackwardWalk over the inner result.
4. **cjc parse behavior**: cjc's file parser accepts `expr.{ .a; .b }`
   (the flat blocks prove it) but the debug prints were inconclusive about
   the nested form — the echoes from a failing expansion mask it. Build
   the macro package in isolation when iterating (`cjpm build` fails on
   the tests member first; use the @APPEND/@SCAN println pattern).

The reverted attempt is recoverable from this session's history; the next
pass should start from a clean checkout, apply 1-3 as separate commits,
and gate after each.

### Status
RESOLVED. `@f(box.{ .tb.{ ._0; ._1 }; .n } <- ((1, 2), 3))` works for
reads and writes, with the shared prefix traversed exactly once (the
parent's target element is bound once and runtime-destructured across
the inner entries, so target effects appear exactly once — verified by
blockTargetEffectsRunOnce with an effect counter). Any optic is allowed
in a shared prefix: its backward applies once to the inner block's
combined result. The duplicate-accident check rejects only IDENTICAL
leaf paths (collectLeafPaths + blockChainsConflict), checked against all
accepted leaves in both the flat and nested append branches. The scanner
and blockEnd are depth-aware (a nested entry's inner `}` no longer
terminates the scan). Reads nest: `@f(box.{ .tb.{ ._0; ._1 }; .n })`
returns ((tb._0, tb._1), n). Nested shared prefixes must be total
(no `?.` — bespoke diagnostic); partial anchors at the BLOCK level remain
supported (06A).

### E. Flat leaf + nested entry sharing a prefix (RESOLVED)

`@f(o.{ .i.a; .i.{ .b } } <- (7, 8))` composes: the leaf and the nested
entry thread through the shared prefix, each target applied once. The
earlier failure was a resolver bug (the nested recursion consumed the
outer tuple, mis-assigning the inner targets), not a cjc inference
limitation — the "lambda type annotations" errors were the cascade from
the mis-typed emission. The resolver now recurses only through literal
sub-tuples, passes opaque sub-tuple expressions whole (the emitter's
runtime destructure validates their arity), and the flat conflict rule
diverges at plain fields.
