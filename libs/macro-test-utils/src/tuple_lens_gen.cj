macro package macro_test_utils

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

func commaSeparated<T>(things: Iterable<T>): Tokens where T <: ToTokens {
    let tokens = Tokens()
    let it = things.iterator()
    let first = it.next()

    (first?.toTokens() ?? return tokens) |> tokens.append

    for (e in it) {
        tokens.append(Token(COMMA)).append(e.toTokens())
    }
    return tokens
}