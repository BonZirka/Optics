macro package lucida_macro

import std.ast.*
import std.collection.*

public macro Type(input: Tokens): Tokens {
    try {
        if (insideParentContext(mainMacroName[1..])) {
            let re = input as RefExpr ?? throw DiagReportException(
                "${typeMacroName}: macro input should be type (RefExpr)",
                input
            )
            return quote($typeFakeCallexprId($re))
        }
        throw DiagReportException(
            "${typeMacroName}: macro should be contained inside '${mainMacroName}'",
            input
        )
    } catch (e: DiagReportException) {
        diagReport(
            DiagReportLevel.ERROR,
            e.tokens,
            e.message,
            e.hint
        )
        quote($input)
    }
}

public macro TypeOf(input: Tokens): Tokens {
    try {
        if (insideParentContext(mainMacroName[1..])) {
            return quote($typeOfFakeCallexprId($input))
        }
        throw DiagReportException(
            "${typeOfMacroName}: macro should be contained inside '${mainMacroName}'",
            input
        )
    } catch (e: DiagReportException) {
        diagReport(
            DiagReportLevel.ERROR,
            e.tokens,
            e.message,
            e.hint
        )
        quote($input)
    }
}

public macro Optic(input: Tokens): Tokens {
    try {
        if (insideParentContext(mainMacroName[1..])) {
            let re = if (input.size == 1) {
                RefExpr(quote($input))
            } else { 
                input as RefExpr ?? throw DiagReportException(
                    "${opticMacroName}: macro input should be type (RefExpr)",
                    input
                )
            }
            if (re.typeArguments.size != 0) {
                throw DiagReportException(
                    "${opticMacroName}: an input should be valid identifier",
                    re.toTokens()
                )
            }
            return quote($opticFakeCallexprId($(re.identifier)))
        }
        throw DiagReportException(
            "${opticMacroName}: macro should be contained inside '${mainMacroName}'",
            input
        )
    } catch (e: DiagReportException) {
        diagReport(
            DiagReportLevel.ERROR,
            e.tokens,
            e.message,
            e.hint
        )
        quote($input)
    }
}