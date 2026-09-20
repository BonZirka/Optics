# 04 — lift the tail-only restriction on first-class optics

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
