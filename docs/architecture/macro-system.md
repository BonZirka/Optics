# Macro processing

Lucida uses declaration macros to register operations and an expression macro
to turn a path into calls to those operations. Type checking occurs on the
emitted Cangjie code.

This page maps the implementation. Read [registry dispatch](registry-plumbing.md)
for the generated types and [fusion](fusion-walk.md) for path execution.

## Declaration entry points

| Macro | Input | Main output |
|---|---|---|
| `@DeriveOptics` | A struct, class, or enum declaration | The original declaration plus optic registrations |
| `@Optic` and kind aliases | Attributes and an empty struct carrier | Custom optic registrations |
| `@GenerateCompositions` | The internal composition host | Composition and registry-upcast overloads |
| `@GenerateTupleExtendsLenses` | A maximum tuple arity | Tuple field operations and registrations |
| `@GeneratePrismForward` | A maximum partial-step count | Typed helpers for partial forward walks |

The last three are library implementation macros, not application declaration
APIs.

## Record derivation

[`derive_macro.cj`](../../core/src/macrodsl/derive_macro.cj) parses the
annotated declaration. `deriveRecordOptics` obtains the primary constructor's
fields and rejects unsupported constraints or constructor parameters.

For each field it emits a read function and a reconstruction function. It
also emits members that expose the focus type and select the lens registry.
Public field operations are made available through generated interfaces and
extensions; other accepted fields receive package-visible operations.

For a one-field record, the macro additionally emits both directions of the
iso between the record and its field type. The conversion members take source
and target type witnesses so several conversions can be resolved by type.

The macro does not inspect a constructor body to prove purity, preservation
of hidden state, or the optic laws.

## Enum derivation

The forward function pattern-matches the case. A hit returns a focus wrapped
in `Some`; a miss returns `None`. The focus is the single payload, a tuple of
payloads, or `Unit`, according to the case shape.

The generated backward function receives both source and replacement. It
rebuilds the matching case and preserves another case. Registration therefore
uses `RegistryAffines`, even though case matching is often introduced using
prisms in optics literature.

## Custom declarations

[`user_optic_macro.cj`](../../core/src/macrodsl/user_optic_macro.cj) validates
the carrier and the attribute fields, chooses the function shapes, and emits
the registration. Kind aliases call the same implementation while retaining
their own name for diagnostics.

The carrier is not re-emitted. Its identifier and generic parameter list
supply the declared slot's name and parameters. `args:` becomes the
argument list accepted by its generated methods.

Bare bodies use fixed `source` and `focus` parameters. A parameter prefix in a
body supplies replacement names for those parameters. The macro checks their
arity and rejects a source parameter in a source-free backward.

Interface identifiers incorporate the declaration signature through
`mangleUserIface`. Alphanumeric bytes are retained; underscores and other
bytes are escaped. The representation normalizes whitespace as implemented
by the helper. Dispatch member names remain keyed to the optic name.

## Expression parsing

[`parsing.cj`](../../core/src/macrodsl/parsing.cj) builds an `OpticalExpr`:

- `OpticsForward` or `OpticsBackward` for an applied value path.
- `FirstClassOptics` or `FirstClassSetter` for a type/optic-anchored path.
- `SiblingForward` or `SiblingBackward` for a block.

Slots become `CompositionNode` values: a derived member, a custom member,
a conversion, a type witness, or an optic value. The parser records the
operator's total/partial expectation. It does not know the final resolved
optic kind.

Block parsing tracks delimiter depth, separates entries with semicolons, and
constructs `BlockSpec` and `BlockEntry` nodes. A nested entry carries a prefix
and an inner block. Replacement tuples are checked against entry counts;
opaque nested tuple expressions are destructured by the emitted program.

## Inner macros

[`inner_macros.cj`](../../core/src/macrodsl/inner_macros.cj) implements `@ty`,
`@typeof`, and `@use`. They verify that they occur inside `@f` and emit marker
calls that the outer parser recognizes.

This parent check is significant for other macros: putting those forms inside
`@InlineOptics` does not make them available to its parser. They reject that
parent before the harness can interpret them.

## Emission

[`eval_macro.cj`](../../core/src/macrodsl/eval_macro.cj) wraps the generated
expression in a local function scope. `evalOptics` selects the value-path,
composition, or block emitter.

`composeOptics` obtains each slot's functions and combines them using the
generated composition overloads. First-class forms finish by constructing the
corresponding public optic struct. Preset replacements finish through the
setter adapters.

The fused emitters bind the operations needed by the walk, read intermediate
values, and rebuild outward. A read need not bind unused backwards. Blocks
thread updates through an owner and recursively handle nested entries.

## Diagnostics and source positions

Macro validation throws `DiagReportException`. The catch path reports the
message through `reportCaughtDiag` and returns the original tokens, which may
then produce secondary compiler errors. The declaration and expression entry
points also emit diagnostic breadcrumbs.

A source token can carry a useful location; a synthesized token may not.
[`utils.cj`](../../core/src/macrodsl/utils.cj) contains the reporting helper
and `LUCIDA_VERBOSE_DIAGS` support. Kind-dependent errors are checked later
by the helper overloads in the core package.

## Maintaining emitted code

Generated identifiers are conventional names, not a proof of collision-free
expansion. Keep new helper names in the reserved namespace and inspect how
consumer expressions enter their local scopes.

When rebuilding generic lists from AST fields, insert the required commas
explicitly. The current implementation handles declaration parameters and
call-site type arguments separately; older experiments exposed different
separator behavior in those AST representations.

Check both ordinary and `[unfuse]` forms after changing path emission. Update
the test harness parser when changing the accepted grammar. The law suite,
diagnostic probes, and generated-expression comparison test different parts
of that change.
