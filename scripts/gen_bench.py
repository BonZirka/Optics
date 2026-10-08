#!/usr/bin/env python3
"""Generate the "minimal update" benchmark: constructor rebuild vs optics syntax.

For each generated object shape the generator emits three benchmark methods that
all perform the *same* semantic update -- write one leaf of a freshly built
value -- so the only difference between them is how the update is expressed:

  reconstruct    hand-rolled: nest constructor calls, referencing every
                 unchanged value (the baseline)
  optics         the optics DSL, fused: `@f(v.x.x...y <- n)`
  opticsUnfused  the optics DSL, unfused: `@f[unfuse](v.x.x...y <- n)`

`@InlineOptics` gets no timing row of its own. It translates to *these* very
constructor calls, so timing it against `reconstruct` measures the noise floor
rather than a design choice. Instead each shape gets an equivalence test
asserting that the inlined chain and the hand-written rebuild produce exactly
the same value, and `expected_expansions.txt` records the expansion the harness
is required to emit; `scripts/check_codegen.sh` diffs the two, so "the harness
compiles the DSL to the same program `reconstruct` spells out" is checked
exactly rather than timed.

Deliberately excluded: first-class optics in the benchmark bodies. No `@use`, no
`Lens<S, F>` bindings, no `@typeof(x).field` minting. First-class optics cost
several times a direct member call, which would drown out the comparison this
benchmark exists to make. (The inlining-metadata machinery still understands
first-class optics; `tests/src/inline_optics.cj` covers that.)

Shapes come in six families, because the costs they isolate are different:

  depth      a single chain of nested structs. Every slot of the path must be
             rebuilt, so this measures per-slot DSL overhead.
  width      one struct with many sibling fields. One slot, but a wide
             rebuild, so this measures the cost of breadth in the constructor
             path.
  enum       a chain ending in an enum, updated through one of its cases. A
             partial slot, so the rebuild also has a miss arm.
  option     a chain ending in an `Option`-typed field, updated through its
             payload. `@f` cannot express this shape at all -- a derived lens
             is total, so `?.` through it is rejected -- so this family
             benchmarks the hand-written `match` against `@InlineOptics` only.
  blockDepth one struct whose two leaves are written at once, through a sibling
             block. Exercises the shared-prefix collapse.
  blockWidth a sibling block writing every field of a wide struct.
  iso       a chain of one-field structs updated through `coerce<T>()`. The
             direct expansion is a nest of one-argument constructors, so this
             measures the DSL's iso plumbing -- two function values and two
             indirect calls -- against a plain field read.

The new leaf value comes from a mutable counter rather than a literal. With a
literal the optimiser is free to hoist the entire reconstruction out of the
benchmark loop, which would measure nothing.

Usage:
    scripts/gen_bench.py [--out DIR] [--depth-list N,N,..] [--width-list N,N,..]
                         [--enum-list N,N,..] [--option-list N,N,..]
                         [--block-depth-list N,N,..] [--block-width-list N,N,..]
                         [--iso-list N,N,..]

Regenerating is not part of the gate: the emitted sources are committed, so
`scripts/bench.sh` and CI need no Python.
"""

from __future__ import annotations

import argparse
import re
import pathlib
import sys

# Kept modest on purpose. compiler-issues.md #1 records that compile time grows
# steeply with declaration arity, and every shape here declares a struct per
# nesting level, so a wide matrix is expensive to build for no extra signal.
DEFAULT_DEPTHS = [2, 4, 8, 16]
DEFAULT_WIDTHS = [2, 4, 8, 16, 32]
# One size each: these families are about the *kind* of chain, not about
# scaling it, and every extra file is another few seconds of build time.
DEFAULT_ENUMS = [8]
DEFAULT_OPTIONS = [8]
DEFAULT_BLOCK_DEPTHS = [8]
DEFAULT_BLOCK_WIDTHS = [8]
DEFAULT_ISOS = [8]


