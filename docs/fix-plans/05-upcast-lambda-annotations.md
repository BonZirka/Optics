# 05 — 3+ affine chains trip the curried-lambda annotation issue (RESOLVED)

## Symptom
Chains with 3+ affine segments fail with
`parameters of this lambda expression must have type annotations` at the
fused walk's expect-upcast lambdas (`{ __e3 => ... }`, odd indices).

## Root cause
Same cjc family as the documented identity-lambda issue
(docs/compiler-issues.md): a lambda in a generic curried position cannot
infer its parameter. emitLensRunLambda already works around it with the
`let _ = p; p` body trick.

## Fix
Find the upcast-lambda emission (the `__e${i}` identifiers — grep
`__e${` in eval_macro.cj, emitted by the unwrap* upcast wiring) and
apply the same body trick, or hoist the lambda to a named binding with
an explicit type when the registry type is statically known at that
point.

## Verification
A 3-affine chain (`a?.at(1).b?.at(0).c?.at(2).d <- v`) compiles and
passes; add it to src/tests + one check_diagnostics.sh probe guarding
the old failure.

## Status
RESOLVED. The failing lambdas were the inter-"prism" runs in
emitLensRunLambda — isPartialProducing counts affines as prisms, so 3+
affines create the failing shape. The fix extends the identity-case
self-reference (`let _ = param`) to the non-identity runs: re-binding
the parameter gives cjc the inference context the curried position
lacks. Verified with a 3-affine chain probe
(`departments?.at(0).teams?.at(0).members?.at(0).name`) in the showcase
and the full gate (211 tests, 22 probes, zero warnings).
