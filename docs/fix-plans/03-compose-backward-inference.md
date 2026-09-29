# 03 — composeBackward inference failure on forward-only reads (RESOLVED)

## Symptom
`unable to infer generic argument of this function` at
`__OpticsCompositions.composeBackward(optics0, optics1)(...)` when the
terminal consumes only the forward (needF=true, needB=false) and one
segment's halves come from `__FirstClassGetters` (dynamic getters).
The write instantiation infers; the read does not.

## Fix
In eval_macro.cj, composeOptics' segment wiring emits BOTH halves for
every non-tail segment (unwrapStart/unwrapMid, the `needF/needB` flags
only trim the tail). When `needB=false`, skip the backward half entirely:
1. Thread needB into wireSegment/unwrapMid so a non-tail segment binds
   only the forward composition (composeForward) — no composeBackward
   call is emitted at all.
2. The already-landed fused tail-Optic path (commit 030e423, the Optic
   case in emitLeafBindingsAndIds + the ungated __gfwd in
   emitFwdGateBindings) bypasses this for tails; this plan covers the
   composeOptics fallback and regular chains.

## Verification
In tests/src/user_optic_name_reuse.cj, re-add firstClassMidChain (the exact
test body is in git history, commit 579a90a): a block read
`@f(o.{ .i.@use(lens); .n })` must compile and pass. Then the full gate
(scripts/check.sh) — 210+ tests, 22 probes, zero warnings.

## Status
RESOLVED — by fix-plan 04 rather than by the needB refactor. Every chain
containing an Optic now takes the fused split (04), so the failing
composeOptics instantiation is unreachable from reads: the original
block-read fallback, regular mid-chain reads/writes, and unfused
chains all verified. The unfused path itself (composeOptics with
getter halves) compiles and infers for (Optic, Derived) pairs —
probed by unfusedAndMintedOpticChains: unfused read/write through a
spliced optic, plus the sourceless mint semantics (a sourceless chain
mints a composed optic value; a sourceless write mints a Setter).
The needB-wiring refactor was unnecessary and was not done.