def emit_depth(n: int) -> str:
    """A chain of n nested structs; update the `y` of the innermost."""
    structs = [f"D{n}_S{i}" for i in range(1, n + 1)]
    root, tick = f"v_d{n}", f"tick_d{n}"

    shape = []
    for i, name in enumerate(structs):
        x_ty = "Int64" if i == n - 1 else structs[i + 1]
        shape.append((name, [("x", x_ty), ("y", "Int64")]))

    # Path from the root to the innermost struct is `.x` repeated n-1 times.
    x_path = ".x" * (n - 1)

    # rebuild: innermost first, then wrap outwards copying each level's `y`
    expr = f"{structs[-1]}({root}{x_path}.x, {tick})"
    for i in range(n - 2, -1, -1):
        outer_y = f"{root}{'.x' * i}.y"
        expr = f"{structs[i]}({expr}, {outer_y})"

    # initial value: every leaf 0
    init = "0"
    for name in reversed(structs):
        init = f"{name}({init}, 0)"

    chain = f"{root}{x_path}.y"
    return _bench_class(
        f"Depth{n}", root, tick, structs[0], shape, init, expr, chain, "{tick}",
        read_chain=f"{root}{x_path}.y",
        read_expr=f"{root}{x_path}.y",
        read_ty="Int64",
    )


def emit_width(n: int) -> str:
    """One struct with n sibling fields; update the last one."""
    name = f"W{n}"
    root, tick = f"v_w{n}", f"tick_w{n}"
    fields = [f"a{i}" for i in range(n)]
    shape = [(name, [(f, "Int64") for f in fields])]

    decls = [
        f"@DeriveOptics\n"
        f"public class {name} {{\n"
        f"    public {name}(\n"
        + ",\n".join(f"        public var {f}: {t}" for f, t in shape[0][1])
        + f"\n    ) {{ }}\n"
        f"}}"
    ]

    target = fields[-1]
    # rebuild: copy every field, substitute the counter for the target
    args = [tick if f == target else f"{root}.{f}" for f in fields]
    expr = f"{name}(\n            " + ",\n            ".join(args) + f")"

    init = f"{name}(" + ", ".join("0" for _ in fields) + ")"
    chain = f"{root}.{target}"
    return _bench_class(
        f"Width{n}", root, tick, name, shape, init, expr, chain, "{tick}", decls,
        read_chain=f"{root}.{fields[0]}",
        read_expr=f"{root}.{fields[0]}",
        read_ty="Int64",
    )


def _manifest_expr(expr: str, binders) -> str:
    """`expr` with every pattern binding rewritten to the emitter's naming.

    The macro cannot reuse a name from the enclosing scope, so it invents
    `__ioN` binders; the hand-written baseline spells them `_` or `leaf`. Neither
    name is part of the program, so the manifest rewrites the baseline's own
    binders to the `__ioN` form and check_codegen.sh erases both.
    """
    n = 0
    for name in binders:
        n += 1
        expr = re.sub(rf"(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])",
                      f"__io{n}", expr)
    return expr


# label -> baseline expression the harness is required to expand to. Written out
# as expected_expansions.txt; scripts/check_codegen.sh normalises both sides and
# diffs them, so the harness is checked to emit the reconstruct expression
# exactly instead of merely timing the same.
EXPECTED_EXPANSIONS: list[tuple[str, str]] = []


def _decls(shape) -> list[str]:
    """One `@DeriveOptics` class per type in the shape table."""
    out = []
    for name, fields in shape:
        if len(fields) == 1:
            ctor_args = f"public var {fields[0][0]}: {fields[0][1]}"
        else:
            joined = ",\n".join(f"        public var {f}: {t}" for f, t in fields)
            ctor_args = "\n" + joined
        out.append(
            f"@DeriveOptics\n"
            f"public class {name} {{\n"
            f"    public {name}({ctor_args}) {{ }}\n"
            f"}}"
        )
    return out


def _equality(shape) -> str:
    """Field-wise `==`, so the equivalence test can compare whole values."""
    out = []
    for name, fields in shape:
        cmp = " && ".join(f"this.{f} == other.{f}" for f, _ in fields)
        out.append(
            f"extend {name} {{\n"
            f"    operator func ==(other: {name}): Bool {{\n"
            f"        {cmp}\n"
            f"    }}\n"
            f"}}"
        )
    return "\n\n".join(out)


