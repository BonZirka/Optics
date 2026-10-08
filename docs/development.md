# Development

The repository is a `cjpm` workspace. Application consumers depend on its
library members rather than on the test project.

| Directory | Package or role |
|---|---|
| `core/src` | `lucida`: optic types, dispatch helpers, generated composition and tuple support |
| `core/src/macrodsl` | `lucida.macrodsl`: declaration and expression macros |
| `stdlib/src` | `lucida_stdlib`: standard array optics |
| `tests/src` | Laws and feature regressions |
| `tests/src/inline` | `tests.inline`: direct-expansion benchmark harness |
| `tests/src/generated` | Generated shapes, equivalence checks, and benchmarks |
| `examples` | Separate consumer project and handwritten benchmarks |
| `scripts` | Verification, code generation, and benchmark commands |

## Toolchain setup

Load the installed Cangjie SDK environment before building:

```sh
source /path/to/cangjie/envsetup.sh
cjc -v
```

The scripts require `CANGJIE_HOME` to name the SDK directory. Sourcing its
setup script should also make `cjpm` available and configure runtime paths.
Setting `CANGJIE_HOME` alone is not a substitute for loading that environment.

The repository manifests currently record `cjc-version = "0.57.3"`.
The full gate was also run successfully with Cangjie 1.0.0 on macOS arm64;
older compiler investigations used Linux alpha builds named in
[compiler notes](compiler-issues.md). These observations are not a complete
support matrix. Record the exact compiler when reporting a failure.

## Verification

From the repository root:

```sh
./scripts/check.sh
```

The script performs these checks in order:

1. Build the workspace with the `rel` custom option (`-O2`).
2. Run the law and feature suite.
3. Build the separate example consumer.
4. Compare the direct-expansion harness output with the expected expressions.
5. Compile invalid examples and inspect their diagnostics.

The current suite contains 281 test cases, 30 expected harness expansions,
and 34 diagnostic probes. These counts describe this revision; the script's
result is the relevant check after further changes.

The Cangjie test runner uses a local socket. A sandbox that prohibits binding
a socket can prevent the runner from starting even after compilation succeeds.
Use an environment that permits that local test transport.

To save the output:

```sh
./scripts/check.sh > check.log 2>&1
```

Keep the exit status as well as the log. Diagnostic probes currently match
message text without asserting a nonzero compiler status.

## Build one part

Run `cjpm build -i --rel` inside `core`, `stdlib`, or `examples` to build that
project. Run `cjpm test` inside `tests` for the suite without selecting the
workspace's `rel` custom option.

When changing macro code, an affected consumer may retain stale macro build
products. Use the SDK's `cjpm clean` command in the relevant library/workspace
and consumer projects, then rebuild. Save logs before cleaning when
investigating a compiler crash.

The code generation check temporarily moves `tests/src/inline_optics.cj`
out of the package and restores it with an exit trap. Do not run it
concurrently with edits or builds of that package. The diagnostic check also
creates a temporary source in `tests/src`.

## Benchmarks and generated sources

```sh
python3 scripts/gen_bench.py
./scripts/check_codegen.sh
./scripts/bench.sh
```

The generator updates the shape corpus and expected expansions. Review those
changes together. The code generation check establishes expression agreement;
the benchmarks measure execution time. One does not replace the other.

Keep the runtime heap settings, compiler options, platform, and number of
runs with every measurement. [Benchmarks](benchmarks.md) explains the recorded
settings and known limitations.

## Changing documentation

Write for a Cangjie programmer learning optics. Introduce a term through its
operation or an example before using it as shorthand. State what the code
does and the conditions under which the statement holds.

Keep the learning sequence, API reference, and implementation explanation
consistent. Application examples should use supported names. Label
pseudocode and include the declarations needed to understand a snippet.

The [API index](api/index.md) covers `lucida` and `lucida.macrodsl`, grouping
declarations into `structs/`, `macros/`, and `slots/`. Give each core application
item its own page with a package and source link, declaration or syntax, member or input
table, semantics, example, and related items. Struct pages own their laws.
Keep shared macro attributes on `@Optic` and link the kind aliases to them.
Add new items to the index.

Use `examples/` for guided tasks and `architecture/` for implementation
explanations. Diagnostics belong in [the troubleshooting page](diagnostics.md).
Link to the canonical reference for a rule instead of maintaining a second
API description in a tutorial.

For a documentation change, check local links and compile affected executable
examples. The complete manifest and program in [Getting started](getting-started.md)
provide a consumer smoke test. Do not present a benchmark number as freshly
measured when only the prose has changed.

When documenting a design choice, name the choice, explain its purpose, and
state a concrete cost or limitation. Document implemented behavior and
identify the environment and revision associated with recorded measurements.
