# Optics (lucida)

An optics library for [Cangjie](https://cangjie-lang.cn): lenses, prisms,
affines, isos and setters with a `@Lucida` update DSL, a `@DeriveOptics` code
generator, and a generated composition table.

```cangjie
let raised = @Lucida(arr?.selectFirst({ e: Employee2 => e.name == "dup" }).salary <- 999)
```

Updates are **immutable** — they return a new value; the original is never
mutated.

## Documentation

- Getting started — [docs/getting-started.md](docs/getting-started.md)
- Introduction to optics — [docs/introduction-to-optics.md](docs/introduction-to-optics.md)
- Examples — [docs/examples/lenses.md](docs/examples/lenses.md), [docs/examples/prisms.md](docs/examples/prisms.md), [docs/examples/chains.md](docs/examples/chains.md), [docs/examples/deriving.md](docs/examples/deriving.md), [docs/examples/user-optics.md](docs/examples/user-optics.md)
- API reference — [docs/api/first-class.md](docs/api/first-class.md), [docs/api/composition.md](docs/api/composition.md), [docs/api/dsl.md](docs/api/dsl.md), [docs/api/diagnostics.md](docs/api/diagnostics.md)
- Architecture & research — [docs/architecture/macro-system.md](docs/architecture/macro-system.md), [docs/architecture/registry-plumbing.md](docs/architecture/registry-plumbing.md), [docs/architecture/fusion-walk.md](docs/architecture/fusion-walk.md), [docs/architecture/design-decisions.md](docs/architecture/design-decisions.md)

## Repository layout

```
libs/optics/              lucida        — optics core + composition table + stdlib
libs/macro-optics/        lucida_macro  — compiler macros (@Lucida, @DeriveOptics, ...)
libs/macro-test-utils/                  — macro authoring helpers
src/                      optics_experiments — benches + the law test suite
scripts/check.sh          verification gate (build + tests)
docs/superpowers/         design specs & implementation plans
```

## Toolchain

Requires the Cangjie SDK (developed against `1.2.0-alpha`) plus stdx.

```bash
source ~/cangjie-sdk/cangjie/envsetup.sh
export CANGJIE_STDX_PATH=/absolute/path/to/linux_x86_64_cjnative/dynamic/stdx
./scripts/check.sh     # cjpm build -i && cjpm test && diagnostics-check; non-zero exit on failure
```

Gotchas learned the hard way:

- `CANGJIE_STDX_PATH` must be an **absolute path** (`~` is not expanded) and
  must point *into* the `stdx` directory — cjpm's scan of `path-option`
  entries is not recursive.
- Running `bin/main` needs `LD_LIBRARY_PATH=target/release/lucida` so the
  macro plugin / runtime libraries resolve.
- Macro packages compile to plugins under `target/release/lucida_macro`;
  after editing any `lucida_macro` source, rebuild before expecting new
  expansions elsewhere.