def _kind_of(entry) -> str:
    return entry[2] if len(entry) > 2 else "struct"


def _shape_attr(shape, root_ty: str) -> str:
    """The `shapes:`/`root:` attribute the @InlineOptics macro needs.

    Macros are token-level and cannot see struct declarations, so the generator
    hands the macro the constructor layout of every type on the chain.
    """
    entries = []
    for entry in shape:
        name, fields = entry[0], entry[1]
        if _kind_of(entry) == "enum":
            cases = []
            for cname, cfields in fields:
                if not cfields:
                    cases.append(f"({cname}, ())")
                elif len(cfields) == 1:
                    cases.append(f"({cname}, ({cfields[0][0]}, {cfields[0][1]}))")
                else:
                    inner = ", ".join(f"({f}, {t})" for f, t in cfields)
                    cases.append(f"({cname}, {inner})")
            entries.append(f"({name}, {', '.join(cases)})")
            continue
        parts = ", ".join(f"({f}, {t})" for f, t in fields)
        entries.append(f"({name}, {parts})")
    body = ",\n                    ".join(entries)
    return f"""shapes: {body},
            root: {root_ty}"""


def _bench_class(
    label,
    root,
    tick,
    root_ty,
    shape,
    init,
    reconstruct_expr,
    chain_expr,
    target,
    decls=None,
    dsl=True,
    equality=None,
    note="",
    binders=(),
    read_chain=None,
    read_expr=None,
    read_ty=None,
    read_eq=None,
) -> str:
    """Assemble the emitted file for one shape.

    `dsl` is False for shapes `@f` cannot express (an `Option`-returning derived
    lens is total, so `?.` through it is rejected): those files benchmark the
    hand-written `match` against `@InlineOptics` only, and their equivalence test
    has no `@f` side to compare with.

    `read_chain`/`read_expr` add the read half of the same update -- `@f(path)`
    instead of `@f(path <- tick)`. A read's direct form is a field read (a
    `match` for a partial one) rather than a rebuild, and its focus is not the
    root, so it gets its own sink, its own equivalence test and its own entry in
    the codegen manifest.

    Reads are generated, checked and *not timed*. The number this suite tracks
    is reconstruction against fused `@f` -- how close the DSL gets to the form
    the optimizer would have produced. A read has no reconstruction to compare
    against: the hand-written form of `@f(path)` is a bare field read, and
    timing that against fused `@f` measures "a pointer chase versus the DSL",
    which the pointer chase always wins. There is no gap there for the harness to
    close, so there is nothing to benchmark; the read forms are held to the
    checks that can actually fail instead.

    (For the record, because it explains the design: fused reads do cost real
    per-slot work -- 8.2 ns at two slots to 128.7 ns at sixteen, flat-
    folding to nothing as a *hand-written* read, and +7.9 ns more when the
    receivers are structs instead of classes, because a successful read copies
    every intermediate value it passes. None of that is a reconstruction gap, so
    it lives in docs/benchmarks.md as prose rather than as a benchmark column.)
    """
    if decls is None:
        decls = _decls(shape)
    eq = _equality(shape) if equality is None else equality

    update = f"{chain_expr} <- {target.format(tick=tick)}"
    optics = f"@f({update})"
    unfused = f"@f[unfuse]({update})"
    shape_attr = _shape_attr(shape, root_ty)
    inline = f"@InlineOptics[\n    {shape_attr}\n]({update})"
    body = "\n".join(decls)

    has_read = read_chain is not None
    if has_read:
        read_optics = f"@f({read_chain})"
        read_unfused = f"@f[unfuse]({read_chain})"


    benches = [f"""    @Bench
    func reconstruct(): Unit {{
        {tick} += 1
        sink_{label} = Some({reconstruct_expr})
    }}"""]
    if dsl:
        benches.append(f"""    @Bench
    func optics(): Unit {{
        {tick} += 1
        sink_{label} = {optics}
    }}

    @Bench
    func opticsUnfused(): Unit {{
        {tick} += 1
        sink_{label} = {unfused}
    }}""")

    inline_equiv = (
        f"@InlineOptics[\n            {shape_attr}\n        ]"
        f"({chain_expr} <- {target.format(tick='probe')})"
    )
    via_reconstruct = (
        f"Some({reconstruct_expr.replace(tick, 'probe')}).getOrThrow()"
    )
    if dsl:
        via_optics = f"\n        let viaOptics = {optics.replace(tick, 'probe')}"
        asserts = """        @Assert(viaInline == viaOptics)
        @Assert(viaInline == viaReconstruct)"""
    else:
        via_optics = ""
        asserts = "        @Assert(viaInline == viaReconstruct)"

    read_sink = (f"\npublic var sink_{label}Read: Option<{read_ty}> = None"
                 if has_read else "")
    read_consume = f"\n        let _ = sink_{label}Read" if has_read else ""
    read_equiv = ""
    if has_read:
        EXPECTED_EXPANSIONS.append((f"{label}Read", _manifest_expr(read_expr, binders)))
        read_inline = (
            f"@InlineOptics[\n            {shape_attr}\n        ]({read_chain})"
        )
        via_read_reconstruct = read_expr
        cmp = (lambda a, b: f"{read_eq}({a}, {b})") if read_eq else (
            lambda a, b: f"{a} == {b}"
        )
        if dsl:
            read_via_optics = f"\n        let viaOpticsRead = {read_optics}"
            read_asserts = (
                f"        @Assert({cmp('viaInlineRead', 'viaOpticsRead')})\n"
                f"        @Assert({cmp('viaInlineRead', 'viaReadReconstruct')})"
            )
        else:
            read_via_optics = ""
            read_asserts = f"        @Assert({cmp('viaInlineRead', 'viaReadReconstruct')})"
        read_equiv = f"""
@Test
class {label}ReadEquivalence {{
    @TestCase
    func readMatchesReconstruct(): Unit {{
        {tick} += 1
        let viaInlineRead = {read_inline}
        let viaReadReconstruct = {via_read_reconstruct}{read_via_optics}
{read_asserts}
    }}
}}
"""

    n_methods = 1 + (2 if dsl else 0)
    banner = f"// {note}\n" if note else ""
    read_or_write = "write a single leaf"
    EXPECTED_EXPANSIONS.append((label, _manifest_expr(reconstruct_expr.replace(tick, "probe"), binders)))
    return f"""// GENERATED by scripts/gen_bench.py -- do not edit by hand.
//
{banner}// {label}: one object shape, {n_methods} benchmark methods over the identical
// minimal update -- {read_or_write}.
// No first-class optics anywhere.

package tests.generated

import lucida.*
import lucida.macrodsl.*
import std.unittest.*
import std.unittest.testmacro.*
import tests.inline.*

{body}

{eq}

// Mutable counter, so the new leaf differs on every call and the optimiser
// cannot hoist the update out of the benchmark loop.
var {tick}: Int64 = 0

public let {root} = {init}

// Sink: keeps the compiler from discarding the update as dead code.
public var sink_{label}: Option<{root_ty}> = None{read_sink}
@Test
@Configure[baseline: "reconstruct"]
class {label}Bench {{

{chr(10) * 2 + chr(10).join(benches)}

    @AfterAll
    func consume(): Unit {{
        let _ = sink_{label}{read_consume}
    }}
}}

@Test
class {label}Equivalence {{
    @TestCase
    func inlineMatchesReconstruct(): Unit {{
        let probe = {tick} + 1
        let viaInline = {inline_equiv}
        let viaReconstruct = {via_reconstruct}{via_optics}
{asserts}
    }}
}}
{read_equiv}"""



