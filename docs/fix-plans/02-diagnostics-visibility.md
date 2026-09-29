# 02 — swallowed macro diagnostics (RESOLVED)

## Symptom
`diagReport` output is lost when (a) a failing macro echoes its input and
the compiler then chokes on the echoed tokens, (b) the error surfaces from
a dependency compile, or (c) the exception is not a DiagReportException
(ParseASTException from std.ast parse helpers escapes uncaught and cjc
reports only `macro evaluation has failed`).

## Root cause established this session
- Errors whose token span is empty (throws with `quote()`) print nothing.
- `--profile-compile-time` was VERIFIED NOT to be the cause (errors print
  with it on; the silent phase was a stale macro dylib).
- Every macro catch in this package needs the same treatment.

## Fix
1. Never throw with empty tokens: audit
   `grep -n "quote()" src/macrodsl/*.cj` for DiagReportException throws
   and give each a real token span (usually the chain input).
2. Wrap std.ast parse helpers (`parseExpr`/`parseDecl`/`parseCommaSeparatedExpressions`)
   at every call site in try/catch that converts to DiagReportException
   with the offending Tokens (pattern already in
   parseBlockChain, parsing.cj).
3. Optional: a debug env switch (LUCIDA_VERBOSE_DIAGS=1) that printlns
   every caught message — the session's workaround, kept out of default
   output. The instrumented catch sites: eval_macro.cj (lucidaDispatch),
   user_optic_macro.cj (@Optic), derive_macro.cj (@DeriveOptics).

## Verification
scripts/check_diagnostics.sh stays green AND a deliberately broken chain
in a consumer prints a positioned, readable error.

## Status
RESOLVED. `reportCaughtDiag(tokens, message, hint)` in utils.cj is now the
single reporting path for every macro catch (eval_macro, derive_macro,
inner_macros x3, user_optic_macro x2, tuple_lens_gen). It always calls
diagReport and additionally printlns the message when
LUCIDA_VERBOSE_DIAGS=1 is set — the println survives the suppression
paths (verified in a consumer: a broken chain prints
`@MACRO-DIAG: ... | hint: ...` under the env, and nothing without it).
The empty-token throws are gone: the fused-emission start-anchor match
now covers every CompositionNode case with a real span, and
GenerateTupleExtendsLenses gained catches for its non-diagnostic
`parseAsUInt64` exceptions. lucidaDispatch also converts uncaught
non-diagnostic exceptions to positioned diagnostics.
