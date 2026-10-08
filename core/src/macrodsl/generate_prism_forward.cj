macro package lucida.macrodsl

import std.ast.*
import std.collection.*

/// Generates `pinPrismForward1..N`, the fused forward walkers for chains with
/// 1..N partial (Option-producing) slots. Each generated function has the same
/// signature and body shape as the historical hand-written `pinPrismForwardK`:
/// a named generic function is what lets call-site inference pin S/Ti/Ai/B —
/// the macro cannot inline the match pyramid because lambda parameter types
/// are not inferable from bodies. Raising the fusion cap therefore means
/// regenerating with a larger N, not hand-unrolling more levels.
/**
 * input - number literal
 */
public macro GeneratePrismForward(input: Tokens): Tokens {
    let n = parseAsUInt64(input)
    generatePrismForwards(n)
}

private func generatePrismForwards(max: UInt64): Tokens {
    var out = quote()
    var k: UInt64 = 1
    while (k <= max) {
        out = quote(
            $out
            $(prismForwardDecl(k))
        )
        k = k + 1
    }
    out
}

// One `pinPrismForwardK` declaration:
//   public func pinPrismForwardK<S, T1..Tk, A1..Ak, B>(
//       sourceThunk: () -> S,
//       fwdI: (Ti) -> Option<Ai>,        // I = 1..k
//       run0: (S) -> T1,
//       runI: (Ai) -> T(i+1),           // I = 1..k-1
//       contK: (Ak) -> B
//   ): (S) -> Option<B>
//   { s: S => match (fwd1(run0(s))) { case Right(a1) => ... Right<S, B>(contK(aK)) ... } }
private func prismForwardDecl(k: UInt64): Tokens {
    let s = idTok("S")
    let b = idTok("B")
    let fnId = idTok("pinPrismForward${k}")

    let typeParams = ArrayList<Tokens>()
    typeParams.add(quote($s))
    for (i in 1..k+1) {
        typeParams.add(quote($(idTok("T${i}"))))
    }
    for (i in 1..k+1) {
        typeParams.add(quote($(idTok("A${i}"))))
    }
    typeParams.add(quote($b))

    let params = ArrayList<Tokens>()
    params.add(quote(_ : () -> $s))
    for (i in 1..k+1) {
        let ti = idTok("T${i}")
        let ai = idTok("A${i}")
        let fwdI = idTok("fwd${i}")
        params.add(quote($fwdI: ($ti) -> Option<$ai>))
    }
    let t1 = idTok("T1")
    let run0 = idTok("run0")
    params.add(quote($run0: ($s) -> $t1))
    for (i in 1..k) {
        let ai = idTok("A${i}")
        let ti1 = idTok("T${i+1}")
        let runI = idTok("run${i}")
        params.add(quote($runI: ($ai) -> $ti1))
    }
    let ak = idTok("A${k}")
    let contK = idTok("cont${k}")
    params.add(quote($contK: ($ak) -> $b))

    let body = buildPrismPyramid(k, b)

    quote(
        @Frozen
        public func $fnId<$(commaSeparated(typeParams))>(
            $(commaSeparated(params))
        ): ($s) -> Option<$b> {
            { s: $s =>
                $body
            }
        }
    )
}

// Builds the nested Right/Left match pyramid innermost-first. Pattern
// variables are the lowercase `a${i}`; `T${i}`/`A${i}`/`S`/`B` are types.
private func buildPrismPyramid(k: UInt64, b: Token): Tokens {
    let contK = idTok("cont${k}")
    let aK = idTok("a${k}")
    var inner = quote(Some<$b>($contK($aK)))
    var i = k
    while (i >= 1) {
        let ai = idTok("a${i}")
        let fwdI = idTok("fwd${i}")
        let probe = if (i == 1) {
            quote($fwdI(run0(s)))
        } else {
            let aPrev = idTok("a${i-1}")
            let runPrev = idTok("run${i-1}")
            quote($fwdI($runPrev($aPrev)))
        }
        inner = quote(
            match ($probe) {
                case Some($ai) => $inner
                case None => None
            }
        )
        i = i - 1
    }
    inner
}