def emit_enum(n: int) -> str:
    """A chain of nested structs ending in an enum, updated through one case.

    The case slot is partial, so both the hand-written baseline and the
    inlined form carry a miss arm that hands the source back untouched.
    """
    structs = [f"EN{n}_S{i}" for i in range(1, n)]
    enum = f"EN{n}_E"
    root, tick = f"v_en{n}", f"tick_en{n}"
    x_path = ".x" * (len(structs) - 1)

    shape = []
    for i, name in enumerate(structs):
        x_ty = structs[i + 1] if i + 1 < len(structs) else enum
        shape.append((name, [("x", x_ty), ("y", "Int64")]))
    shape.append((enum, [("Empty", None), ("Held", [("v", "Int64")])], "enum"))

    decls = [
        f"@DeriveOptics\npublic enum {enum} {{\n"
        f"    | Empty\n    | Held(Int64)\n}}"
    ] + _decls(shape[:-1])

    # rebuild: re-wrap the case, then every level outwards copying its `y`
    inner = f"{enum}.Held({tick})"
    for i in range(len(structs) - 1, -1, -1):
        inner = f"{structs[i]}({inner}, {root}{'.x' * i}.y)"
    # Bare case names and a wildcard miss arm: the same spelling `@f` and the
    # harness emit, so the codegen gate can demand exact equality.
    expr = f"""match ({root}{x_path}.x) {{
            case Held(_) => {inner}
            case _ => {root}
        }}"""

    init = f"{enum}.Empty"
    for name in reversed(structs):
        init = f"{name}({init}, 0)"

    equality = f"""extend {enum} {{
    operator func ==(other: {enum}): Bool {{
        match ((this, other)) {{
            case (Empty, Empty) => true
            case (Held(a), Held(b)) => a == b
            case _ => false
        }}
    }}
}}"""
    eq_tail = "\n\n" + "\n\n".join(
        f"extend {name} {{\n"
        f"    operator func ==(other: {name}): Bool {{\n"
        f"        this.x == other.x && this.y == other.y\n"
        f"    }}\n}}"
        for name, _ in shape[:-1]
    )

    chain = f"{root}{x_path}.x?.Held"
    # A read through a case yields the payload, and a miss yields
    # `Option<Int64>.None` -- qualified, because the miss arm needs its type
    # spelled to infer. Nothing is carried back: that is the write contract, not
    # the read one.
    read_expr = f"""match ({root}{x_path}.x) {{
            case Held(p) => Some(p)
            case _ => Option<Int64>.None
        }}"""
    return _bench_class(
        f"Enum{n}", root, tick, structs[0], shape, init, expr, chain, "{tick}",
        decls, equality=equality + eq_tail, binders=("p",),
        read_chain=f"{root}{x_path}.x?.Held",
        read_expr=read_expr,
        read_ty="Option<Int64>",
        note="A partial slot: the case can miss, and a miss rebuilds nothing.",
    )


