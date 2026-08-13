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
does not exist and the `@f` macro receives index expressions as opaque
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

## 7. `case _` after an exhaustive multi-case match is flagged unreachable — but removing it is a hard error

A hand-written match over a multi-case enum whose scrutinee is a *direct
enum-constructor value* reports every non-constructor arm as
`unreachable pattern`, while deleting those same arms fails with
`non-exhaustive patterns`:

```cangjie
let f = Status.Failed("boom", 7)   // Status = Pending | Active(Int64) | Failed(String, Int64)
match (f) {
    case Pending => ()             // warning: unreachable pattern
    case Active(_) => ()           // warning: unreachable pattern
    case Failed(msg, code) => work // ...but removing these two arms
}                                  //      errors: non-exhaustive patterns
```

- The identical match over a macro-produced value of the same static type
  (`let fixed = @f(...)`) raises no warning — the flag tracks how the
  scrutinee value was created, not its type.
- Explicit type annotation (`let f: Status = ...`), arm reordering, and
  wildcard vs named arms all behave identically; the two analyses
  (reachability and exhaustiveness) simply disagree.
- Workaround shipped in this repo: extract the needed case with an affine
  read (`if (let Some(pair) <- @f(f?.Failed))`) instead of matching.

First observed on cjc 1.3.0-alpha.20260925001050.

## 8. Identity lambdas in generic curried positions report `unused variable` on the used parameter

`{ p => p }` passed as a function argument whose parameter/return types are
still generic reports `unused variable: 'p'` even though the body returns
the parameter. The same lambda in a concrete-typed `let` raises nothing, so
the use-analysis misses the return-position use while the parameter's type
is unresolved.

- Affects macro-emitted identity run lambdas passed to the generated
  generic pyramid walkers.
- Bare generic function references (`__identityRun` unapplied) do not help:
  they fail with `generic type should be used with type argument`.
- Workaround shipped in this repo: emit identity runs as
  `{ p => let _ = p; p }` (see `emitLensRunLambda`).

First observed on cjc 1.3.0-alpha.20260925001050.

## 9. `-Wparser` fires on phantom line breaks from nested-macro token remapping

The `possibly confusing line terminator` heuristic (meant for U+2028/2029-
class characters) fires on pure-ASCII sources in two shapes:

1. An assert nesting a macro call — `@Assert(@f(x.y) == v)` — expands to
   `assertEqual` whose expression argument contains the `@f` expansion
   spliced inline; the expansion's tokens carry remapped positions, and the
   heuristic reports a terminator "between `)` and `==`" although the real
   line break is nowhere near (the string argument embeds the same expansion
   with literal `\n` escapes on one line). Write-form asserts
   (`@f(x <- v).y == z`) do not trip it — only specific token pairs like
   `) ==` do.
2. A `&&`/`||` chain wrapped with the operator leading the next line
   (`... name\n        && ...`); ending lines with the operator is
   accepted.

Workarounds shipped in this repo: bind the macro result and assert on the
local (`let got = @f(x.y)`) instead of nesting, end wrapped boolean lines
with the operator, or `-Woff parser` for code that must keep the nested
shape.
