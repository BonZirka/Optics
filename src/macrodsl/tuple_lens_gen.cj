macro package lucida.macrodsl

import std.ast.*
import std.collection.*
import std.convert.*

/**
 * input - number literal
 */
public macro GenerateTupleExtendsLenses(input: Tokens): Tokens {
    let n = parseAsUInt64(input)
    generateTupleExtends(n)
}

private func generateTupleExtends(max: UInt64): Tokens {
    let genericParamPrefix = "X"
    let argnamePrefix = "x"
    func generateExtend(
        current: UInt64,
        genericPrefix: Tokens,
        prevFuncs: (Tokens, UInt64) -> Tokens,
        cont: (Tokens) -> Tokens): Tokens {
        assert(current >= 2) { "TOO SMALL!" }
        if (current > max) {
            cont(quote())
        } else {
            let xn = Token(IDENTIFIER, "${genericParamPrefix}${current-1}")
            let genericArgs = quote($genericPrefix, $xn)
            let funcNameLensForward = Token(IDENTIFIER, "___${current-1}_impl_forward")
            let funcNameLensBackward = Token(IDENTIFIER, "___${current-1}_impl_backward")
            let funcNameOptics = Token(IDENTIFIER, "___${current-1}_optics")
            let currentFuncs = { tupleType: Tokens, size: UInt64 =>
                let argvars: Array<Tokens> = 0..size |> map { n: UInt64 => quote(source[$n])} |> collectArray
                argvars[Int64(current-1)] = quote(focus)
                quote($(prevFuncs(tupleType, size))
                    @Frozen
                    public func $funcNameLensForward(source: $tupleType): $xn {
                        source[$(current-1)]
                    }
                    @Frozen
                    public func $funcNameLensBackward(source: $tupleType, focus: $xn): $tupleType {
                        ($(commaSeparated(argvars)))
                    }
                    )
            }
            generateExtend(
                current + 1,
                genericArgs,
                currentFuncs
            ) { nextExtends =>
                let tupleType = quote(($genericArgs))
                cont(quote(extend <$genericArgs> RegistryLenses<$tupleType> {
                        $(currentFuncs(tupleType, current))
                    }

                    $nextExtends))
            }
        }
    }

    let current: UInt64 = 1 
    let X0 = Token(IDENTIFIER, "${genericParamPrefix}${current-1}")
    let funcNameLensForward = Token(IDENTIFIER, "___${current-1}_impl_forward")
    let funcNameLensBackward = Token(IDENTIFIER, "___${current-1}_impl_backward")
    let funcNameOptics = Token(IDENTIFIER, "___${current-1}_optics")
    let currentFuncs = { tupleType: Tokens, size: UInt64 =>
        var argvars: Array<Tokens> = 0..size |> map { n: UInt64 => quote(source[$n])} |> collectArray
        argvars[Int64(current-1)] = quote(focus)
        quote(
            @Frozen
            public func $funcNameLensForward(source: $tupleType): $X0 {
                source[$(current-1)]
            }
            @Frozen
            public func $funcNameLensBackward(source: $tupleType, focus: $X0): $tupleType {
                ($(commaSeparated(argvars)))
            }
        )
    }
    generateExtend(
        current + 1,
        quote($X0),
        currentFuncs,
    ) { x => x }
}

func parseAsUInt64<T>(input: T): UInt64 where T <: ToTokens {
    let lce: LitConstExpr = (parseExpr(input.toTokens()) as LitConstExpr) ?? throw Exception("pass integer")
    assert(lce.literal.kind == INTEGER_LITERAL) { "pass integer" }
    UInt64.parse(lce.literal.value)
}