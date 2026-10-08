# Fusion

The fused emitter generates the operations for an applied path directly.
It uses the same registered reads and backwards as composition, but avoids
building a composed function pair at every intermediate step.

The entry points are `emitFusedForwardWalk` and `emitFusedBackwardWalk` in
[`eval_macro.cj`](../../core/src/macrodsl/eval_macro.cj).

## Total paths

For a two-lens update, the essential work is the following pseudocode:

```text
part = outer.view(source)
changedPart = inner.update(part, replacement)
result = outer.update(source, changedPart)
```

A longer path stores the intermediate sources required by each backward.
It applies the backwards from the focus towards the original source.
A source-free backward, such as an iso conversion, uses only the newly
rebuilt focus.

Leaf binding is demand-driven. Forward walks bind the forwards they use;
backward walks bind the functions needed for probing and reconstruction.
The last slot does not need to produce a witness for another slot.

This is still an expansion through registered functions. It is not
necessarily the same code as directly spelling every constructor and field
access. That distinction is measured by the
[direct-expansion harness](inline-harness.md).

## Type inference helpers

The macro cannot generally write the inferred source and focus types into
every lambda parameter. Helpers such as `pinForward` and `pinBackward`
provide typed contexts by accepting source and target witnesses.

The witness function's type supplies information; the helper does not call
it to obtain a source. The generated operation is subsequently applied to
the actual source value.

`pinBackwardSourceless` provides the analogous context for a backwards
function that needs only the replacement.

## Partial reads

A partial read must stop when a slot returns `None`. The emitter groups
total runs around the partial slots and passes them to a typed helper
that performs the required sequence of matches.

`@GeneratePrismForward` generates `pinPrismForward1` through
`pinPrismForward16` in the current core. The name covers both prism and
affine partial steps. A supported forward walk with more than 16 partial
slots falls back to ordinary composition.

The limit concerns the partial forward helper family. It is not a general
16-slot limit on all paths or a claim about the backward implementation.

## Partial updates

For a partial step, the backward emitter probes for a match before continuing
towards the focus. A successful walk reconstructs outward. A miss preserves
the original source instead of constructing an unrelated prism case.

Total and partial operator checks are applied through the resolved kind
registries. Custom backwards may have one argument or two; the `__bwdApply`
family handles that difference. Total-marked custom writes also use a check
that rejects an unconditional prism reconstruction.

The emitted guards do not make arbitrary supplied functions pure. An optic
body or constructor can still mutate shared objects or perform effects.

## First-class slots

The emitter can split a value path at an interior `@use` slot, apply that
optic's functions, and continue from its focus. The regression suite covers
an interior lens and its following derived fields.

This is not a reason to assume every combination of partial first-class
values and nested blocks is handled by the same path. The actual split code
has its own function-shape assumptions; changes need tests for the relevant
kind and position. A chain beginning with `@use` constructs an optic through
the composition route.

## Blocks

A block has an owner value and an ordered list of entries. Each entry's
backward updates the accumulating owner. The anchor's backwards then rebuild
the original source around that owner.

A nested block binds its prefix focus once, applies the inner entries there,
and rebuilds the prefix around their combined result. Flat entries sharing
part of a path are still separate entries; automatic sharing of every common
prefix is not implied.

A partial final anchor runs the block inside the successful branch and
preserves the source on a miss. Block reads at such an anchor return an
`Option` containing their tuple. General partial anchors and partial nested
prefixes have a narrower supported set than ordinary chains.

The block emitter is selected directly by `SiblingForward` and
`SiblingBackward`. The `[unfuse]` switch does not provide an independent
composed implementation of blocks.

## Verify an emitter change

Use the law and feature tests to compare successful reads, replacements,
and misses. Check preservation of other fields and expression evaluation
where effects are deliberately tested. Include ordinary and `[unfuse]`
paths when both are available.

The generated corpus compares selected values with a direct reconstruction
and separately checks its token expansion. It covers a useful set of shapes,
not every possible custom optic or grammar form.

Timing comes after those checks. [Benchmarks](../benchmarks.md) describe the
recorded settings and distinguish performance measurements from equivalence.
