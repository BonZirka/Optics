# Diagnostics

Diagnostics are macro-time: each one is produced while your code compiles
and points at the exact token that caused it. Three macros emit them —
`@Lucida` rejects a chain it cannot parse or walk, `@DeriveOptics` and
`@LucidaOptic` reject a declaration they cannot expand — and one more
family comes from the type check (one member is caught earlier, at parse
time): mark a segment with the wrong operator
for its kind and the expression resolves only to a strict-`@Deprecated`
overload whose deprecation message is the diagnostic.
[Design decisions](../architecture/design-decisions.md) explains why the
library reports misuse that way. Most messages carry a hint; this page
quotes both. The chain-start and malformed-call messages live in
[the DSL reference](dsl.md), next to the forms they police.

## Operator misuse

The mark names the guarantee, and the compiler holds every segment to it —
derived, user-declared, or the library's own. A mark that contradicts the
kind behind the segment fails to compile with one of these:

| Error | Cause | Fix |
|---|---|---|
| `@Lucida: '.' on a partial optic (Prism/Affine) — its forward returns Either, so a total read is impossible. Use '?.' and match Right/Left.` | A `.`-marked read resolved to a Prism or Affine — a partial optic whose forward returns `Either`. | Mark the segment `?.` and match the result: `Right(payload)` on a match, `Left(source)` on a miss. |
| `@Lucida: '?.' on a total optic (Lens/Iso) — its forward cannot miss, so there is no Either to unwrap. Use '.' for a plain read.` | A `?.`-marked read resolved to a Lens or Iso — a total optic whose forward cannot miss. | Mark the segment `.`; the read is the focus, plain. |
| `@Lucida: '?.' on a total optic (coerce) — its forward cannot miss, so there is no Either to unwrap. Use '.' for a plain read.` | `?.` marked a `coerce<T>()` segment — coercion is fixed-total, so there is no partial read to unwrap. This one is rejected at parse time, before any code is generated. | Mark the segment `.`. |
| `@Lucida: '.'-write through a prism — '.'-writes assert a match and would rebuild the source unconditionally on miss. Use '?.' to preserve the source on miss.` | A `.`-marked write through a `Prism`-kind segment: its backward rebuilds the source from the focus alone, so on a miss the write would rebuild anyway. | Mark the write `?.`; on a miss the source comes back unchanged — the miss is an identity. |

A `.`-write through an affine-kind segment stays legal: its backward
receives the source and keeps it on a miss.

## @DeriveOptics

The derive checks the declaration at expansion time and rejects a shape it
cannot derive from at the offending token — an error at derive time, never
a silently skipped field or case.

- **Annotating anything else** —
  ``@DeriveOptics: deriving optics is only implemented for `struct`, `class` and `enum` ``.
  Only a `struct`, `class` or `enum` carries the plumbing chains ride on.
  Fix: move the derive onto one of those, or hand-write the optics.
- **No primary constructor** — `Primary constructor should be specified`.
  The fields come from the primary constructor; without one there is
  nothing to derive from. Fix: add a primary constructor, or hand-write
  the optics.
- **A parameter that is not a field** —
  `Primary constructor should contain only field declarations`. Only
  `let`/`var` parameters become lenses; a plain parameter cannot be
  focused. Fix: declare it as a field or drop it.
- **A private field** —
  `Primary constructor should contain only non-private field declarations`.
  A field with no access modifier derives as package-visible; a `private`
  one would emit an optic nothing outside the file could reach. Fix: drop
  the `private` modifier or hand-write that optic.
- **A `where` clause on the type** —
  `@DeriveOptics: generic constraints ('where' clauses) are not supported yet`
  (hint: `Remove the constraint or hand-write the optics`).
- **A payloadless case** —
  `@DeriveOptics: enum case 'X' has no associated value; only single-payload cases are supported`
  (hint: `Give the case exactly one associated value, or hand-write its prism`).
  `X` is the case's name.
- **A multi-payload case** —
  `@DeriveOptics: enum case 'X' has N associated values; only single-payload cases are supported`
  (hint: `Bundle the values into one struct and derive optics for that struct`).
  `X` is the case's name and `N` the payload count; the bundle's fields get
  lenses of their own, so the chain continues into them.

## @LucidaOptic

The declaration macro checks the carrier, then the bracket of fields, then
the bodies, and rejects the first shape it cannot use at the token that
caused it.

**The carrier.** The struct is a nameplate for the optic — it carries the
name and type parameters, nothing else.

- **Not a struct** —
  `@LucidaOptic: carrier must be a struct declaration`
  (hint: `Use: @LucidaOptic[fields] struct Name<T> {}`).
  Fix: declare an empty struct.
