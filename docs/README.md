# Documentation

These pages assume that you can read Cangjie structs, enums, generic types,
and function values. No knowledge of optics or functional programming is
required.

Start with [Getting started](getting-started.md) to run an update. Then read
[Understanding optics](introduction-to-optics.md) for an explanation of the
operations behind the syntax.

## Learn by example

| Topic | What you will learn |
|---|---|
| [Fields and lenses](examples/lenses.md) | Read a field, replace it, and preserve the enclosing record |
| [Enum cases and partial access](examples/prisms.md) | Handle a match or a miss and distinguish a prism from an affine |
| [Longer paths and blocks](examples/chains.md) | Select array elements and update several related fields |
| [Deriving optics](examples/deriving.md) | Use structs, classes, enums, generics, tuples, and wrapper conversions |
| [Declaring custom optics](examples/user-optics.md) | Define a slot and make its behavior available to `@f` |
| [Optic values](examples/optic-values.md) | Construct optics, call their members, and pass them to other functions |

## API reference

The [API index](api/index.md) lists the application interface by declaration
kind. Each item has a page with its declaration, members or inputs, behavior,
and examples.

| Reference | Contents |
|---|---|
| [Structs](api/index.md#structs) | `Lens`, `Affine`, `Prism`, `Iso`, and `Setter`; constructors, members, and laws |
| [Expression macros](api/index.md#expressions) | `@f`, `@ty`, `@typeof`, and `@use`; paths, reads, updates, and blocks |
| [Declaration macros](api/index.md#declarations) | `@DeriveOptics`, `@Optic`, and the four kind aliases |
| [Slots](api/index.md#slots) | Tuple elements and `coerce` conversions |
| [Composition](api/composition.md) | Combining optics and determining the resulting kind |
| [API boundaries](api/internals.md) | Supported names and generated implementation helpers |

Examples that continue an earlier declaration say which declaration they use.
Code marked as pseudocode explains a transformation and is not intended to be
compiled. The getting-started program is complete, including its manifest.

## Troubleshooting

[Diagnostics](diagnostics.md) explains common errors and how to correct them.
For toolchain setup and build failures, see [Development](development.md).

## Work on the library

Read [Development](development.md) for the workspace, verification commands,
and documentation conventions. The [glossary](terminology.md)
defines the terms used throughout the documentation. The implementation
notes then cover:

- [Design decisions](architecture/design-decisions.md): choices and tradeoffs.
- [Macro processing](architecture/macro-system.md): parsing and generated code.
- [Registry dispatch](architecture/registry-plumbing.md): how types select an optic.
- [Fusion](architecture/fusion-walk.md): reading and rebuilding a chain.
- [The direct-expansion harness](architecture/inline-harness.md): the test-only
  reference implementation used in performance work.

[Benchmarks](benchmarks.md) record measurements and their conditions.
[Compiler notes](compiler-issues.md) describe observations on specific compiler
versions. The [changelog](../CHANGELOG.md) records released changes.
