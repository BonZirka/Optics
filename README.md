# Optics (lucida)

An optics library for [Cangjie](https://cangjie-lang.cn): lenses, prisms,
affines, isos and setters with a `@Lucida` update DSL, a `@DeriveOptics` code
generator, and a generated composition table.

```cangjie
@DeriveOptics
public struct GBox<T> {
    public GBox(public let v: T) { }
}

let b = GBox<Int64>(5)
@Lucida(b.v)                  // res: 5 — a read evaluates the focus
@Lucida(b.v <- 7)             // res: a new GBox(7); b still holds 5

let nums = [10, 20, 30]
@Lucida(nums?.at(1) <- 99)    // res: [10, 99, 30]
@Lucida(nums?.at(7) <- 99)    // res: [10, 20, 30] — a miss returns the source unchanged
```

Updates are **immutable** — they return a new value; the original is never
mutated.

## Why Lucida

- **Kind-exact operators.** `.` marks a total segment (the part is always
  there), `?.` a partial one (it may miss). Mark the wrong pair and it fails
  to compile — with a message that says what was illegal and which operator
  to use.
- **`@DeriveOptics`.** One line on a type: a lens per constructor field, a
  prism per enum case — the payload for single-payload cases, a tuple of
  payloads for multi-payload cases, `Unit` for payloadless ones — and an iso
  per one-field wrapper.
- **`@LucidaOptic`.** Declare the optics a derive cannot: an array slot at an
  index, a hand-built segment, a generic carrier.
- **Fused chains.** A chain compiles to direct nested calls — no optic values
  composed at runtime.
- **First-class optics.** Hold a lens in a value, pass it around; 25 kind
  pairs compose with upcasting.

## Documentation

- [Getting started](docs/getting-started.md) — a runnable program, five minutes.
- [Introduction to optics](docs/introduction-to-optics.md) — what optics are and why.
- [Benchmarks](docs/benchmarks.md) — recorded numbers for fused vs unfused chains, and how to reproduce them.
- Examples — [lenses](docs/examples/lenses.md), [prisms](docs/examples/prisms.md), [chains](docs/examples/chains.md), [deriving](docs/examples/deriving.md), [user optics](docs/examples/user-optics.md).
- API reference — [first-class optics](docs/api/first-class.md) (with the per-kind laws), [composition](docs/api/composition.md), [the `@Lucida` DSL](docs/api/dsl.md), [diagnostics](docs/api/diagnostics.md), [internals & reserved names](docs/api/internals.md).
- Architecture & research — [the macro system](docs/architecture/macro-system.md), [registry plumbing](docs/architecture/registry-plumbing.md), [the fusion walk](docs/architecture/fusion-walk.md), [design decisions](docs/architecture/design-decisions.md), [compiler notes](docs/compiler-issues.md).

## Stability

Public API: the five optic structs, `Either`, the DSL macros, and the
`lucida.stdlib` optics. Identifiers starting with `__` and the `Registry*`
structs are **reserved** — they are macro plumbing, not API, and may change
in any minor release ([internals](docs/api/internals.md)).

## Repository layout

```
src/                      lucida               — optics core + composition table + stdlib
src/macrodsl/             lucida.macrodsl      — compiler macros (@Lucida, @DeriveOptics, ...)
src/tests/                lucida.tests         — the law test suite
examples/                 optics_experiments   — runnable demo + benchmarks
scripts/check.sh          verification gate (build + law tests + examples + diagnostics)
scripts/bench.sh          benchmark runner (results: docs/benchmarks.md)
```

Imports: `import lucida.*` for the optics API, `import lucida.macrodsl.*`
for the macros, `import lucida.stdlib.*` for the standard optic library.
