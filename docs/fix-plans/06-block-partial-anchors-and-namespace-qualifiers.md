# 06 — blocks: partial anchors; namespaces: qualifiers

## A. Partial anchors for sibling blocks
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
