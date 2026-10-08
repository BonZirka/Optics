# The direct-expansion harness

`@InlineOptics` is a test-project macro used to compare `@f` with a directly
written reconstruction. It is not exported by `lucida`, and it is not an
alternative application API.

The macro receives a path plus explicit descriptions of the types on that
path. It can then emit field accesses, constructor calls, and matches without
using Lucida's runtime registry helpers.

## Example

In the test project, import `tests.inline.*`. Suppose `InlTip` is the
record from the harness tests with constructor fields `v` and `w`:

```cangjie
let direct = @InlineOptics[
    shapes: (InlTip, (v, Int64), (w, Int64)),
    root: InlTip
](tip.v <- 9)
```

The direct reconstruction is `InlTip(9, tip.w)`. A corresponding `@f` update
should produce the same relevant field values.

The explicit shape metadata is required because this macro does not query
resolved type layouts. A wrong layout can produce wrong generated code;
comparison against the independent handwritten expression is therefore part
of the check.

## Two checks

The generated corpus has 15 shapes, each with a read and a write expression.

**Value comparison.** Tests compare the harness result, the handwritten
expression, and `@f` where that form is supported. The `Option8` shape has no
corresponding built-in `@f` path and is checked against its handwritten form.
The handwritten harness tests cover additional forms and misses.

**Expression comparison.** `scripts/check_codegen.sh` compares the 30 dumped
expressions against `expected_expansions.txt`. Normalization removes
whitespace and selected generated binder/counter spelling. Other token
differences remain visible.

These checks answer different questions. Equal results for sample values do
not imply identical expansions, and identical normalized expansions do not
establish coverage of every input or effect.

## Attributes

`shapes:` lists records with fields in constructor order:

```text
shapes: (Owner, (field, FieldType), (other, OtherType)),
        (Child, (value, ValueType))
```

An enum shape lists cases and their payloads. A payloadless case uses `()`:

```text
shapes: (Slot, (Empty, ()), (Held, (value, Int64)))
```

`root:` names the source expression's type. It must identify a supplied shape
or another type supported by the harness's metadata handling.

`registry:` supplies metadata for named slots. Its body form provides
forward and backward code and the focus type:

```text
registry: (name, body, { source => FORWARD },
           { source, focus => BACKWARD }, FocusType)
```

There is also a derived-field metadata form `(name, OwnerType, field)`.
Having metadata for an optic does not bypass the parent-macro restrictions
on `@use`, `@ty`, or `@typeof`.

Pass the path expression itself as the macro input. Do not wrap it in `@f`:
the nested macro would expand before the harness receives the input.

## Coverage and limits

| Form | Current harness coverage |
|---|---|
| Derived field reads and updates | Supported with shape metadata |
| Enum cases and fields below a case | Supported for represented payload layouts |
| Sibling and nested blocks | Supported within the harness's block restrictions |
| Block directly anchored on a partial case | Supported |
| One-field `coerce<T>()` | Supported after validating the shape and target type |
| Custom method slot | Requires explicit registry metadata |
| Array index or predicate selection | Requires suitable per-call metadata |
| Tuple element optics | No general tuple-shape support |
| `@use`, `@ty`, `@typeof` | Rejected by their parent checks outside `@f` |
| `Option` field unwrapping | A harness extension used by `Option8`; not matching built-in `@f` syntax |

A block can be anchored directly on the payload selected by a final partial
slot. The harness rejects an anchor that crosses a partial slot and
then continues before reaching the block. Its diagnostic probes also reject
partial markers on total fields and invalid coercions.

Missing harness coverage does not imply that the corresponding ordinary
library feature is missing. Tuple optics and first-class lenses, for example,
have their own tests in the main suite.

## Source layout and grammar maintenance

- [`inline_macro.cj`](../../tests/src/inline/inline_macro.cj) reads metadata and
  emits the direct expression.
- [`parser.cj`](../../tests/src/inline/parser.cj) is a copy of the path parser
  adapted for this package.
- [`inline_optics.cj`](../../tests/src/inline_optics.cj) compares individual forms.
- [`gen_bench.py`](../../scripts/gen_bench.py) writes the generated shape corpus
  and expected expansions.

The parser copy keeps private production parser types out of the public API,
but introduces a maintenance cost. Review both parsers when changing grammar.
Current equivalence tests and negative probes cover specific forms; they do
not mechanically guarantee that the grammars stay identical.

## Running the checks

With the Cangjie SDK environment loaded:

```sh
./scripts/check_codegen.sh
```

The script temporarily removes the handwritten harness test file from the
build so the expansion dump contains only the generated corpus. Its exit trap
restores that file. Do not run another test-project build or edit that file
concurrently.

Performance runs are separate:

```sh
./scripts/bench.sh
```

The current generated tables time handwritten reconstruction, fused `@f`,
and ordinary composition where supported. The harness expansion is checked
against reconstruction and is not timed as a separate column.
The [benchmark record](../benchmarks.md) gives the recorded comparisons and
measurement conditions.