def emit_option(n: int) -> str:
    """A chain ending in an `Option`-typed field, updated through its payload.

    `@f` has no syntax for this: a derived lens is total, so `?.` through an
    `Option`-returning lens is rejected. The family therefore has nothing to
    compare against on the DSL side -- `@InlineOptics` still has to expand to the
    hand-written `match`, which the codegen gate and the equivalence test check.
    """
    structs = [f"OP{n}_S{i}" for i in range(1, n)]
    leaf = f"OP{n}_L"
    root, tick = f"v_op{n}", f"tick_op{n}"
    x_path = ".x" * (len(structs) - 1)

    shape = []
    for i, name in enumerate(structs):
        x_ty = structs[i + 1] if i + 1 < len(structs) else f"Option<{leaf}>"
        shape.append((name, [("x", x_ty), ("y", "Int64")]))
    shape.append((leaf, [("a", "Int64"), ("b", "Int64")]))

    decls = _decls(shape[:-1]) + [_decls([shape[-1]])[0]]

    # rebuild: the payload is unwrapped by the match, so `leaf.b` is in scope
    inner = f"{leaf}({tick}, leaf.b)"
    for i in range(len(structs) - 1, -1, -1):
        inner = f"{structs[i]}({inner}, {root}{'.x' * i}.y)"
    expr = f"""match ({root}{x_path}.x) {{
            case Some(leaf) => {inner}
            case None => {root}
        }}"""

    init = f"{leaf}(0, 0)"
    for name in reversed(structs):
        init = f"{name}({init}, 0)"

    holder = structs[-1]
    equality = f"""extend {leaf} {{
    operator func ==(other: {leaf}): Bool {{
        this.a == other.a && this.b == other.b
    }}
}}

func op{n}LeafEq(a: Option<{leaf}>, b: Option<{leaf}>): Bool {{
    match ((a, b)) {{
        case (Some(p), Some(q)) => p == q
        case (None, None) => true
        case _ => false
    }}
}}

extend {holder} {{
    operator func ==(other: {holder}): Bool {{
        op{n}LeafEq(this.x, other.x) && this.y == other.y
    }}
}}""" + "\n\n" + "\n\n".join(
        f"extend {name} {{\n"
        f"    operator func ==(other: {name}): Bool {{\n"
        f"        this.x == other.x && this.y == other.y\n"
        f"    }}\n}}"
        for name, _ in shape[:-2]
    )

    chain = f"{root}{x_path}.x?.a"
    read_expr = f"""match ({root}{x_path}.x) {{
            case Some(p) => Some(p.a)
            case None => Option<Int64>.None
        }}"""
    return _bench_class(
        f"Option{n}", root, tick, structs[0], shape, init, expr, chain, "{tick}",
        decls, dsl=False, equality=equality, binders=("leaf", "p"),
        read_chain=f"{root}{x_path}.x?.a",
        read_expr=read_expr,
        read_ty="Option<Int64>",
        note=("@f cannot express this shape -- a derived lens is total, so '?.' "
              "through an Option-returning lens is rejected."),
    )


