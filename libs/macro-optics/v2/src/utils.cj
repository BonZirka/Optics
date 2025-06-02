macro package lucida_macro

import std.ast.*
import std.collection.*

class DiagReportException <: Exception {
    DiagReportException(
        message: String,
        public let tokens: Tokens,
        public let hint!: String = ""
    ) { super(message) }
}

extend ArrayList<Decl> {
    public func addContra<T>(decl: T) where T <: Decl {
        let res: Decl = decl
        add(res)
    }
}

extend Decl {
    prop accessModifier: ?Modifier {
        get() {
            this.modifiers |> filter { it: Modifier =>
                let kind = it.keyword.kind
                kind == TokenKind.PUBLIC ||
                kind == TokenKind.PROTECTED ||
                kind == TokenKind.PRIVATE
            } |> first
        }
    }
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

func assert<T>(expr: Bool, message: () -> T): Unit where T <: ToString {
    if (!expr) {
        throw Exception(message().toString())
    }
}

func parseCommaSeparatedExpressions(input: Tokens): Array<Expr> {
    let parsedFakeCall = (parseExpr(quote(dummy($input))) as CallExpr).getOrThrow()
    return parsedFakeCall.arguments |> map { arg: Argument => arg.expr } |> collectArray
}

func parseCommaSeparatedExpressions2(input: Tokens): Array<Expr> {
    let parsedFakeCall = (parseExpr(quote(dummy($input))) as CallExpr).getOrThrow()
    if (parsedFakeCall.arguments.size != 2) {
        throw DiagReportException(
            "Expected 2 arguments, but got ${parsedFakeCall.arguments.size}",
            input
        )
    }
    return parsedFakeCall.arguments |> map { arg: Argument => arg.expr } |> collectArray
}

func generics(targs: ArrayList<TypeNode>): Tokens {
    if (targs.size == 0) { quote() }
    else {
        quote(<$(commaSeparated(targs))>)
    }
}

// ===== Fused emission helpers =====

/// Emits `let __magicalI = ...; let __opticsI = ...; let __fwdI = ...; let __bwdI = ...;`
/// for a Derived (struct field) segment. The caller threads the next magical
/// expression (referencing the local `__magical${index}` binding) into the next
/// segment via `derivedNextMagicalExpr`.
func emitDerivedLeafBindings(
    index: Int64,
    fieldTok: Token,
    prevMagicalExpr: Tokens
): Tokens {
    let currMagical = Token(IDENTIFIER, "__magical${index}")
    let opticsId   = Token(IDENTIFIER, "__optics${index}")
    let fwdId      = Token(IDENTIFIER, "__fwd${index}")
    let bwdId      = Token(IDENTIFIER, "__bwd${index}")
    let accessForward  = Token(IDENTIFIER, "__${fieldTok.value}_impl_forward")
    let accessBackward = Token(IDENTIFIER, "__${fieldTok.value}_impl_backward")
    quote(
        let $currMagical = $prevMagicalExpr
        let $opticsId = $currMagical.__downcast($currMagical)
        let $fwdId = $opticsId.$accessForward
        let $bwdId = $opticsId.$accessBackward
    )
}

/// Returns the next magical expression for a Derived segment, referencing the
/// local `__magical${index}` binding (bound by `emitDerivedLeafBindings`) so the
/// generated code stays linear in chain depth rather than exponential.
func derivedNextMagicalExpr(index: Int64, fieldTok: Token): Tokens {
    let currMagical = Token(IDENTIFIER, "__magical${index}")
    let accessMagic = Token(IDENTIFIER, "__${fieldTok.value}_optics")
    quote($currMagical.$accessMagic($currMagical))
}