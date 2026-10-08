# Design decisions

This chapter explains the choices represented by the current implementation.
It assumes the terminology in [Understanding optics](../introduction-to-optics.md).
The examples and API reference describe how to use the library; this chapter
is intended for readers considering changes to it.

## Reconstruct values along an update path

Derived record updates call the record constructor with a replacement field
and the original values of the other constructor fields. This gives the DSL
an expression result and lets a caller retain the original source.

The cost is reconstruction along the path. For a mutable array, the standard
index optic must also copy before replacing an element. Other field values
may still be shared. User constructors and custom optic functions can have
side effects, so the library does not establish deep immutability or purity
for arbitrary supplied types.

An in-place assignment remains appropriate when a program owns mutable state
and does not need to retain its previous value. Benchmarks should identify
which behavior is being compared.

## Represent optics with concrete function shapes

The five public structs store the operations each kind needs. A lens has a
total read and a sourceful update; a prism has a partial read and a source-free
constructor. Affines, isos, and setters complete the supported combinations.
The signatures are visible in
[`first_class.cj`](../../core/src/first_class.cj).

This representation makes direct construction and ordinary function calls
available without a DSL. It also permits composition overloads to be selected
by concrete types. The implementation generates the 25 ordered kind pairs
instead of requiring callers to supply an abstract encoding.

The API is monomorphic: a `Lens<S, A>` writes an `A` back into an `S`.
There is no type-changing update or separate traversal interface for reading
several focuses.

The source code supports these statements about the present design. It does
not establish that other optic encodings are impossible in Cangjie.

## Let the compiler resolve slot types

A path macro has syntax such as `source.address.city`. Its implementation does
not query the compiler for the resolved type of each intermediate expression.
It emits typed helper calls and lets ordinary type checking resolve them.

`RegistryMagical<T>` carries the type at a point in the path. Generated
members select a kind registry, expose the slot functions, and identify
the next focus type. [Registry dispatch](registry-plumbing.md) follows this
sequence.

This avoids maintaining a second type-resolution system in the macro.
The cost is a generated declaration surface and occasional diagnostics in
that generated code. Changes to helper visibility must account for consumer
packages where the expansion is compiled.

## Make partial access explicit

The DSL uses `.` for total access and `?.` for partial access. For a read,
this tells a reader where failure can enter the path and explains whether
the result is a focus or an `Option`.

The operator is checked against the slot's registered kind. It is not an
instruction to unwrap any field whose type contains `Option`. A total field
lens returning `Option<T>` and a partial operation returning a focus `T`
are different operations.

The explicit marker adds syntax that callers must learn, and misuse needs a
clear diagnostic. The current write implementation also permits some
sourceful affine backwards under a total marker. Documentation recommends
`?.` for partial slots consistently; the reference records the exception.

## Derive from constructor structure

A record's primary constructor gives the macro a field order and a way to
rebuild the record. A single-field record also gives a straightforward pair
of wrapper conversions. An enum declaration supplies case names and payload
positions.

The derivation consequently has a specific supported model: non-private
constructor fields, reconstructible through that constructor, without
`where` constraints. Properties, arbitrary initialization logic, and hidden
state cannot be assumed to obey the same reconstruction rules.

For enum cases, the generated kind is `Affine`. Its update accepts the source
and preserves another case on a miss. A user who needs unconditional case
construction can declare or construct a `Prism` separately. Cases with
several payloads use a tuple focus; a payloadless case uses `Unit`.

## Require explicit generic parameters on custom declarations

A custom optic uses an empty carrier declaration such as `struct item<T> {}`.
The carrier provides a name and an explicit generic parameter list. The macro
consumes the carrier and generates registration declarations.

An identifier in `source: Box<T>` could name a parameter or a concrete type.
The current macro therefore takes parameters from the declaration rather
than trying to infer them from the spelling of a type. Concrete arguments
such as `Box<Int64>` remain concrete.

Generated methods belong to generic extensions; they are not themselves
methods with that same generic parameter list. Callers infer the parameters
through the source. Explicit method type arguments and generic constraints
are unsupported.

## Generate interface names from signatures

Two custom optics can use the same name for different source types. Their
interfaces include an encoding of the kind, source, focus, and arguments,
so their declarations do not collide merely because the names match.

The dispatch member still uses the optic name: the expression contains that
name, while type resolution supplies the source. Consequently, declarations
with the same name and source can still collide. Interface naming does not
provide arbitrary overload resolution between such declarations.

The old `@Optics` grouping macro is no longer needed by this scheme. Removing
it also removed checks that compared declarations within a group; some
collisions now produce ordinary compiler diagnostics.

## Fuse known value paths

The value-path emitter generates a sequence of reads followed by a backward
reconstruction. This avoids combining an intermediate function pair at every
slot of a path whose structure is already known.

First-class optic construction still needs reusable function values, and
`[unfuse]` retains the composition path for comparisons. A first-class lens
inside a value chain can be handled by splitting the path and continuing at
its focus. Block expressions have a dedicated emitter.

Fusion is an implementation strategy, not a zero-cost guarantee. Generic
accessors, constructors, and function boundaries can remain in the generated
program. The [recorded benchmarks](../benchmarks.md) show measurable overhead
relative to handwritten reconstruction.

## Use overloads for checks that need resolved kinds

Parsing catches malformed declarations and unsupported syntax. Checks that
need the actual resolved kind are emitted as helper calls with kind-specific
overloads. Invalid combinations select strict-deprecated overloads whose
messages explain the operator error.

This gives the compiler a diagnostic at a point where the macro itself does
not know the types. It also ties the presentation to compiler overload and
deprecation behavior. Errors outside those checked combinations may still
appear as type-inference or missing-member errors in expanded code.

See [diagnostics](../diagnostics.md) for the application-facing explanation
and [`magical.cj`](../../core/src/magical.cj) for the overloads.

## Keep implementation helpers accessible to expansions

Consumer expansions refer to library helpers. The current import strategy
makes them available through `lucida.*`, with reserved names distinguishing
them from application interfaces.

Public visibility is broader than the supported API. That distinction must
remain explicit in the reference. Conventional generated names also leave
some collision risk; a reserved prefix reduces that risk without proving
complete macro hygiene.

## Keep the measurement harness in the test project

`@InlineOptics` expands a restricted path using explicitly supplied shape
metadata. It provides a direct reconstruction for comparison with `@f`.
Consumers of the library do not need to compile or import it.

This boundary keeps experimental measurement machinery out of the application
API. Its cost is a second parser, currently copied into the test macro
package, and narrower coverage of some forms. Equivalence tests and diagnostic
probes help detect drift, but uncovered forms remain an explicit limitation.
