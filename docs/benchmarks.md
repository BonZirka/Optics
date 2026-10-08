# Benchmarks

This page records measurements of the repository's benchmark suites under
the conditions below. They describe the measured operations and environment.

The main comparison is between handwritten reconstruction, fused `@f`, and
`@f[unfuse]`. In-place mutation is included in some handwritten suites, but
it provides a different behavior: it does not retain the original value.

## Recorded environment

The previous measurement record specifies:

- Main measurements: 2026-10-03, Darwin 25.5.0, Apple M5 Max, 18 cores.
- Compiler: Cangjie 1.0.0, cjnative, aarch64-apple-darwin.
- Optimization: `-O2`, static library build.
- Runtime: `cjHeapSize=4GB`, `cjGCInterval=4294967296ns`.
- Aggregation: median of three runs unless a section says otherwise.

The macOS toolchain warned that configured LTO settings applied only to
Linux/OHOS, so the main tables were recorded without LTO. The generated
matrix was checked again on 2026-10-04 after moving to the test project.
The record reports agreement within 9%, and within 3% for cases above 2 ns,
without a change in ordering.

## Reproduction

Load the SDK environment, then run from the repository root:

```sh
./scripts/bench.sh
```

The script builds benchmark binaries in `examples` and `tests`, then runs the
handwritten suites and the generated shape suite. It supplies the heap and
GC interval above unless they are already set in the environment.

Repeat complete runs and retain the raw output. Record the compiler, machine,
build options, runtime settings, and source revision with any replacement
table. Run the equivalence and code generation checks before interpreting
performance changes.

## Garbage collection and variability

The earlier runs frequently reported that GC occurred during measurement
batches. The same case then had substantially different results between runs,
sometimes reversing which implementation appeared faster.

For `Width32Bench`, the historical investigation recorded 15 runs with the
default GC settings:

| | reconstruct | `@InlineOptics` | ratio |
|---|---|---|---|
| median | 21.92 ns | 20.90 ns | −4.7% |
| range | 12.92–24.27 (1.88x) | 13.12–23.57 (1.80x) | −41.7% .. +72.8% |

With the large heap, a separate 10-run experiment recorded:

| | reconstruct | `@InlineOptics` | ratio |
|---|---|---|---|
| median | 9.94 ns | 10.09 ns | +1.6% |
| range | 9.90–10.45 (1.06x) | 10.05–10.19 (1.01x) | −3.6% .. +2.4% |

The second experiment reported no GC warnings. It used the large heap before
the interval setting was corrected, so it isolates the heap change rather
than establishing the effect of both settings together.

`cjGCInterval` is a duration. The earlier value `512MB` was rejected by the
runtime; the benchmark continued with a default. Inspect startup messages
instead of assuming every supplied setting took effect.

These settings reduce collection during short timing batches. They do not
remove garbage-collection costs from a long-running application. Within-run
error bars also do not describe variability between separate runs.

## Two-level update

Source: [`examples/bench/general/bench.cj`](../examples/bench/general/bench.cj).
The operation changes one leaf in a two-level value.

| Case             | What it does                             | Median   | vs recon |
|------------------|------------------------------------------|----------|----------|
| nativeBaseline   | mutate fields in place                   | 0.611 ns | 0.99x    |
| reconstruction   | hand-written rebuild `A(B(x, "New"), y)` | 0.614 ns | 100%     |
| unfusedOptics    | `@f[unfuse](...)` (library composition)  | 1.318 ns | 2.15x    |
| opticsBaseline   | `@f(...)` (fused)                        | 1.344 ns | 2.19x    |

The recorded fused update is about 2.19 times the handwritten reconstruction,
a difference of roughly 0.73 ns. The absolute costs are small, so repeated
measurement and code inspection matter when interpreting changes here.
An earlier claim that all four implementations were within 1% is superseded
by this table.

## Ten-level update

Source: [`examples/bench/depth/depth.cj`](../examples/bench/depth/depth.cj).

| Case             | What it does                             | Median    | vs recon |
|------------------|------------------------------------------|-----------|----------|
| nativeBaseline   | mutate the leaf in place                 | 1.336 ns  | 0.06x    |
| reconstruction   | hand-written nested rebuild              | 21.17 ns  | 100%     |
| opticsBaseline   | `@f(...)` (fused)                        | 24.99 ns  | 1.18x    |
| unfusedOptics    | `@f[unfuse](...)` (library composition)  | 169.8 ns  | 8.02x    |

