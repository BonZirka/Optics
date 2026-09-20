macro package optics_experiments.testutils

import std.ast.*

/**
 * input - number literal
 */
public macro GenerateComposeFuncDecls(input: Tokens): Tokens {
    let n = parseAsUInt64(input)
    generateComposeFuncDecls(n)
}

private func generateComposeFuncDecls(max: UInt64): Tokens {
    let genericParamPrefix = "X"
    let argnamePrefix = "x"
    let lambdaArgName = Token(IDENTIFIER, "input")
    func generateCFD(
        current: UInt64,
        genericPrefix: Tokens,
        argsPrefix: Tokens,
        compositionPrefix: Tokens,
        cont: (Tokens) -> Tokens): Tokens {
        assert(current >= 2) { "TOO SMALL!" }
        if (current > max) {
            cont(quote())
        } else {
            let x0 = Token(IDENTIFIER, "${genericParamPrefix}0")
            let xn = Token(IDENTIFIER, "${genericParamPrefix}${current}")
            let xnm1 = Token(IDENTIFIER, "${genericParamPrefix}${current-1}")
            let argname = Token(IDENTIFIER, "${argnamePrefix}${current-1}")
            let funcArgs = quote($argsPrefix, $argname: ($xnm1) -> $xn)
            let genericArgs = quote($genericPrefix, $xn)
            let funcName = Token(IDENTIFIER, "composeFunc${current}")
            let composition = quote($argname($compositionPrefix))
            let funcDecl = quote(
                @Frozen
                public func $funcName<$genericArgs>($funcArgs): ($x0) -> $xn {
                    { $lambdaArgName: $x0 => $composition }
                })
            generateCFD(
                current + 1,
                genericArgs,
                funcArgs,
                composition
            ) { nextDecl =>
                cont(quote(
                    $funcDecl
                    $nextDecl
                ))
            }
        }
    }

    let X0 = Token(IDENTIFIER, "${genericParamPrefix}0")
    let X1 = Token(IDENTIFIER, "${genericParamPrefix}1")
    let x0 = Token(IDENTIFIER, "${argnamePrefix}0")
    generateCFD(
        2,
        quote($X0, $X1),
        quote($x0: ($X0) -> ($X1)),
        quote($x0($lambdaArgName))
    ) { x => x }
}
