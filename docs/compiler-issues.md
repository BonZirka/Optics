# Compiler observations

These notes preserve investigations recorded on Cangjie
1.2.0-alpha.20260710020028 and 1.3.0-alpha.20260925001050, cjnative,
Linux x86_64. Individual entries state a narrower version where known.
They have not all been reproduced on the compiler used for the current
macOS verification run.

Treat a workaround as an explanation of the source code, not as evidence
that every later compiler has the same behavior. A new report should include
a minimal reproducer, `cjc -v`, build options, and full output.

## High-arity generic compilation

The historical experiment increased generated tuple support beyond the shipped
maximum of 16. After reducing macro construction overhead, clean build times
were recorded as follows:

| Tuple arity | 8 | 16 | 20 | 32 | 64 |
|---|---|---|---|---|---|
| Clean build | 10 s | 11 s | 13 s | 34 s | 284 s |

At arity 64, the compilation produced roughly 8,000 declarations, and the
profile attributed about 22 seconds to macro evaluation. The remaining time
was not explained adequately by the available phase totals.

## Repeated token splicing

An earlier tuple generator repeatedly interpolated a growing token buffer
through nested `quote()` calls. Its recorded macro times were:

| Tuple arity | 8 | 16 | 20 | 24 |
|---|---|---|---|---|
| Macro evaluation | 88 ms | 6,374 ms | 117,075 ms | More than 36 min |

Building reusable blocks and joining them in a flat pass reduced the recorded
arity-16 macro time to 109 ms. An equivalent arity-20 construction took
342 ms. The current tuple generator uses that approach.

Repeated parsing or copying during interpolation is a possible explanation
for the earlier growth, but the compiler mechanism was not confirmed.
The demonstrated result is the reduction from changing token construction.

## Compile-time profiling

In the investigated SDKs, `cjc --profile-compile-time` wrote a
`<package>.time.prof` JSON file containing phase timings in milliseconds.
That output helped separate macro evaluation from later compiler work.

Availability and file shape should be checked on the SDK being investigated;
this note is not a statement about current external documentation.

## Static-library LTO format

The investigated Linux compiler rejected
`--lto-staticlib-format=bitcode` with a message saying that option was
supported only on iOS. Ordinary `--lto=thin` remained usable for the Linux
experiment.

The distinction concerns the explicit archive-format option, not a blanket
lack of Linux LTO support. The separate macOS measurements recorded platform
warnings for configured LTO; see [benchmarks](benchmarks.md).

## Tuple path syntax

The DSL parser accepts derived-style tuple elements such as `._0`. The
investigated AST representation did not provide `.0` as a normal member
access, and indexing expressions were not supported path nodes.

This explains the library's tuple slot spelling. Ordinary Cangjie tuple
indexing outside `@f` is a separate language operation.

## Optional constructors in nested generated lambdas

The record reports a type-inference difference between handwritten and
macro-emitted nested lambdas. A bare `None` in a generated generic match
could fail with `generic type should be used with type argument`.

| Context | Recorded behavior for bare `None` |
|---|---|
| Handwritten single or nested lambdas | Accepted in the tested cases |
| Generated single-level lambda | Accepted in the tested helper |
| Generated nested lambda | Failed in tested match, branch, and return forms |
| Generated qualified `Option<B>.None` | Accepted |

The workaround is to provide the type explicitly, using `Option<B>.None`
and, where needed, `Some<B>(value)`. The composition generator uses explicit
forms where its nested generated lambdas require them.

The behavior was recorded on both alpha versions named above. The observations
suggest a difference in expected-type propagation; they do not establish the
compiler's internal cause.

## Reachability and exhaustiveness warnings

On the recorded 1.3 alpha, a match over a value initialized directly with an
enum constructor could report other arms as unreachable. Removing those
arms could then fail exhaustiveness checking.

Explicit source annotations, reordered arms, and wildcard arms did not
resolve the tested case. A value obtained through a macro expansion did not
produce the same warning in that investigation.

Preserve the required match cases. In code that only needs one payload, a
partial optic read can also avoid writing the match explicitly. A warning
alone is not evidence that the required fallback branch should be deleted.

## Identity lambdas in generic contexts

An identity lambda `{ p => p }` supplied in a generic curried context was
reported as having an unused parameter on the recorded 1.3 alpha. In related
inference cases the emitter needed an explicit use of the parameter.

`emitLensRunLambda` emits the identity body in this form:

```cangjie
{ p => let _ = p; p }
```

The explicit use is an implementation workaround. Before removing it, check
the partial-chain regressions on the compilers the project supports.

## Parser warnings after nested macro expansion

The recorded compiler could emit `possibly confusing line terminator` for
ASCII source that nested a macro read inside an assertion. Token positions
after expansion appeared to contribute to the diagnostic. Leading operators
on continued boolean expressions also produced warnings in tested cases.

Practical workarounds are to bind a macro result before asserting on it and
to place a continued boolean operator at the end of the preceding line.
`-Woff parser` suppresses the warning class but can also suppress useful
warnings elsewhere.

## Failures without an established cause

During local verification with Cangjie 1.0.0 on macOS arm64, an optimized
compile of `tests.inline` once failed because `llc` exited with code 139.
A later build and full gate succeeded. That establishes an observed transient
failure, not its cause or a reliable reproducer.

Keep the original compilation log if this recurs. Distinguish it from macro
diagnostics and from the test runner failing to bind a socket in a sandbox.
