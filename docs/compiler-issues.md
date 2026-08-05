# Compiler notes

Measured issues to revisit upstream. Toolchain: cjc 1.2.0-alpha.20260710020028
and 1.3.0-alpha.20260925001050 (cjnative), Linux x86_64. Discovery tool:
`cjc --profile-compile-time` (see issue 3).

## 1. Compile-time cost of high-arity generics (open)

With macro evaluation eliminated as a factor (issue 2 fixed on our side), a
clean `cjpm build` of this module still grows steeply with the arity of the
generated tuple extends (each arity contributes an `extend` with up to `k`
type parameters and `k+1` members; ~8k declarations at arity 64):

| tuple arity | 8 | 16 | 20 | 32 | 64 |
|---|---|---|---|---|---|
| clean build | 10 s | 11 s | 13 s | 34 s | 284 s |

At arity 64, `--profile-compile-time` attributes only 22 s to macro
evaluation — the remaining ~4.4 min is cjc itself. Phase totals
(Semantic/TypeCheck, CHIR, CodeGen) each grow a few hundred ms and do not
explain the wall, so the cost is spread across per-declaration handling that
the phase profile does not break out. Candidates worth profiling upstream:
generic substitution on declarations with many type parameters, `.cjo`
interface emission, LTO bitcode lowering per function.

Next step: finer pass timing inside cjc (or a profiling build of the
compiler) to name the pass.

## 2. Token splice cost in macro `quote()` interpolation (macro system)

The first tuple generator accumulated its output through nested `quote()`
splices (a CPS chain whose continuations re-spliced the grown buffer at every
arity). Evaluation cost of `@GenerateTupleExtendsLenses` measured:

| tuple arity | 8 | 16 | 20 | 24 |
|---|---|---|---|---|
| macro evaluation | 88 ms | 6 374 ms | 117 075 ms | >36 min |

— superlinear long before the compiler-side costs of issue 1 matter, and
LTO-independent. Rewriting the same output shape as *memoized blocks joined
in one flat pass* (`Tokens.append`, no re-splice of accumulated buffers)
collapses it: arity 16 macro evaluation is 109 ms, arity 20 was 342 ms with
an equivalent flat formulation.

Suspected mechanism: interpolating a `Tokens` value into `quote()` re-parses
the spliced content, making each nested splice pay for everything spliced
before it. Needs upstream confirmation; if true, it is a trap for any macro
that assembles large outputs incrementally.

## 3. `--profile-compile-time` is undocumented

`cjc --profile-compile-time` writes `<package>.time.prof` (JSON, milliseconds
per compilation phase, nested per pass) into the output directory. It is
absent from both `cjc` documentation and cjpm's developer guide, and it is
the tool that separated macro-evaluation cost from compiler cost in this
repository. Worth documenting in both.

## 4. `--lto-staticlib-format` is iOS-only

Passing `--lto-staticlib-format=bitcode` on a Linux static-library build is
rejected ("only supported on iOS platforms"), so the bitcode-vs-native
format of an LTO static lib cannot be chosen on Linux. Plain `--lto=thin`
embeds working bitcode in static libs (cross-package LTO with our consumer
was verified by benchmark), so this is a capability gap, not a blocker.

## 5. Tuple element access parses neither `.0` nor `t[0]`-style chains (FYI)

Tuples index as `t[i]` in source, but a member-access AST node for `.0`
does not exist and the `@Lucida` macro receives index expressions as opaque
`Unknown expression`. Not a defect — the DSL's `._i` spelling sidesteps it —
but any DSL authoring tuples should know the grammar constraints up front.

## 6. Expected-type propagation for bare enum constructors is lost through macro emission in nested lambdas

Minimal context: a macro emits, into a generic member, a lambda nested inside
another lambda whose branches end in a bare no-payload enum constructor:

```cangjie
// emitted by @GenerateCompositions (generate_compositions.cj) into
// __OpticsCompositions.composeForward:
static public func composeForward<S, A, B>(...): ((S) -> A, (A) -> Option<B>, ...) -> (S) -> Option<B> {
    { f1b, f2b, b2 =>
        { x: S =>
            match (f2b(f1b(x))) {
                case Some(v) => Some<B>(v)
                case None => None        // <- error: generic type should be
            }                            //    used with type argument
        }
    }
}
```

Measured matrix (same compiler, same shape):

| context | bare `None` infers? |
|---|---|
| hand-written: match arm, if/else branch, `return`, single or nested lambda, direct body | yes (all 12 probe shapes) |
| macro-emitted: single-level lambda, `match` arm | yes (`pinPrismForwardK` bodies) |
| macro-emitted: nested lambda — `match` arm, if/else expression, `return` statement | **no** — `generic type should be used with type argument` |
| macro-emitted: type-applied (`Some<B>(v)`) or qualified (`Option<B>.None`) | yes |

Notes:

- Hand-written and macro-emitted tokens are otherwise identical — the failure
  is specific to code arriving through quote expansion.
- The boundary looks like expected-type propagation stopping one lambda deep
  when the code comes from a macro; single-level lambda bodies still receive
  the member's return type.
- Also fails for `return None` (the return statement does not pick up the
  enclosing lambda's result type through emission), which rules out
  statement-form workarounds.
- Workaround shipped in this repo: qualify the constructor
  (`Option<B>.None`) or type-apply payload constructors (`Some<B>(v)`) in
  every macro-emitted branch expression. The pyramid walkers keep bare
  constructors (single-level lambda).

First observed on cjc 1.2.0-alpha.20260710020028, still reproduces on
1.3.0-alpha.20260925001050.