The fused update is about 18% slower than reconstruction and about 6.8 times
faster than the unfused path in this record. The earlier claim that the fused
update beat reconstruction is superseded.

The mutation row does not pay for retaining the original structure. The
elapsed times alone do not establish exact allocation counts or explain
every remaining call in the generated program.

## Generated depth and width shapes

[`gen_bench.py`](../scripts/gen_bench.py) generates the source shapes,
equivalence tests, and expected expressions. Depth shapes vary the length of
a nested path. Width shapes vary the number of fields retained while changing
one field. Times are in nanoseconds.

| Shape  | reconstruct | `@f` fused | `@f[unfuse]` | fused vs recon |
|--------|-------------|------------|--------------|----------------|
| Depth2 | 2.699  | 2.975  | 2.954   | +10.2% |
| Depth4 | 6.165  | 6.918  | 25.94   | +12.2% |
| Depth8 | 11.98  | 13.95  | 103.0   | +16.4% |
| Depth16| 23.72  | 29.95  | 344.4   | +26.3% |
| Width2 | 0.875  | 1.304  | 1.301   | +49.0% |
| Width4 | 1.327  | 1.668  | 1.677   | +25.7% |
| Width8 | 2.186  | 3.269  | 3.027   | +49.5% |
| Width16| 3.933  | 5.936  | 5.928   | +50.9% |
| Width32| 10.04  | 10.11  | 10.09   | +0.7%  |

Fused `@f` is 10–51% slower than reconstruction on eight of these nine shapes;
`Width32` is nearly tied. The unfused path grows substantially with depth.
These measurements do not identify a single cause for every gap.

## Cases, blocks, and conversions

| Shape         | reconstruct | `@f` fused | `@f[unfuse]` | fused vs recon |
|---------------|-------------|------------|--------------|----------------|
| Enum8         | 1.843  | 5.283  | 60.38   | +186.7% |
| BlockDepth8   | 12.04  | 12.58  | 13.14   | +4.5%   |
| BlockWidth8   | 2.026  | 5.422  | 5.459   | +167.6% |
| Iso8          | 8.976  | 10.30  | 88.21   | +14.8%  |
| Option8       | 12.79  | —      | —       | n/a     |
| PrismBlock    | 0.983  | 2.225  | 2.227   | +126.3% |

- `Enum8` updates through an enum case. A direct reconstruction can express
  the case test and rebuild in a small match expression.
- `BlockDepth8` shares a long anchor before updating two fields.
- `BlockWidth8` updates eight fields. Its direct reconstruction uses one
  constructor call; the production block emitter applies entry operations.
- `Iso8` includes a one-field wrapper conversion.
- `PrismBlock` updates fields in a case payload, with the block directly
  anchored on that partial case.
- `Option8` uses the harness's optional-field handling. There is no built-in
  `@f` path for that form, so the missing cells are unsupported comparisons,
  not zero cost.

The direct-expansion harness is not another timed column. The code generation
check compares its normalized output with the handwritten reconstruction.
See [the harness](architecture/inline-harness.md) for what that comparison
covers.

## Reads

The generated matrix includes 15 read expressions and their equivalence
checks. The current tables do not time those reads. Value equivalence and
expression agreement therefore provide evidence about behavior, not read
performance.

Earlier exploratory read timings were sensitive to hoisting, representation,
and whether the input changed inside the timing loop.

## Historical LTO experiment

The following Linux results predate the GC corrections. They are retained as
a record of the experiment and are not reliable estimates of the current
benefit from LTO. Units are nanoseconds.

| Build                | native | fused `@f` | hand rebuild | unfused |
|----------------------|--------|-----------------|--------------|---------|
| static, no LTO       | 2.3    | 52.5            | 58.4         | 343     |
| static + thin LTO    | 2.1    | 48.9            | 55.1         | 322     |
| static + full LTO    | 2.0    | 48.6            | 55.5         | 323     |

## Serialization adapter experiment

Source: [`salary_bump.cj`](../examples/bench/examples/salary_bump.cj).
The record contains a handwritten decode/rebuild/encode baseline of 406.9 ns.
It does not contain an implemented matching optic benchmark case, so it
cannot establish the cost of expressing that operation with optics.

## Interpreting a change

First establish that the implementations perform the same update, including
misses and preservation of unrelated fields. Then compare repeated runs under
the same conditions. For a small timing difference, inspect emitted code and
between-run variability before attributing it to an optimization.

The measured fused paths retain overhead relative to handwritten reconstruction
in most recorded cases.
