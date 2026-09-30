#!/bin/bash
# Assert that @InlineOptics expands to exactly the program reconstruct spells out.
#
# The harness exists to compile the optics DSL away, so for every generated
# shape its expansion has to *be* the hand-written rebuild -- same tokens, not
# merely the same runtime behaviour. That is checked here instead of being timed:
# `expected_expansions.txt` (written by scripts/gen_bench.py) holds one baseline
# expression per shape, the macro prints its expansion, and both sides are put
# through the same normalisation before diffing.
#
# Normalisation erases only what carries no meaning: whitespace, the fresh
# `__ioN` binders the emitter has to invent, and the benchmark's counter name.
# Anything else -- a missing comma, a redundant `match`, a differently spelled
# case pattern -- shows up as a diff.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${CANGJIE_HOME:?CANGJIE_HOME must point to the Cangjie toolchain directory (the one containing envsetup.sh)}"

manifest=tests/src/generated/expected_expansions.txt
if [[ ! -f $manifest ]]; then
    echo "check_codegen: missing $manifest -- run scripts/gen_bench.py" >&2
    exit 1
fi

normalize() {
    # One expression per line throughout, so a missing shape cannot hide inside a
    # neighbour. Erases exactly what carries no meaning -- the label, the fresh
    # `__ioN` binders the emitter must invent, the counter name, and all
    # whitespace. Anything else (a missing comma, a redundant `match`, a
    # differently spelled case pattern) survives as a diff.
    sed -E -e 's/^[^\t]*\t//' \
        -e 's/__io[0-9][0-9]*/B/g' \
        -e 's/tick_[a-z0-9]*/C/g' \
        -e 's/probe/C/g' \
        -e 's/(^|[ (,=>])_([ ),=]|$)/\1B\2/g' \
        -e 's/[[:space:]]//g'
}

work=$(mktemp -d)
harness_tests=tests/src/inline_optics.cj
restore() {
    if [[ -f $work/inline_optics.cj ]]; then
        mv "$work/inline_optics.cj" "$harness_tests"
    fi
    rm -rf "$work"
}
trap restore EXIT

cut -f2- "$manifest" | normalize | sort > "$work/expected"

# The dump holds whatever this build expanded, and expansion is cached: touch a
# file and its macro calls re-run and re-print, leave it alone and they print
# nothing. Building the whole test project would therefore mix the corpus with
# whatever else happened to recompile — the harness's own unit tests, whose
# expansions are not in the manifest and are not this gate's business. So the
# corpus is expanded on its own: the unit-test file steps out of the package for
# the length of the build, which makes the dump exactly the corpus on every run
# instead of only on a warm cache. (Killed hard? `git checkout
# tests/src/inline_optics.cj` puts it back.)
mv "$harness_tests" "$work/inline_optics.cj"
touch tests/src/generated/*.cj
( cd tests && LUCIDA_DUMP_INLINE=1 cjpm build -i --rel ) > "$work/build.log" 2>&1
build_status=$?
mv "$work/inline_optics.cj" "$harness_tests"
if [[ $build_status -ne 0 ]]; then
    sed -n '1,40p' "$work/build.log" >&2
    echo "check_codegen: tests build failed" >&2
    exit 1
fi

grep '^@EXPAND: ' "$work/build.log" | sed 's/^@EXPAND: //' | normalize | sort > "$work/actual"

expected_count=$(wc -l < "$work/expected" | tr -d ' ')
actual_count=$(wc -l < "$work/actual" | tr -d ' ')
if [[ $expected_count -ne $actual_count ]]; then
    echo "check_codegen: expected $expected_count expansions, macro emitted $actual_count" >&2
    exit 1
fi

if ! diff -u "$work/expected" "$work/actual" > "$work/diff"; then
    echo "check_codegen: @InlineOptics does not expand to the hand-written rebuild" >&2
    sed -n '1,40p' "$work/diff" >&2
    exit 1
fi

echo "check_codegen: $actual_count shapes expand exactly to reconstruct"