def _block_bench(
    label, root, tick, root_ty, shape, decls, init, expr, chain, target, note,
    read_chain=None, read_expr=None, read_ty=None,
) -> str:
    return _bench_class(
        label, root, tick, root_ty, shape, init, expr, chain, target, decls, note=note,
        read_chain=read_chain, read_expr=read_expr, read_ty=read_ty,
    )


def emit_iso(n: int) -> str:
    """A chain of one-field structs, updated through a coercion at the tail.

    `coerce<T>()` resolves against a one-field derivation and its field type, so
    the direct expansion of `v.x.x...x.coerce<Int64>() <- tick` is a plain nest
    of single-argument constructors -- which is exactly what `reconstruct`
    writes. The only difference between the two paths is the DSL's: `@f` has to
    build the iso's forward and backward functions and call them, so this family
    measures coercion plumbing against a field read.
    """
    structs = [f"IS{n}_S{i}" for i in range(1, n + 1)]
    root, tick = f"v_iso{n}", f"tick_iso{n}"
    x_path = ".x" * (n - 1)

    shape = []
    for i, name in enumerate(structs):
        if i + 1 < n:
            shape.append((name, [("x", structs[i + 1])]))
        else:
            shape.append((name, [("v", "Int64")]))

    # rebuild: single-argument constructors all the way in, no field reads at
    # all -- the coercion *is* the leaf constructor.
    inner = tick
    for name in reversed(structs):
        inner = f"{name}({inner})"

    init = tick.replace(tick, "0")
    for name in reversed(structs):
        init = f"{name}({init})"

    return _bench_class(
        f"Iso{n}", root, tick, structs[0], shape, init, inner,
        f"{root}{x_path}.coerce<Int64>()", "{tick}",
        read_chain=f"{root}{x_path}.coerce<Int64>()",
        read_expr=f"{root}{x_path}.v",
        read_ty="Int64",
        note="A coercion at the tail: the direct form is a nest of one-argument\n"
             "// constructors, so the DSL's iso plumbing is the only difference.",
    )


