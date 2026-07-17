// Benchmarks for the lucida optics library.
//
// This file only anchors the `bench` package: cjpm skips a directory
// (and its subdirectories) that contains no `.cj` file of its own, so
// without it the per-directory benchmark packages below would be
// silently excluded from the build. Each subdirectory is its own
// benchmark package (`bench.general`, `bench.depth`, ...).
package optics_experiments.bench