- **Members on the carrier** —
  `@LucidaOptic: carrier struct must be empty`
  (hint: `The struct only carries the optic name and type parameters`).
  The optic lives in the generated code, so the carrier has no room for
  members. Fix: move them out.
- **A `where` clause** —
  `@LucidaOptic: generic constraints ('where' clauses) are not supported`
  (hint: `Remove the constraint or hand-write the optics`). Type
  parameters work; constraints on them do not.

**The bracket of fields.** Six field names are recognized; their values
are checked as strictly as their presence.

- **A token that starts no field** —
  `@LucidaOptic: unexpected token in fields`
  (hint: `Expected one of: source:, focus:, kind:, args:, forward:, backward:`).
  A misspelled field name reads as an unexpected token. Fix: correct the
  name.
- **An empty field value** — `@LucidaOptic: field 'X' is empty`. `X` is
  the field's name: it parsed but carries no value. Fix: give it one.
- **A field that wants one identifier** —
  `@LucidaOptic: field 'X' must be a single identifier`. `source:`,
  `focus:` and `kind:` take a single name, nothing else. Fix: drop the
  extra tokens.
- **A body without braces** —
  `@LucidaOptic: field 'X' must be a { ... } block`. `forward:` and
  `backward:` are brace-delimited bodies. Fix: wrap the body in
  `{ ... }`.
- **A missing required field** —
  `@LucidaOptic: missing required field 'kind'`,
  `@LucidaOptic: missing required field 'source'`,
  `@LucidaOptic: missing required field 'focus'`,
  `@LucidaOptic: missing required field 'forward'`,
  `@LucidaOptic: missing required field 'backward'` — the message names
  the field to add.
- **An unknown kind** — `@LucidaOptic: unknown kind 'X'`
  (hint: `kind must be one of: Lens, Prism, Affine, Iso`). `X` is what
  you wrote; setters are not declarable here.

**args and the bodies.**

- **An unparseable args list** —
  `@LucidaOptic: cannot parse args list`. `args:` takes function
  parameter syntax, as in `(n: Int64, tag: Bool)`. Fix: check the
  spelling.
- **A reserved arg name** —
  `@LucidaOptic: arg name 'src' is reserved`
  (hint: `src/_src/focus are fixed slots of the generated lambdas`).
  The message names `focus` or `_src` the same way. Fix: rename the arg.
- **`src` in a sourceless backward** —
  `@LucidaOptic: backward of kind 'Prism' has no src slot`
  (hint: `Lens/Affine backwards receive src; Prism/Iso rebuild from focus`).
  Fires for `Iso` too: those backwards rebuild from `focus` alone, so
  there is no `src` slot to name. Fix: rebuild from `focus` (a `src`
  inside a nested lambda is left alone).

## Chain diagnostics

The walk checks the head of the chain first. The derived and user-declared
segments are continuations — they need an owner — and `coerce<T>()`
cannot lead either:

- a derived field first —
  `@Lucida: a derived field optic cannot start a chain here`
  (hint: `Start the chain with the owning value, @Type, @TypeOf or @Optic`);
- a user-declared optic first —
  `@Lucida: user-defined method optics cannot start a chain` (same hint);
- `coerce<T>()` first — rejected at parse time with
  `Cannot make 'coerce<Type>()' method first`; the walk carries the same
  guard as a backstop, `@Lucida: 'coerce<Type>()' cannot start a chain`.

Two more parse-level messages fire on malformed segments:

- wrong generic arity on a coercion —
  `A number of generic parameters should be exactly one` (`coerce<Int, String>()`);
- generics on a derived segment —
  `Generics in Derived optics expression` (hint: `Remove or redesign`;
  fires on `o.name<Int64>`).

Start anchors are start-only in the other direction too. Malformed calls
and unknown modifiers have their own messages.
The full list of chain-start and malformed-call messages, each with the
context it fires in, is in
[the DSL reference](dsl.md) — see
[grammar](dsl.md#grammar) and [starting a chain](dsl.md#starting-a-chain).

## Gotchas

> **Gotcha:** These messages are compile-time only. Runtime behavior has
> no error paths: a partial write's miss is an identity; a partial read's
> miss is a `Left` — misses are values, not errors.

## Where to go next

- [The DSL reference](dsl.md) — every `@Lucida` form, including the
  chain-start and malformed-call messages quoted in context.
- [Deriving](../examples/deriving.md) — what `@DeriveOptics` emits, with
  the rejections above met in the flow of a real derive.
- [User-declared optics](../examples/user-optics.md) — the fields and
  bodies these messages police.
- [Design decisions](../architecture/design-decisions.md) — why the
  operator-misuse messages are delivered by strict `@Deprecated`
  overloads.
