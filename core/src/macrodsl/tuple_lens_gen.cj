macro package lucida.macrodsl

import std.ast.*
import std.collection.*
import std.convert.*

func parseAsUInt64<T>(input: T): UInt64 where T <: ToTokens {
    let lce: LitConstExpr = (parseExpr(input.toTokens()) as LitConstExpr) ?? throw Exception("pass integer")
    assert(lce.literal.kind == INTEGER_LITERAL) { "pass integer" }
    UInt64.parse(lce.literal.value)
}

/**
 * input - number literal
 *
 * Generates, per arity k in 2..N, the tuple-lens plumbing the DSL's `._i`
 * element access rides on:
 *   - `extend <X..> RegistryLenses<(X..)>` with the element impl pair
 *     (`___i_impl_forward` / `___i_impl_backward`) for every element i;
 *   - `extend <X..> RegistryMagical<(X..)>` with the element accessors
 *     (`___i_optics`) and `__downcast`.
 *
 * The emission is a CPS walk over the arities, kept composable: each arity
 * wraps the accumulated element-pair chain (`currentFuncs`) and hands a
 * continuation down. The chain is memoized per (level, size) — a level's
 * block depends on both (the backward rebuild args grow with the tuple
 * arity) — so every block is built exactly once. The per-arity extends are
 * collected flat and joined in a single pass: nested quote() splices
 * re-parse their interpolated content, which is what made re-splicing the
 * growing buffer quadratic-plus in practice (see docs/compiler-issues.md).
 */
public macro GenerateTupleExtendsLenses(input: Tokens): Tokens {
    try {
        let n = parseAsUInt64(input)
        generateTupleExtends(n)
    } catch (e: DiagReportException) {
        reportCaughtDiag(e.tokens, e.message, e.hint)
        quote($input)
    } catch (e: Exception) {
        reportCaughtDiag(input, "GenerateTupleExtendsLenses: ${e.message}", "pass an integer literal, e.g. @GenerateTupleExtendsLenses(16)")
        quote($input)
    }
}

// Levels are < 1024 and sizes are < 1024, so the composite memo key is
// collision-free.
private func memoKey(level: UInt64, size: UInt64): UInt64 {
    level * 1024 + size
}

private func generateTupleExtends(max: UInt64): Tokens {
    let memo = HashMap<UInt64, Tokens>()
    let blocks = ArrayList<Tokens>()
    let X0 = Token(IDENTIFIER, "X0")

    // Base chain level: the element-0 pair, parameterized over the tuple type
    // and the arity it is being emitted for.
    let baseFuncs = { tupleType: Tokens, size: UInt64 =>
        match (memo.get(memoKey(1, size))) {
            case Some(cached) => cached
            case None =>
                let built = quote(
                    @Frozen
                    public func ___0_impl_forward(source: $tupleType): $X0 {
                        source[0]
                    }
                    @Frozen
                    public func ___0_impl_backward(source: $tupleType, focus: $X0): $tupleType {
                        ($(rebuildArgs(size, 0)))
                    }
                )
                memo.add(memoKey(1, size), built)
                built
        }
    }

    generateExtend(2, max, quote($X0), baseFuncs, memo, blocks)

    // Blocks were collected while unwinding: highest arity first. Join once.
    var out = Tokens()
    var idx = blocks.size - 1
    while (idx >= 0) {
        out.append(blocks[idx])
        idx = idx - 1
    }
    out
}

// The backward rebuild argument list for element `focusAt` of a `size`-tuple:
// (source[0], ..., focus, ..., source[size-1]).
private func rebuildArgs(size: UInt64, focusAt: UInt64): Tokens {
    var args = quote()
    var j: UInt64 = 0
    while (j < size) {
        let arg = if (j == focusAt) { quote(focus) } else { quote(source[$j]) }
        args = if (j == 0) { arg } else { quote($args, $arg) }
        j = j + 1
    }
    args
}

private func generateExtend(
    current: UInt64,
    max: UInt64,
    genericPrefix: Tokens,
    prevFuncs: (Tokens, UInt64) -> Tokens,
    memo: HashMap<UInt64, Tokens>,
    blocks: ArrayList<Tokens>
): Unit {
    if (current > max) { return }

    let xn = Token(IDENTIFIER, "X${current-1}")
    let genericArgs = quote($genericPrefix, $xn)
    let funcNameLensForward = Token(IDENTIFIER, "___${current-1}_impl_forward")
    let funcNameLensBackward = Token(IDENTIFIER, "___${current-1}_impl_backward")

    // The accumulated element-pair block for this chain level, memoized per
    // (level, size): the same level is walked once per deeper arity, and the
    // blocks differ by the rebuild-arg count.
    let currentFuncs = { tupleType: Tokens, size: UInt64 =>
        match (memo.get(memoKey(current, size))) {
            case Some(cached) => cached
            case None =>
                let built = quote(
                    $(prevFuncs(tupleType, size))
                    @Frozen
                    public func $funcNameLensForward(source: $tupleType): $xn {
                        source[$(current-1)]
                    }
                    @Frozen
                    public func $funcNameLensBackward(source: $tupleType, focus: $xn): $tupleType {
                        ($(rebuildArgs(size, current - 1)))
                    }
                )
                memo.add(memoKey(current, size), built)
                built
        }
    }

    generateExtend(current + 1, max, genericArgs, currentFuncs, memo, blocks)

    // Unwinding: emit this arity's pair of extends after all deeper arities
    // have been collected. Flat append — no token splicing of the accumulated
    // output.
    let tupleType = quote(($genericArgs))

    var accessors = quote()
    var i: UInt64 = 0
    while (i < current) {
        let xi = Token(IDENTIFIER, "X${i}")
        let accId = Token(IDENTIFIER, "___${i}_optics")
        accessors = quote(
            $accessors
            @Frozen
            public func $accId(_: RegistryMagical<$tupleType>): RegistryMagical<$xi> {
                RegistryMagical()
            }
        )
        i = i + 1
    }

    blocks.add(quote(
        extend <$genericArgs> RegistryLenses<$tupleType> {
            $(currentFuncs(tupleType, current))
        }
        extend <$genericArgs> RegistryMagical<$tupleType> {
            $accessors
            @Frozen
            public func __downcast(_: RegistryMagical<$tupleType>): RegistryLenses<$tupleType> {
                RegistryLenses()
            }
        }
    ))
}
