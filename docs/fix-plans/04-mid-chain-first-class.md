# 04 — lift the tail-only restriction on first-class optics (RESOLVED)

## Symptom
`a.b.@use(lens).c` is rejected: "a first-class optic can only end a
chain". The fused walk binds every segment's registry UP FRONT from
magical expressions; a segment after an Optic needs a magical built from
the Optic's runtime output, which does not exist at binding time.

## Fix direction
Inside the fused walk's fold the probe values DO exist. Re-anchor there:
the segment after an Optic binds its registry from
`magic({ => __tI })` where __tI is the Optic segment's forward probe.
Concretely:
1. emitLeafBindingsAndIds: allow the Optic case mid-chain, but emit NO
   magical threading past it; instead record an index break.
2. emitFusedForwardWalk/emitFusedBackwardBody: after an Optic segment,
   emit the next segment's bindings INSIDE the fold from
   `magic({ => __tI })` (the TypeOf-anchor pattern — see how
   emitBlockForwardWalk synthesizes `TypeOf(quote($ownerId))`).
3. Keep the diagnostic for genuinely impossible shapes (Optic directly
   after a partial without a consumed probe).

## Verification
`@f(o.i.@use(lens).n)` and the block form `@f(o.{ .i.@use(lens).k; .n })`
compile and pass; scripts/check.sh green.

## Status
RESOLVED. Both fused walks split the chain at the first mid-chain Optic:
the head (anchor + preceding segments) fuses as usual, the optic's
forward output is bound to a value, and the rest re-anchors on it via a
synthetic TypeOf anchor — recursively, so chains with several spliced
optics split into a nest of walks. On writes the optic's backward
rebuilds the head's owner from the rest's result before the head fold.
The rest walk is IIFE-wrapped at its splice point (its output begins
with bindings — the same initializer trap the block emitters hit).
The tail-only diagnostic in emitLeafBindingsAndIds stays as a safety
net; it is unreachable through the walks. Verified by midChainFirstClass
(read, write, and the block-entry form) and the full gate: 212 tests,
22 probes, zero warnings.
