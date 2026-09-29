# Improvement suggestions

Distilled from the showcase-consumer session (building a deeply nested
update against this library from outside). Ordered by friction caused.

## Publishing / toolchain

1. RESOLVED (992f006): the repo is a cjpm workspace — members `core`
   (lucida), `lucida_stdlib`, `tests`. Consumers depend on `core` and opt
   into `lucida_stdlib`; the suite is never compiled for them. Member
   names must be bare identifiers (cjpm rejects dots).
2. RESOLVED (reportCaughtDiag + LUCIDA_VERBOSE_DIAGS=1, see
   docs/fix-plans/02). Was: `diagReport` output is lost when the
   failing macro echoes its input or when the error surfaces from a
   dependency compile. Every debugging session this session started with
   re-adding `println` to the macro catches. Root-cause the printer path
   (positions with empty token spans print nothing) and consider a
   debug-only verbose mode.

## Composition machinery

3. RESOLVED (superseded by the 04 chain split, see docs/fix-plans/03).
   Was: forward-only reads through `composeOptics` cannot infer
   `composeBackward`'s generics** when a first-class optic's halves come
   from `__FirstClassGetters` (dynamic getters). The write instantiation
   infers, the read one does not. Fix: skip backward wiring when
   `needB=false`, or pin the getters as typed segment bindings (the fused
   tail-Optic treatment in 030e423).
4. RESOLVED (chain split at the Optic, see docs/fix-plans/04). Was:
   mid-chain first-class optics are tail-only in fused walks. A
   following segment would need a magical built from a runtime value
   (`magic({ => __tI })` inside the fold). Lifting the restriction makes
   `a.b.@use(lens).c` fuse like any other chain.
5. RESOLVED (emitLensRunLambda self-reference, see docs/fix-plans/05).
   Was: chains with 3+ affine segments trip the cjc curried-lambda issue
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
7. RESOLVED (content-addressed interface names; the `@Optics` block is gone).
   Was: two `@Optics` blocks reusing an optic name in one package collided on
   the unified interface names. Each declaration now mangles its three
   generated interfaces from its own signature (kind, source, focus, args),
   keeping alphanumeric bytes verbatim and escaping `_` as `_u` and every other
   byte as `_xHH` — so `(T) -> Bool` becomes
   `_x28T_x29_x20_x2d_x3e_x20Bool` and can never collide across declarations.
   Member names (`__method_<name>_impl_forward`) stay keyed to the optic name,
   since a chain resolves them by name alone; two same-named optics must
   therefore still differ in source type, or their dispatch members on
   `RegistryMagical<Source>` collide. The empty carrier struct is no longer
   re-emitted either — it carried no members and nothing referenced it as a
   type, so it was a second collision point once interfaces were separated.

   Consequence: same name, different `args:` now compiles. `@Optics` used to
   reject it ("optics named 'x' declare different args"); with the namespace
   gone, separate macro invocations share no state, so nothing compares a
   declaration against one expanded earlier. Sound over different sources — the
   members sit on different registries — but a mismatched `args:` goes
   unwarned. A package-level opt-in registry of `(name, source) -> args` would
   restore the check if it is ever worth the macro-state machinery. The
   same-`source:`/different-`kind:` case still fails, but on a cjc return-type
   clash on `__downcast_method_<name>` instead of a bespoke message. Both
   degraded cases are pinned by probes in `scripts/check_diagnostics.sh`.

## Consumers

8. **Stale macro-dylib traps.** Changing macro-package code while a
   consumer's target holds an older dylib produces phantom failures
   (missing declarations, silently swallowed errors). Document
   "clean both targets after touching the macros" — or make cjpm
   key the cache on the dylib hash.
