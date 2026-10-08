# Diagnosing errors

[Documentation](README.md) · [API reference](api/index.md)

An error can come from the optic parser, from type checking the generated
code, or from compiling a macro package. Start with the first error that
mentions the expression or declaration you wrote. Later errors may be caused
by the same failed expansion.

This page lists common messages and their causes. It is a troubleshooting
reference, not a guarantee of exact compiler wording across SDK versions.
The regression probes live in
[`check_diagnostics.sh`](../scripts/check_diagnostics.sh).

## Imports and dependencies

Code using optics normally needs:

```cangjie
import lucida.*
import lucida.macrodsl.*
```

Array selection also needs `import lucida_stdlib.*` and a dependency on the
`stdlib` workspace member. Use `lucida.macrodsl`, not `lucida_macro`, and
`lucida_stdlib`, not `lucida.stdlib`.

A consumer's dependency paths point to `core` and, optionally, `stdlib`.
The workspace root includes the test project and is not the dependency path
shown in the [getting-started manifest](getting-started.md).

## Operators

| Message contains | Cause | Change |
|---|---|---|
| `'.' on a partial optic (Prism/Affine)` | A read treats a partial slot as total | Use `?.` at that slot and handle the resulting `Option` |
| `'?.' on a total optic (Lens/Iso)` | A total slot is marked partial | Use `.`; if its field type is `Option`, unwrap it separately |
| `'?.' on a total optic (coerce)` | A conversion is marked partial | Use `.coerce<T>()` |
| `rebuild the source unconditionally on miss` | A total-marked write uses a prism's source-free constructor | Use a partial update with `?.` |

The check is made against each slot's registered kind. A partial slot
elsewhere in the same path does not make a total field partial.

## Paths and blocks

| Message contains | Cause or resolution |
|---|---|
| `expects at least one argument` | `@f()` needs a path |
| `Unknown expression` | The macro did not recognize a path; ordinary arithmetic and indexing expressions are not optic slots |
| `expects a value after '<-'` | Supply the replacement expression |
| `only allowed at the start of a chain` | Move `@ty` or `@typeof` to the start |
| `macro input should be type (RefExpr)` | `@ty` expects a plain type identifier; use `@typeof(value)` for a generic instantiation such as `Box<Int64>` |
| `macro should be contained inside '@f'` | An inner macro such as `@use` is being used outside its supported parent |
| `expects exactly one type argument` | Write `.coerce<T>()` with the target type |
| `requires a tuple target` | Supply a tuple literal for a block with several entries |
| `tuple target has ... elements` | Match the number and nesting of block entries |
| `expected a block chain starting with '.'` | Start an entry with a field, such as `.name`, and separate entries with `;` |
| `block chains conflict on a shared prefix` | Check for a repeated field path; comparison of custom paths can also be conservative |
| `blocks require a value anchor` | Apply the block to a value instead of constructing a first-class block optic |

For a block behind a selection, put the selection at the end of the anchor:
`items?.at(0).{ .name; .address.city }`. Arbitrary partial slots inside
anchors or nested prefixes may fail during type checking rather than with a
specific macro diagnostic.

Passing a built-in type keyword such as `Int64` to `@ty` can also produce
`macro evaluation has failed` with an AST parsing error. Use a typed value
with [`@typeof`](api/macros/typeof.md); see [`@ty`](api/macros/ty.md) for its
accepted input.

## Derivation

`@DeriveOptics` accepts a struct, class, or enum. Record derivation requires a
primary constructor whose parameters declare non-private fields. A normal
parameter without `let` or `var` does not provide a field that can be read
back during reconstruction.

`generic constraints ('where' clauses) are not supported` is an explicit
implementation restriction. Removing a necessary constraint is not a general
solution: use a suitable concrete optic or a manually constructed optic
value when the model requires the constraint.

## Custom declarations

| Message contains | Cause or resolution |
|---|---|
| `carrier must be a struct declaration` | Place the macro on an empty struct |
| `carrier struct must be empty` | Remove members and constructors; the carrier only supplies a name and generic parameters |
| `missing required field` | Supply source, focus, forward, backward, and a kind when using `@Optic` |
| `unexpected token in fields` | Check attribute names and separators |
| `unknown kind` | Use Lens, Affine, Prism, or Iso |
| `takes no 'kind' field` | A kind alias such as `@Lens` already specifies its kind |
| `must be a { ... } block` | Enclose a forward or backward body in braces |
| `has no source parameter` | A Prism or Iso backward receives only a focus |
| `binds ... parameters; expected ...` | Match the parameter count to the kind's function shape |
| `arg name ... is reserved` | Rename an argument called source, focus, or _source |

A repeated declaration can fail on a generated name such as
`__name_impl_kind_...`. Same-named optics on the same source can also collide
on `__downcast_method_name`. Different interface signatures do not make those
dispatch members distinct.

The bodies are Cangjie code. The macro cannot determine whether they have the
right result type or satisfy optic laws before the compiler checks the
expansion.

## Investigating a macro failure

Build the smallest package that reproduces the error. Record `cjc -v`, the
build command, and the complete output. `--debug-macro` can help expose the
expanded expression. `LUCIDA_VERBOSE_DIAGS=1` enables additional diagnostic
output from the library's reporting helper.

After changing a macro package, stale consumer build products can produce
misleading errors. Rebuild the library and the affected consumer from clean
build products; [development](development.md) explains the package layout.

A compiler process exiting with code 139 is different from a rejected optic
expression. Keep that log and try the smallest reproducible compilation.
A retry that succeeds does not identify the cause.

## Test harness errors

`@InlineOptics` belongs to the test project. Its errors about `shapes`, `root`,
unknown fields, or missing registry metadata concern that harness, not normal
`@f` use. Its inner-macro and tuple support is narrower than the library's.
See the [harness reference](architecture/inline-harness.md).