def emit_block_depth(n: int) -> str:
    """A nested chain whose innermost struct has both leaves written at once."""
    structs = [f"BD{n}_S{i}" for i in range(1, n + 1)]
    root, tick = f"v_bd{n}", f"tick_bd{n}"
    x_path = ".x" * (n - 1)

    shape = []
    for i, name in enumerate(structs):
        x_ty = "Int64" if i == n - 1 else structs[i + 1]
        shape.append((name, [("x", x_ty), ("y", "Int64")]))

    inner = f"{structs[-1]}({tick}, {tick})"
    for i in range(n - 2, -1, -1):
        inner = f"{structs[i]}({inner}, {root}{'.x' * i}.y)"

    init = "0"
    for name in reversed(structs):
        init = f"{name}({init}, 0)"

    chain = f"{root}{x_path}.{{ .x; .y }}"
    return _block_bench(
        f"BlockDepth{n}", root, tick, structs[0], shape, _decls(shape), init, inner,
        chain, "({tick}, {tick})",
        "A sibling block: two writes into one anchor, sharing a rebuild.",
        read_chain=f"{root}{x_path}.{{ .x; .y }}",
        read_expr=f"({root}{x_path}.x, {root}{x_path}.y)",
        read_ty="(Int64, Int64)",
    )


def emit_block_width(n: int) -> str:
    """A sibling block writing every field of a wide struct at once."""
    name = f"BW{n}"
    root, tick = f"v_bw{n}", f"tick_bw{n}"
    fields = [f"a{i}" for i in range(n)]
    shape = [(name, [(f, "Int64") for f in fields])]

    expr = f"{name}(\n            " + ",\n            ".join(tick for _ in fields) + ")"
    init = f"{name}(" + ", ".join("0" for _ in fields) + ")"
    chain = f"{root}.{{ " + "; ".join(f".{f}" for f in fields) + " }"
    target = "(" + ", ".join("{tick}" for _ in fields) + ")"  # placeholder

    return _block_bench(
        f"BlockWidth{n}", root, tick, name, shape, _decls(shape), init, expr, chain,
        target, "A sibling block wide enough to force a tuple target.",
        read_chain=chain,
        read_expr="(" + ", ".join(f"{root}.{f}" for f in fields) + ")",
        read_ty="(" + ", ".join("Int64" for _ in fields) + ")",
    )


