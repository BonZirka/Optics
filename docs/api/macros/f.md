# @f

`@f` interprets a path made of registered optic slots. Import `lucida.*`
and `lucida.macrodsl.*`.

Package: `lucida.macrodsl` · [API index](../index.md) · [Source](../../../core/src/macrodsl/eval_macro.cj)

```cangjie
public macro f(input: Tokens): Tokens
public macro f(attr: Tokens, input: Tokens): Tokens
```

The examples use `Address`, `Person`, and `person` from
[Getting started](../../getting-started.md).

## Input and result

| Form | Result |
|---|---|
| `@f(value.field)` | The selected value |
| `@f(value.field <- replacement)` | A rebuilt source value |
| `@f(@ty(Type).field)` | An optic value |
| `@f(@typeof(value).field)` | An optic using the expression's type |
| `@f(@use(optic).field)` | An optic composed with the supplied optic |
| `@f(@ty(Type).field <- replacement)` | A setter with a preset replacement |

The return type depends on the slots. A lens path reads its focus directly;
a path with partial access reads `Option<Focus>`. A value update returns its
source type. A setter has no focus-reading operation: the implementation's
forward form applies its `modifyId` operation.

[`@ty`](ty.md), [`@typeof`](typeof.md), and [`@use`](use.md) are only valid
inside `@f`. `@ty` and `@typeof` start paths; `@use` may also occur within a
path. Give `@use` an identifier bound to an optic value.

## Slots

A **slot** is one step in an optic path. In `person.address.city`, the root
is `person`, and the slots are `.address` and `.city`. Slots can also select
array elements or enum cases, perform conversions, and apply custom optics.

| Slot | Meaning |
|---|---|
| [`.field`](deriveoptics.md#records) | A derived record field |
| [`?.Case`](deriveoptics.md#enums) | A derived enum case |
| [`._0`, `._1`, …](../slots/tuple.md) | A tuple element, for tuple arities 2 through 16 |
| `.name(arguments)` | A total declared optic |
| `?.name(arguments)` | A partial declared optic |
| [`.coerce<Type>()`](../slots/coerce.md) | A registered iso conversion |
| `.@use(optic)` | A supplied optic value |

Method-like slots are names registered by optics. An arbitrary Cangjie
method call is not automatically a slot. Index expressions such as `array[0]`
are not supported inside a path.

The `coerce` name is reserved. It requires exactly one type argument and no
partial marker. Automatic conversions come from one-field record derivations.

## Total and partial slots

A dot marks total access. A question-dot marks access that may find no focus.
For example, this enum adds a partial selection of a `Person`:

```cangjie
@DeriveOptics
public enum Selection {
    | Empty
    | Selected(Person)
}
```

Inside a function:

```cangjie
let selection = Selection.Selected(person)
let name = @f(selection?.Selected.name)
```

Here `Selected` is partial and `name` is total. The result has type
`Option<String>`. A source of `Selection.Empty` produces `None`.

The operators do not infer optionality from a field's return type. Reading a
field of type `Option<T>` with `.` obtains that field value. Writing `?.`
before an ordinary field does not add an unwrapping operation.

Reads check the operator against the actual optic kind. A total read through
a prism or affine and a partial read through a lens or iso are rejected.
A first-class optic inserted with `@use` carries its own kind.

There is an implementation exception for writes: a sourceful affine backward
can accept a total-marked replacement because its own function handles misses.
A prism's source-free backward cannot safely do that, and the total-marked
write is rejected. Prefer `?.` consistently for partial slots in
application code.

## Replacements

```cangjie
let updated = @f(person.address.city <- "Oslo")
```

`<-` separates the path from the replacement expression. It returns a rebuilt
person and does not assign to `person`. The focus and source types remain the
same. A path with a partial slot preserves the source when it misses.

For a type-anchored path, `<-` constructs a preset setter instead of performing
an update. Its modifier acts on the supplied target; see
[preset replacements](../structs/setter.md#preset-replacements-from-the-dsl).

## Blocks

A block reads or updates several paths relative to one value:

```cangjie
let selected = @f(person.{ .name; .address.city })
let updated = @f(person.{ .name; .address.city } <- ("Ada", "Oslo"))
```

The read returns a tuple in entry order. A single-entry block returns the
entry's value directly. The outer target for a multi-entry update must be a
tuple literal with the same number of elements as the block.

Nested blocks preserve their grouping:

```cangjie
let updated = @f(person.{ .address.{ .city; .zip }; .name } <- (("Oslo", 30003), "Ada"))
```

The nested target can be a tuple expression that the emitter destructures.
The nested prefix is traversed once for that entry, and target expressions
are evaluated once within the emitted block operation. Flat entries that
happen to share a prefix do not imply the same shared traversal.

Supported blocks have these constraints:

- The anchor is a source value, not a first-class optic construction.
- Every entry starts with a field access such as `.name` or `._0`.
- A partial anchor is supported when its final slot is partial, as in
  `selection?.Selected.{ .name; .address.city }`.
- Nested shared prefixes should be total. Arbitrary partial paths through
  block anchors and nested blocks are not generally supported.
- Duplicate field paths are rejected. The parser's comparison of custom
  slots is conservative; it does not prove that arbitrary custom updates
  are independent.

Entries apply in order to the accumulating owner value. For distinct ordinary
fields this gives the expected simultaneous-looking result. Custom backwards
can inspect or change other fields, so entry order can affect their result.

## Execution modifier

```cangjie
let updated = @f[unfuse](person.address.city <- "Oslo")
```

`[unfuse]` requests the composition implementation for an ordinary chain.
It does not alter the requested update, and it is mainly useful in tests and
benchmarks. Blocks continue to use their block emitter.

The fused forward implementation uses generated helpers for up to 16 partial
slots per supported walk; longer partial reads fall back to composition.
This is an implementation limit, not a restriction to 16 fields in a path.

## Expression behavior

Keep selection predicates and custom optic functions free of side effects
when composing them. Reconstruction can invoke user functions and record
constructors; `@f` does not enforce purity or roll back effects.

The macro is a path language, not a general expression evaluator. Arithmetic
such as `@f(3 + 4)` is not a path. Use a normal expression for calculations and
put the resulting value on the replacement side of `<-`.

See [diagnostics](../../diagnostics.md) for errors and
[longer paths](../../examples/chains.md) for examples with declarations.
