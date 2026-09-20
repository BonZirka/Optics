# Benchmarks

Recorded results for the benchmark suite in `examples/bench`. Reproduce with:

```bash
CANGJIE_HOME=/path/to/cangjie ./scripts/bench.sh
```

Each bench class compares the same update written four ways; the `Ratio`
column is relative to the case named in `@Configure[baseline: ...]`.

## Environment

- 2026-09-25, Linux 7.0.0-29-generic
- 13th Gen Intel(R) Core(TM) i7-13700 (24 CPUs), release build (`-O2`)
- Cangjie Compiler 1.2.0-alpha.20260710020028 (cjnative)
- `lucida` ships as a static library built with thin LTO
  (`[profile.build.lto] level = "thin"`)

Numbers below are medians of multiple runs; single-run comparisons proved
unreliable (see the LTO table — run-to-run and build-to-build layout noise is
±10%, enough to flip a ranking).

## Why LTO matters

`lucida` used to ship as a dynamic library. Every per-segment phantom
registry construction was then a cross-DSO call that could not inline: the
fused 10-level update carried 20 `Registry*<init>` calls that do nothing but
were not free. Shipping static + `@Frozen` on the registry inits removed
most of it; LTO removes the rest and lets the optimizer see the whole chain.

Depth-suite medians, 3 runs per configuration (ns):

| Build                | native | fused `@f` | hand rebuild | unfused |
|----------------------|--------|-----------------|--------------|---------|
| static, no LTO       | 2.3    | 52.5            | 58.4         | 343     |
| static + thin LTO    | 2.1    | 48.9            | 55.1         | 322     |
| static + full LTO    | 2.0    | 48.6            | 55.5         | 323     |

Thin and full LTO are equivalent within noise; thin links faster, so it is
the shipping default. Full LTO does **not** regress the hand-written
baseline — earlier single-run readings suggesting that were noise.

## `bench/general` — 2-level chain (`A(B(x, y), y)`, one leaf update)

Baseline: `nativeBaseline` (direct field mutation).

| Case             | What it does                                   | Median    | Ratio    |
|------------------|------------------------------------------------|-----------|----------|
| nativeBaseline   | mutate fields in place                         | 0.824 ns  | 100%     |
| opticsBaseline   | `@f(bow.x.y <- "New")` (fused)            | 0.822 ns  | 100%     |
| unfusedOptics    | `@f[unfuse](...)` (library composition)   | 0.825 ns  | 100%     |
| reconstruction   | hand-written rebuild `A(B(x, "New"), y)`       | 0.797 ns  | -3%      |

With LTO, all four spellings of the update flatten to the same code at this
depth: the DSL — fused or unfused — costs nothing over a hand-written
mutation.

## `bench/depth` — 10-level chain (`Struct_1` … `Struct_10`, one leaf update)

Baseline: `reconstruction` (hand-written 10-level rebuild).

| Case             | What it does                                   | Median    | Ratio    |
|------------------|------------------------------------------------|-----------|----------|
| reconstruction   | hand-written nested rebuild                    | 53.29 ns  | 100%     |
| nativeBaseline   | mutate the leaf in place                       | 2.079 ns  | -96.1%   |
| opticsBaseline   | `@f(...)` (fused)                         | 48.58 ns  | -8.9%    |
| unfusedOptics    | `@f[unfuse](...)` (library composition)   | 325.9 ns  | +511%    |

The fused chain now **beats the hand-written rebuild** (the optimizer folds
the emission into the same constructor chain, minus the human's redundant
re-reads) and is **6.7× faster than library composition**. The remaining gap
to in-place mutation is the immutable-update cost itself: 10 allocations.

## `bench/examples` — update through serialization adapters

`BenchBumpEncoded`: the value lives in an encoded `Wire` (a small
hand-rolled format, declared in the benchmark file — the point is that the
update crosses an encode/decode boundary, not how the boundary is built);
the baseline decodes, rebuilds, and re-encodes by hand, the optic case
expresses the same update as a `@f[unfuse]` chain over the `serialization<T>()`
adapter.

The adapter is declared by hand as a first-class optic rather than an `@Optic`
carrier, which is what keeps the chain on the library-composition path.

**No numbers recorded yet.** The format changed when stdx was dropped, so
the previous medians and ratio are gone rather than marked stale — a
different implementation has a different cost and the old figures are not
comparable. Re-measure on the [environment](#environment) above before
quoting anything. What the earlier run established, and what a re-run
should confirm, is the shape rather than the magnitude: the adapter path
costs more than the hand-written rebuild, and the cost is dominated by
(de)serialization rather than by the chain.

The chain is deliberately unfused — user-declared adapter optics like this are
exactly what the library-composition fallback exists for. A
`lucida.stdx` package declaring this carrier (and the `ArrayList`/`Option`
segments) is [future work](architecture/design-decisions.md#open-problems);
until then the benchmark keeps its own copy, which is also why it needs no
dependency beyond the standard library.

## Reading the numbers

- **Shallow chains are free**: at depth 2 every spelling of the update
  compiles to identical code under LTO.
- **Fusion vs unfusion is the headline at depth**: 6.7× at depth 10. The gap
  widens with chain depth because unfused composition allocates an optic per
  segment while the fused walk emits direct nested calls.
- **The fused path is not slower than the code you would have written**:
  48.6 ns vs 53.3 ns hand rebuild at depth 10 — immutable updates cost 10
  allocations either way; native in-place mutation (2 ns) is only available
  when you do not need the original.
- Chains with more than 16 Option-producing segments fall back to the unfused
  (library composition) path — the pinned walkers are generated up to
  `pinPrismForward16` (see [the fusion walk](architecture/fusion-walk.md) for
  the family and how to raise the cap).