def emit_prism_block() -> str:
    """A sibling block anchored on a case: the guard decides once, then the
    block writes both of the payload's fields.

    `x?.Held.{ .a; .b }` spends its `?.` on the case, so the block's owner is the
    payload and the whole write sits inside the case's `match`: a hit rebuilds
    the case, a miss hands the enum back untouched. The hand-written baseline is
    that same `match`, which is what the codegen gate compares against.
    """
    payload, enum = "PB_P", "PB_E"
    root, tick = "v_pb", "tick_pb"

    shape = [
        (payload, [("a", "Int64"), ("b", "Int64")]),
        (enum, [("Empty", None), ("Held", [("p", payload)])], "enum"),
    ]
    decls = [
        f"@DeriveOptics\npublic enum {enum} {{\n"
        f"    | Empty\n    | Held({payload})\n}}"
    ] + _decls(shape[:-1])

    init = f"{enum}.Held({payload}(0, 0))"

    # Bare case name and a wildcard miss arm: the same spelling `@f` and the
    # harness emit, so the codegen gate can demand exact equality.
    expr = f"""match ({root}) {{
            case Held(_) => {enum}.Held({payload}({tick}, {tick}))
            case _ => {root}
        }}"""

    equality = f"""extend {enum} {{
    operator func ==(other: {enum}): Bool {{
        match ((this, other)) {{
            case (Empty, Empty) => true
            case (Held(a), Held(b)) => a == b
            case _ => false
        }}
    }}
}}"""

    # `Option` has no structural `==` for a tuple payload, so the read half
    # compares through a matcher of its own.
    eq_helper = """private func pbOptPairEq(x: Option<(Int64, Int64)>, y: Option<(Int64, Int64)>): Bool {
    match ((x, y)) {
        case (Some(p), Some(q)) =>
            let (pa, pb) = p
            let (qa, qb) = q
            pa == qa && pb == qb
        case (None, None) => true
        case _ => false
    }
}"""
    decls = decls + [eq_helper]

    chain = f"{root}?.Held.{{ .a; .b }}"
    read_expr = f"""match ({root}) {{
            case Held(p) => Some((p.a, p.b))
            case _ => Option<(Int64, Int64)>.None
        }}"""
    return _bench_class(
        "PrismBlock", root, tick, enum, shape, init, expr, chain, "({tick}, {tick})",
        decls, equality=equality + "\n\n" + _equality(shape[:-1]), binders=("p",),
        read_chain=chain,
        read_expr=read_expr,
        read_ty="Option<(Int64, Int64)>",
        read_eq="pbOptPairEq",
        note="A sibling block behind a case: the guard wraps the whole block rebuild.",
    )


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--out",
        default="tests/src/generated",
        help="output directory for the generated package (default: %(default)s)",
    )
    ap.add_argument(
        "--depth-list",
        default=",".join(str(n) for n in DEFAULT_DEPTHS),
        help="comma-separated nesting depths (default: %(default)s)",
    )
    ap.add_argument(
        "--enum-list",
        default=",".join(str(n) for n in DEFAULT_ENUMS),
        help="comma-separated depths for the enum (prism) family",
    )
    ap.add_argument(
        "--option-list",
        default=",".join(str(n) for n in DEFAULT_OPTIONS),
        help="comma-separated depths for the Option-partial family",
    )
    ap.add_argument(
        "--block-depth-list",
        default=",".join(str(n) for n in DEFAULT_BLOCK_DEPTHS),
        help="comma-separated depths for the sibling-block family",
    )
    ap.add_argument(
        "--block-width-list",
        default=",".join(str(n) for n in DEFAULT_BLOCK_WIDTHS),
        help="comma-separated field counts for the wide sibling-block family",
    )
    ap.add_argument(
        "--iso-list",
        default=",".join(str(n) for n in DEFAULT_ISOS),
        help="comma-separated depths for the coercion family",
    )
    ap.add_argument(
        "--width-list",
        default=",".join(str(n) for n in DEFAULT_WIDTHS),
        help="comma-separated field counts (default: %(default)s)",
    )
    args = ap.parse_args(argv)

    def sizes(name: str) -> list[int]:
        return [int(x) for x in getattr(args, name).split(",") if x.strip()]

    depths = sizes("depth_list")
    widths = sizes("width_list")
    enums = sizes("enum_list")
    options = sizes("option_list")
    block_depths = sizes("block_depth_list")
    block_widths = sizes("block_width_list")
    isos = sizes("iso_list")
    if not (depths or widths or enums or options or block_depths or block_widths or isos):
        print("error: nothing to generate", file=sys.stderr)
        return 2

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    written = []
    for n in depths:
        path = out / f"depth{n}.cj"
        path.write_text(emit_depth(n))
        written.append(path)
    for n in widths:
        path = out / f"width{n}.cj"
        path.write_text(emit_width(n))
        written.append(path)
    for n in enums:
        path = out / f"enum{n}.cj"
        path.write_text(emit_enum(n))
        written.append(path)
    for n in options:
        path = out / f"option{n}.cj"
        path.write_text(emit_option(n))
        written.append(path)
    for n in block_depths:
        path = out / f"blockdepth{n}.cj"
        path.write_text(emit_block_depth(n))
        written.append(path)
    for n in block_widths:
        path = out / f"blockwidth{n}.cj"
        path.write_text(emit_block_width(n))
        written.append(path)
    for n in isos:
        path = out / f"iso{n}.cj"
        path.write_text(emit_iso(n))
        written.append(path)
    path = out / "prismblock.cj"
    path.write_text(emit_prism_block())
    written.append(path)

    manifest = out / "expected_expansions.txt"
    manifest.write_text("".join(
        f"{label}\t{' '.join(expr.split())}\n"
        for label, expr in sorted(EXPECTED_EXPANSIONS)
    ))

    for path in written:
        print(f"wrote {path}")
    print(f"wrote {manifest}")
    # counted from the files, not from the shape table, so a family that grew or
    # lost a method cannot quietly disagree with the reported total
    total = sum(path.read_text().count("@Bench") for path in written)
    print(
        f"\n{len(written)} shapes, {total} benchmarks ({len(depths)} depth, "
        f"{len(widths)} width, {len(enums)} enum, {len(options)} option, "
        f"{len(block_depths)} block depth, {len(block_widths)} block width, "
        f"{len(isos)} iso, 1 prism block)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))