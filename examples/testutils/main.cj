macro package optics_experiments.testutils

import std.ast.*
import std.collection.*
import std.convert.*

/**
 * input - number literal
 */
public macro GenerateNestedStruct(input: Tokens): Tokens {
    let n = parseAsUInt64(input)
    generateStruct(1, n) { x => x }
}

public macro GenerateInit(input: Tokens): Tokens {
    let n = parseAsUInt64(input)
    generateInit(1, n) { x => x }
}

public macro GenerateReconstruct(input: Tokens): Tokens {
    let args = parseCommaSeparatedExpressions(input)
    assert(args.size == 2) { "1st arg - variable name; 2nd arg - number literal" }
    let n = parseAsUInt64(args[1])
    let initVar = args[0]
    generateReconstruct(1, n, initVar.toTokens()) { x => x }
}


public macro GenerateLucidaCall(input: Tokens): Tokens {
    let args = parseCommaSeparatedExpressions(input)
    assert(args.size == 2) { "1st arg - variable name; 2nd arg - number literal" }
    let n = parseAsUInt64(args[1])
    let initVar = args[0]
    generateLucidaCall(1, n, initVar.toTokens()) { x => x }
}

public macro GenerateStructSetting(input: Tokens): Tokens {
    let args = parseCommaSeparatedExpressions(input)
    assert(args.size == 2) { "1st arg - variable name; 2nd arg - number literal" }
    let n = parseAsUInt64(args[1])
    let initVar = args[0]
    generateStructSetting(1, n, initVar.toTokens()) { x => x }
}

private func generateStructSetting(current: UInt64, max: UInt64, initVar: Tokens, cont: (Tokens) -> Tokens): Tokens {
    if (current >= max) {
        quote(
            $(cont(initVar)).y = "New"
        )
    } else {
        generateStructSetting(current + 1, max, initVar) { prevCall: Tokens =>
            quote($(cont(prevCall)).x)
        }
    }
}

private func generateLucidaCall(current: UInt64, max: UInt64, initVar: Tokens, cont: (Tokens) -> Tokens): Tokens {
    if (current >= max) {
        quote(
            @f($(cont(initVar)).y <- "New")
        )
    } else {
        generateLucidaCall(current + 1, max, initVar) { prevCall: Tokens =>
            quote($(cont(prevCall)).x)
        }
    }
}

private func generateReconstruct(current: UInt64, max: UInt64, prefix: Tokens, cont: (Tokens) -> Tokens): Tokens {
    let structNamePrefix = "Struct_"
    let structName = Token(IDENTIFIER, "${structNamePrefix}${current}")
    if (current >= max) {
        let constructorCall = quote(
            $structName($prefix.x, "New")
        )
        cont(constructorCall)
    } else {
        generateReconstruct(current + 1, max, quote($prefix.x)) { nextConstructorCall: Tokens =>
            cont(quote($structName($nextConstructorCall, $prefix.y)))
        }
    }
}

private func generateInit(current: UInt64, max: UInt64, cont: (Tokens) -> Tokens): Tokens {
    let structNamePrefix = "Struct_"
    let structName = Token(IDENTIFIER, "${structNamePrefix}${current}")
    if (current >= max) {
        let constructorCall = quote(
            $structName("Brave", "Old")
        )
        cont(constructorCall)
    } else {
        generateInit(current + 1, max) { nextConstructorCall: Tokens =>
            cont(quote($structName($nextConstructorCall, "World")))
        }
    }
}

private func generateStruct(current: UInt64, max: UInt64, cont: (Tokens) -> Tokens): Tokens {
    let structNamePrefix = "Struct_"
    let structName = Token(IDENTIFIER, "${structNamePrefix}${current}")
    let macroses = quote(
        @Derive[ToString]
        @DeriveOptics
    )
    if (current >= max) {
        let structDecl = quote(
            $macroses
            public class $structName {
                public $structName(
                    public var x: String,
                    public var y: String
                ) { }
            }
        )
        cont(structDecl)
    } else {
        let nextStructName = Token(IDENTIFIER, "${structNamePrefix}${current + 1}")
        generateStruct(current + 1, max) { nextStructDecl: Tokens =>
            let structDecl = quote(
                $macroses
                public class $structName {
                    public $structName(
                        public var x: $nextStructName, 
                        public var y: String
                    ) { }
                }
            )
            cont(quote(
                $structDecl
                $nextStructDecl
            ))
        }
    }
}

func parseAsUInt64<T>(input: T): UInt64 where T <: ToTokens {
    let lce: LitConstExpr = (parseExpr(input.toTokens()) as LitConstExpr) ?? throw Exception("pass integer")
    assert(lce.literal.kind == INTEGER_LITERAL) { "pass integer" }
    UInt64.parse(lce.literal.value)
}

func parseCommaSeparatedExpressions(input: Tokens): Array<Expr> {
    let parsedFakeCall = (parseExpr(quote(dummy($input))) as CallExpr).getOrThrow()
    return parsedFakeCall.arguments |> map { arg: Argument => arg.expr } |> collectArray
}

func assert<T>(expr: Bool, message: () -> T): Unit where T <: ToString {
    if (!expr) {
        throw Exception(message().toString())
    }
}
