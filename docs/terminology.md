# Terminology

Terms used in the API reference, guides, and implementation notes.

## Values and types

| Term | Meaning |
|---|---|
| Source | The input value on which an optic operates; conventionally type `S` |
| Focus | The value an optic provides access to when access succeeds; conventionally type `A` |
| Replacement | The new focus supplied to `update` or the right-hand side of `<-` |
| Modifier | A function `(A) -> A` applied through a setter |
| Result | The value returned by an operation |
| Optic | A description of access and reconstruction with one of the supported kinds |
| Optic value | An optic held in a variable or passed to a function |
| Optic kind | Lens, Affine, Prism, Iso, or Setter |

Source and focus are relative to an optic. An address can be the focus of a
person-to-address optic and the source of an address-to-city optic. A focus
can be a stored field, a case payload, or the result of a conversion.

A **first-class optic** is an optic value. Declaration macros register named
slots; they do not themselves bind variables containing optic values.

## Operations

| Operation | Meaning | API |
|---|---|---|
| View | Obtain a lens's focus | `view` |
| Preview | Attempt to obtain a focus, returning `Some(focus)` or `None` | `preview` |
| Update | Return a source with a supplied replacement at its focus | `update` |
| Convert to | Convert an iso's source to its focus | `to` |
| Convert from | Convert an iso's focus back to its source | `from` |
| Build | Construct a prism's source from a focus | `build` |
| Modify | Apply a modifier through an optic | `modify` |
| Compose | Combine compatible optics in application order | `@f` with `@use` |

**Read** collectively describes obtaining a focus through `view`, `preview`,
or `to`. **Reconstruction** is the work of forming the resulting source from
its enclosing values. A DSL update returns that source value.

The exact member signatures are listed in the [API reference](api/index.md#structs).
Preset replacement setters have the behavior described under
[`Setter`](api/structs/setter.md#preset-replacements-from-the-dsl).

## Total and partial access

**Total access** always produces a focus. **Partial access** may find no focus
and reports the result with `Option`. A **match** produces `Some(focus)`;
a **miss** produces `None`.

These terms describe the presence of a focus. User code can still throw an
exception. An expected miss is distinct from a compiler or runtime error.
A total field whose value is `Option<T>` still provides that field value on
every read.

**Access mode** describes the expectation expressed by `.` or `?.` in a slot.
**Optic kind** describes the registered behavior selected by type checking.
`.` applies to Lens and Iso; `?.` applies to Affine and Prism. The current
write exception for affines is documented in [`@f`](api/macros/f.md#total-and-partial-slots).

## Path syntax

| Term | Meaning |
|---|---|
| Optic expression | The complete expression interpreted by `@f` |
| Path | A root followed by optic slots |
| Root | The starting value, type expression, or optic expression |
| Slot | One step in a path: a field, case, custom call, conversion, or inserted optic |
| Relative path | A path interpreted from an enclosing block's source |
| Block | A `{ ... }` group of entries |
| Entry | One relative path, optionally ending in a nested block |
| Block prefix | The path leading to the value on which a block operates |
| Block source | The value reached by the block prefix |

In `person.address.city`, `person` is the root, and `.address` and `.city`
are slots. A slot describes an operation and need not correspond to a stored
field or memory location.

```text
@f(person.address.{ .city; .zip } <- ("Oslo", 30003))

root:          person
block prefix:  person.address
block source:  the selected Address value
entries:       .city and .zip
replacements:  "Oslo" and 30003
```

Implementation notes also use **chain** for a path, **anchor** for a root or
block prefix, and **sibling block** for a block of relative entries.

A **parameter** is a name bound in a function or custom optic body, such as
`source` or `focus`. An **argument** is an expression supplied at a call.

A path rooted in a value applies an operation to that value. A path rooted
in a type or optic value constructs an optic value.

## Implementation terms

| Term | Meaning |
|---|---|
| Parse | Convert input syntax to the internal expression representation |
| Resolve | Select declarations or kinds using type information |
| Emit | Produce Cangjie tokens |
| Expansion | The generated code resulting from a macro call |
| Type witness | A value used to carry type information for resolution |
| Registry | The generated declarations through which optic operations are resolved |
| Fusion | Generate a combined execution sequence for a known path |

The **forward adapter** and **backward adapter** are the function shapes used
by composition. Forward adapters expose `view`, `preview`, `to`, or a setter's
`modifyId`; backward adapters expose `update`, `from`, `build`, or `modify`.

See [macro processing](architecture/macro-system.md),
[registry dispatch](architecture/registry-plumbing.md), and
[fusion](architecture/fusion-walk.md) for the implementation.
