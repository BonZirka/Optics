# Benchmarks

Recorded results for the benchmark suite: the hand-written cases in
`examples/bench`, and the generated shape matrix in `tests/src/generated/`.
Reproduce with:

```bash
CANGJIE_HOME=/path/to/cangjie ./scripts/bench.sh
```

Each bench class compares the same update written several ways. The comparison
this file exists to track is **reconstruction against fused `@f`**: the goal is
for the reconstruction to be as fast as fused. A hand-written *direct* form is
reported only where it is itself a reconstruction; it is never the headline,
because a direct form always wins and always will.

## Environment

- 2026-10-03, Darwin 25.5.0 (Apple M5 Max, 18 cores), release build (`-O2`)
- Cangjie Compiler 1.0.0 (cjnative), aarch64-apple-darwin
- `cjHeapSize=4GB cjGCInterval=4294967296ns` — see [measurement hygiene](#measurement-hygiene), this is not optional. Note the units: the interval is a *duration*, and the runtime rejects a byte count (`512MB`) with `Unsupported cjGCInterval parameter`, then runs with its default anyway — a knob that fails silently and still produces numbers
- `lucida` ships as a static library; `[profile.build.lto] level = "thin"` is
  configured but the toolchain warns LTO settings only apply to Linux/OHOS, so
  these numbers are **without** LTO

Numbers are medians of 3 runs. With the heap setting above, run-to-run spread on
the generated matrix measures 1.075x median, 1.358x worst case (Depth16
reconstruct) over 3 runs; without it, spread reaches 1.9x and rankings flip.

> **The numbers in this file were re-measured on 2026-10-03.** Every table below
> previously carried GC-contaminated medians — see
> [measurement hygiene](#measurement-hygiene). Several conclusions changed, and
> two claims this file used to make are now marked as withdrawn.
>
> **The generated matrix was re-measured on 2026-10-04**, after it moved from
> `examples/bench/generated/` to `tests/src/generated/` with the harness that
> measures it (see [the harness](architecture/inline-harness.md)). Medians of 3
> runs agree with the table below to within 9%, and within 3% for every case
> above 2 ns; the largest gap is `PrismBlock` reconstruct at 0.983 → 1.069 ns,
> a sub-2 ns case where a different binary's code layout is the likely cause.
> No ordering changes, so the tables are left as recorded rather than rewritten
> from a noisier configuration.

## Measurement hygiene

The single most important thing about benchmarking here: **keep GC out of the
measurement batches.** The suite allocates in a tight loop, and with default
settings the harness prints

```
Warning: GC was invoked twice during some of the batches. This can significantly
affect final results.
```

on *every* case — which was the default behaviour, not a misconfiguration.

The effect is not a small additive cost. It is a ~2x multiplier that lands in a
*different case on each run*, so it randomises the ranking rather than shifting it
uniformly. Measured on `Width32Bench`, 15 consecutive runs with default GC:

| | reconstruct | `@InlineOptics` | ratio |
|---|---|---|---|
| median | 21.92 ns | 20.90 ns | −4.7% |
| range | 12.92–24.27 (1.88x) | 13.12–23.57 (1.80x) | −41.7% .. +72.8% |

Values were strongly **bimodal**, clustering near 10 ns or near 22 ns and
flipping between cases *within a single run* — reconstruct at 14.74 ns while
`@InlineOptics` measured 23.57 ns in the same process. Taken as "the inlined
form is 40% faster on wide shapes", which is what an earlier draft of this file
concluded. It was an artifact.

With `cjHeapSize=4GB` (now the default in `scripts/bench.sh`), same case, 10
runs. The `cjGCInterval` written as `512MB` in an earlier draft of this file was
rejected by the runtime — it wants a duration — so this row is the large heap
alone, and it is the heap that did the work:

| | reconstruct | `@InlineOptics` | ratio |
|---|---|---|---|
| median | 9.94 ns | 10.09 ns | +1.6% |
| range | 9.90–10.45 (1.06x) | 10.05–10.19 (1.01x) | −3.6% .. +2.4% |

GC warnings: 0/10. Absolute cost dropped ~2.2x, spread collapsed from 1.88x to
1.06x, and the ratio settled at the value the identical expansion predicts.

Two things follow, and both were learned the hard way:

- **A within-run error bar is not a reproducibility claim.** The ±3–5% bars the
  harness prints describe precision inside one run. Between-run spread was
  reaching 2x. Never quote a single run.
- **Sanity-check the magnitude against the source.** Two of these cases expand to
  *character-identical* constructor calls, so no measured difference between them
  can be real. When the numbers disagreed, the numbers were wrong.

## `bench/general` — 2-level chain (`A(B(x, y), y)`, one leaf update)

Baseline: `nativeBaseline` (direct field mutation).

| Case             | What it does                             | Median   | vs recon |
|------------------|------------------------------------------|----------|----------|
| nativeBaseline   | mutate fields in place                   | 0.611 ns | 0.99x    |
| reconstruction   | hand-written rebuild `A(B(x, "New"), y)` | 0.614 ns | 100%     |
| unfusedOptics    | `@f[unfuse](...)` (library composition)  | 1.318 ns | 2.15x    |
| opticsBaseline   | `@f(...)` (fused)                        | 1.344 ns | 2.19x    |

> **Withdrawn:** this section previously reported all four within 1% and
> concluded "all four spellings compile to the same code at this depth". Under
> clean measurement fused `@f` is **2.2x** the hand-written rebuild.

The chain is trivial enough that the fused path's fixed cost is the whole
measurement: ~0.7 ns of overhead on a 0.6 ns rebuild. Fused and unfused are
indistinguishable here (0.98x) — with two segments there is nothing for fusion to
save, and composition is not yet expensive.

## `bench/depth` — 10-level chain (`Struct_1` … `Struct_10`, one leaf update)

Baseline: `reconstruction` (hand-written 10-level rebuild).

| Case             | What it does                             | Median    | vs recon |
|------------------|------------------------------------------|-----------|----------|
| nativeBaseline   | mutate the leaf in place                 | 1.336 ns  | 0.06x    |
| reconstruction   | hand-written nested rebuild              | 21.17 ns  | 100%     |
| opticsBaseline   | `@f(...)` (fused)                        | 24.99 ns  | 1.18x    |
| unfusedOptics    | `@f[unfuse](...)` (library composition)  | 169.8 ns  | 8.02x    |

> **Withdrawn:** this section previously reported fused `@f` at 48.58 ns
> *beating* the hand-written rebuild (53.29 ns) by 8.9%. Fused is actually 18%
> *slower* than the rebuild.

The immutable-update cost itself dominates both: 10 allocations, ~16x the cost
of in-place mutation, which is only available when you do not need the original.

**Fusion vs unfusion is real and survives clean measurement**: 6.79x here, and
14.6x at depth 16 in the generated matrix below. Composition allocates an optic
per segment, and the cost grows with depth. This is the one long-standing claim
in this file that the re-measurement confirmed.

## `tests/src/generated` — shape matrix, DSL vs hand-written

Generated by `scripts/gen_bench.py` into the test project, next to the harness
it measures: one object shape per file, three timed ways
to perform the identical minimal update (write a single leaf), plus a test
asserting the direct chain, the `@f` expansion and the hand-written rebuild all
produce the same value. Every shape's read is generated and pinned by the codegen
gate, and none of them is timed — see
[reads](#reads-checked-not-timed).

[`@InlineOptics`](architecture/inline-harness.md) is deliberately *not* a column
here. It expands to this very hand-written rebuild — `scripts/check_codegen.sh`
diffs its output against `expected_expansions.txt` token for token — so a fourth
column would have measured the noise floor. The harness is the baseline's
mechanism, not a competitor to it. Baseline: `reconstruct`. Medians of 3 runs, ns:

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

Two things this table shows:

**1. Fused `@f` carries real per-chain overhead.** 10–51% slower than the
hand-written rebuild on eight of nine shapes. The fused expansion
reads untouched siblings through the generic accessor path; a direct rebuild
reads the fields the optimizer folds into the allocation. This is consistent
with `bench/general`, where fused `@f` is 2.2x the rebuild.

**2. Unfused composition is the expensive path, and it scales with depth.**
2.95 → 344 ns from depth 2 to depth 16 (117x), against 8.8x for the rebuild over
the same range. On width shapes unfused and fused are indistinguishable — the
cost is per *segment*, and a width shape is one segment.

`Width32` is a tie across all three (+0.7%). It is also the case that exposed
the GC problem, allocating 272-byte objects hard enough to trigger collection;
with GC excluded it is simply a shape wide enough that the rebuild cost
dominates the accessor overhead.

### Complex shapes — prisms, partials, blocks, coercions

The depth and width families are total lenses, which is the easy case: no segment
can fail, and every rebuild is a straight nest of constructor calls. The families
below add something the fused path has to do *work* for. Medians, ns:

| Shape         | reconstruct | `@f` fused | `@f[unfuse]` | fused vs recon |
|---------------|-------------|------------|--------------|----------------|
| Enum8         | 1.843  | 5.283  | 60.38   | +186.7% |
| BlockDepth8   | 12.04  | 12.58  | 13.14   | +4.5%   |
| BlockWidth8   | 2.026  | 5.422  | 5.459   | +167.6% |
| Iso8          | 8.976  | 10.30  | 88.21   | +14.8%  |
| Option8       | 12.79  | —      | —       | n/a     |
| PrismBlock    | 0.983  | 2.225  | 2.227   | +126.3% |

- **Enum8** writes through an enum case (`v.x…x?.Held <- tick`). The `match` is
  hoisted over the whole chain, so a miss returns the source without allocating.
  Fused `@f` is 187% over the hand-written `match` because its miss path still
  runs the generic accessor chain.
- **BlockWidth8** writes all eight fields through one sibling block. Fused `@f`
  pays 168%: the block's per-entry work goes through the registry. Direct, the
  block is one constructor call — and the harness now emits exactly that, which
  the codegen gate pins.
- **BlockDepth8** is the shape where fusion costs least (+4.5%): two entries and a
  shared prefix make the accessor work a small fraction of a depth-7 rebuild.
- **PrismBlock** writes both fields of a case payload through a sibling block
  anchored on the case (`v?.Held.{ .a; .b }`). The direct form is a single
  `match` whose hit arm is one constructor call — the guard decides once, and the
  block rebuild happens inside it — which is why reconstruction is 2.3x faster
  than fused `@f` here, the widest gap of any shape with a hand-written baseline
  this small.
- **Iso8** is a chain of one-field structs ending in `coerce<Int64>()`. The
  direct form of that segment is a field read and a one-argument constructor —
  nothing at all — while fused `@f` builds the iso's forward and backward
  function values and calls them. That is the whole +15%: a fixed ~1.3 ns of iso
  plumbing per update, on a shape whose rebuild is 9.0 ns.
- **Option8** updates through an `Option`-typed field (`v.x…x?.a <- tick`).
  `@f` has no syntax for this — a derived lens is total, so `?.` through an
  `Option`-returning lens is rejected — so it has no DSL column at all.

`Option8` is the clearest argument for the harness existing: it is not a faster
version of `@f`, it is the only one of the two that can express the update. It
still has a role in the timed matrix as a guard: `@InlineOptics` has to expand to
the same `match` (codegen gate) and produce the same value (equivalence test),
so a future DSL that grows this syntax starts from a known-good baseline.

### Reads: checked, not timed

Every shape also generates its **read** half — `@f(path)` with no arrow, plus the
hand-written form it must expand to — and those are in the codegen gate (30
expansions: 15 writes, 15 reads) and in 15 equivalence tests.

They are deliberately **not** timed, and the reason is the point of the whole
suite. The number being tracked here is reconstruction against fused `@f`: how
close the DSL gets to the form the optimizer would have produced. A read has no
reconstruction to compare against — the hand-written form of `@f(path)` is a
bare field read — so timing it against fused `@f` would be reporting "a pointer
chase versus the DSL". That comparison is not wrong, but it is unwinnable and
therefore useless: there is no gap for the harness to close. The read forms are
held to the two checks that can actually fail, that the expansion *is* the
hand-written form and that both sides return the same value.

The per-segment cost that reads do have is real and worth knowing about, so it is
recorded here rather than benchmarked. Fused reads are not flat in chain length:
8.2 ns at two segments, 28.2 ns at eight, 128.7 ns at sixteen, against 0.13–0.19
ns for the equivalent hand-written read. The receivers matter too, because a
successful `@f` read copies every intermediate value it passes through — the
same three-segment chain measures 11.52 ns fused over classes and 19.45 ns over
structs, while the hand-written read moves only 0.14 → 0.20 ns, because the
optimiser elides copies it can see through a plain field access but not copies
buried in generic forward functions.

None of that is a reconstruction gap, so it does not belong in a table whose
purpose is to track one. It belongs in the note above, and if a future version of
`@f` wants to close it, the honest benchmark for that work is a read whose
direct form is itself a reconstruction — which no read in this DSL has.

## Why LTO matters

> **Stale — needs re-measurement.** The figures below predate the GC fix and were
> taken on Linux, where the configured thin LTO does apply. The qualitative claim
> (fused chains are allocation- and call-bound, so cross-module optimisation
> helps) is consistent with the clean results above, but the magnitudes here are
> GC-contaminated and the comparison has not been repeated with LTO on and off.

`lucida` used to ship as a dynamic library. Every per-segment phantom registry
construction was then a cross-DSO call that could not inline: the fused
10-level update carried 20 `Registry*<init>` calls that do nothing but were not
free. Shipping static + `@Frozen` on the registry inits removed most of it; LTO
removes the rest and lets the optimizer see the whole chain.

Depth-suite medians, 3 runs per configuration (ns):

| Build                | native | fused `@f` | hand rebuild | unfused |
|----------------------|--------|-----------------|--------------|---------|
| static, no LTO       | 2.3    | 52.5            | 58.4         | 343     |
| static + thin LTO    | 2.1    | 48.9            | 55.1         | 322     |
| static + full LTO    | 2.0    | 48.6            | 55.5         | 323     |

Thin and full LTO are equivalent within noise; thin links faster, so it is
the shipping default.

## `bench/examples` — update through serialization adapters

`BenchBumpEncoded`: the value lives in an encoded `Wire` (a small
hand-rolled format, declared in the benchmark file — the point is that the
update crosses an encode/decode boundary, not how the boundary is built);
the baseline decodes, rebuilds, and re-encodes by hand, the optic case
expresses the same update as a `@f[unfuse]` chain over the `serialization<T>()`
adapter.

The adapter is declared by hand as a first-class optic rather than an `@Optic`
carrier, which is what keeps the chain on the library-composition path.

**One number only.** The hand-written baseline measures 406.9 ns. There is no
second case to compare it against — the adapter case is not implemented as a
benchmark, so this section still does not support the comparison it was written
for. What a working pair should confirm is the shape rather than the magnitude:
the adapter path should cost more than the hand-written rebuild, dominated by
(de)serialization rather than by the chain.

The chain is deliberately unfused — user-declared adapter optics like this are
exactly what the library-composition fallback exists for. A
`lucida.stdx` package declaring this carrier (and the `ArrayList`/`Option`
segments) is [future work](architecture/design-decisions.md#open-problems);
until then the benchmark keeps its own copy, which is also why it needs no
dependency beyond the standard library.

## Reading the numbers

- **Measure before believing.** Every conclusion in this file was wrong before
  the GC settings were fixed, including two that had been published across
  several revisions. The tell was a claimed effect between two cases that emit
  identical code.
- **`@InlineOptics` is free.** It is the hand-written rebuild, because that is
  what it emits. Use it when you want the DSL at the call site and constructor
  calls in the binary.
- **Fused `@f` is not free.** 1.2x the rebuild at depth 10, 2.2x at depth 2,
  and 1.2–1.5x across the generated depth shapes. The gap is fixed per-chain
  accessor overhead, so it hurts most when the chain is short.
- **Unfused is the expensive path**: 6.8x fused at depth 10, 14.6x at depth 16,
  growing with segment count. Width shapes are unaffected — one segment, nothing
  to compose.
- **The remaining gap to in-place mutation is the immutable update itself.**
  ~16x at depth 10 in both the hand-written and inlined forms, which is 10
  allocations either way.
- Chains with more than 16 Option-producing segments fall back to the unfused
  (library composition) path — the pinned walkers are generated up to
  `pinPrismForward16` (see [the fusion walk](architecture/fusion-walk.md) for
  the family and how to raise the cap).