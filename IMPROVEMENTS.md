# Improvement suggestions

Distilled from the showcase-consumer session (building a deeply nested
update against this library from outside). Ordered by friction caused.

## Publishing / toolchain

1. **`lucida.tests` compiles for every consumer.** cjpm auto-discovers
   `src/tests` as a sub-package, so a dependent build compiles the whole
   test suite as a staticlib. Under some flag combinations this fails with
   `N errors generated, 0 error printed` — no positions, no text. Move the
   suite out of the published package (or find the cjpm exclusion) and
   chase the silent-error path with cjc.
2. **Swallowed macro diagnostics.** `diagReport` output is lost when the
   failing macro echoes its input or when the error surfaces from a
   dependency compile. Every debugging session this session started with
   re-adding `println` to the macro catches. Root-cause the printer path
   (positions with empty token spans print nothing) and consider a
   debug-only verbose mode.

## Composition machinery

3. **Forward-only reads through `composeOptics` cannot infer
   `composeBackward`'s generics** when a first-class optic's halves come
   from `__FirstClassGetters` (dynamic getters). The write instantiation
   infers, the read one does not. Fix: skip backward wiring when
   `needB=false`, or pin the getters as typed segment bindings (the fused
   tail-Optic treatment in 030e423).
4. **Mid-chain first-class optics are tail-only in fused walks.** A
   following segment would need a magical built from a runtime value
   (`magic({ => __tI })` inside the fold). Lifting the restriction makes
   `a.b.@use(lens).c` fuse like any other chain.
5. **Chains with 3+ affine segments trip the cjc curried-lambda issue**
   (`parameters of this lambda expression must have type annotations`) in
   the fused walk's expect-upcast lambdas. Same family as the
   `emitLensRunLambda` identity-lambda workaround in
   docs/compiler-issues.md — annotate or self-reference there too.

## Blocks

6. **Partial anchors.** Sibling blocks require a fusible, total anchor;
   `p.stages?.at(0).members.{ ... }` is rejected. Composing the block with
   the pinned-prism machinery would allow blocks after any partial chain,
   which is the natural use case (update several fields of a found
   element).
7. **Namespace collisions across blocks.** Two `@Optics` blocks reusing an
   optic name in one package still collide on the unified interface names.
   A namespace qualifier (or content-addressed interface names) would lift
   this.

## Consumers

8. **Stale macro-dylib traps.** Changing macro-package code while a
   consumer's target holds an older dylib produces phantom failures
   (missing declarations, silently swallowed errors). Document
   "clean both targets after touching the macros" — or make cjpm
   key the cache on the dylib hash.
