# Lucida — API reference

Core types, macros, and optic slots for reading and updating data in Cangjie.
For a first program, start with [Getting started](../getting-started.md).

## Packages

| Package | Import | Contents |
|---|---|---|
| `lucida` | `import lucida.*` | Optic structs and tuple slots |
| `lucida.macrodsl` | `import lucida.macrodsl.*` | Expression and declaration macros |

The `core` dependency supplies both packages. Its current version is `1.0.0`;
see the [dependency setup](../getting-started.md#create-a-consumer-project).

## Structs

`S` is the source type and `A` is the focus type. Operations preserve both types.

| Struct | Members | Purpose |
|---|---|---|
| [`Lens<S, A>`](structs/lens.md) | `view`, `update` | Access one focus and update it using the old source |
| [`Affine<S, A>`](structs/affine.md) | `preview`, `update` | Access a focus that may be absent; preserve the source on a miss |
| [`Prism<S, A>`](structs/prism.md) | `preview`, `build` | Match a focus or construct a source from one |
| [`Iso<S, A>`](structs/iso.md) | `to`, `from` | Convert between a source and a focus in both directions |
| [`Setter<S, A>`](structs/setter.md) | `modify`, `modifyId` | Apply a function through an optic |

Each struct page contains its declaration, member behavior, example, and laws.
For constructing and passing these values, see [Optic values](../examples/optic-values.md).

## Macros

### Expressions

| Macro | Purpose |
|---|---|
| [`@f`](macros/f.md) | Read, update, or construct an optic from a path; includes slot and block syntax |
| [`@ty`](macros/ty.md) | Start an optic path from a source type |
| [`@typeof`](macros/typeof.md) | Start an optic path using an expression's type |
| [`@use`](macros/use.md) | Insert an existing optic value into a path |

### Declarations

| Macro | Purpose |
|---|---|
| [`@DeriveOptics`](macros/deriveoptics.md) | Derive record fields, enum cases, and wrapper conversions |
| [`@Optic`](macros/optic.md) | Declare a named slot with an explicit kind |
| [`@Lens`](macros/lens.md) | Declare a total slot whose update receives the source |
| [`@Affine`](macros/affine.md) | Declare a partial slot whose update receives the source |
| [`@Prism`](macros/prism.md) | Declare a partial slot with a source constructor |
| [`@Iso`](macros/iso.md) | Declare a conversion in both directions |

`Lens` is a struct in `lucida`; `@Lens` is a macro in `lucida.macrodsl`.
The same distinction applies to Affine, Prism, and Iso. There is no `@Setter`
declaration macro.

## Slots

These operations are used inside `@f` paths. A slot is one step in a path;
its spelling can resemble a field or method call.

| Slot | Supplied by | Purpose |
|---|---|---|
| [`._0`, `._1`, …](slots/tuple.md) | `lucida` | Access tuple elements for arities 2 through 16 |
| [`.coerce<T>()`](slots/coerce.md) | `@DeriveOptics` | Convert between a one-field wrapper and its field type |

Record `.field` and enum `?.Case` slots depend on the annotated type; their
rules are documented under [`@DeriveOptics`](macros/deriveoptics.md).

## Related reference

- [Composition](composition.md): compatible types, resulting kinds, and partial paths.
- [API boundaries](internals.md): generated names and helpers reserved for implementation use.
- [Diagnostics](../diagnostics.md): common errors and corrections.

Implementation helpers have public visibility so expanded code can call them.
The application API is the set of items listed above; helper details belong
in the [implementation notes](../README.md#work-on-the-library).
