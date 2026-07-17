macro package lucida.macrodsl

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

/// Emits `let __magicalI = ...; let __opticsI = ...; let __fwdI = ...; let __bwdI = ...`
/// for an affine method segment (`at` / `selectFirst`). The impl members take the
/// registry plus the original call arguments and return the forward/backward
/// function values, which is exactly the shape the fused walkers consume.
func emitUserDefinedLeafBindings(
    index: Int64,
    name: Token,
    targs: ArrayList<TypeNode>,
    args: ArrayList<Argument>,
    prevMagicalExpr: Tokens
): Tokens {
    let currMagical = Token(IDENTIFIER, "__magical${index}")
    let opticsId   = Token(IDENTIFIER, "__optics${index}")
    let fwdId      = Token(IDENTIFIER, "__fwd${index}")
    let bwdId      = Token(IDENTIFIER, "__bwd${index}")
    let accessForward  = Token(IDENTIFIER, "__method_${name.value}_impl_forward")
    let accessBackward = Token(IDENTIFIER, "__method_${name.value}_impl_backward")
    let downcastName   = Token(IDENTIFIER, "__downcast_method_${name.value}")
    let gen = generics(targs)
    quote(
        let $currMagical = $prevMagicalExpr
        let $opticsId = $currMagical.$downcastName$gen($currMagical)
        let $fwdId = $opticsId.$accessForward$gen($currMagical, $(commaSeparated(args)))
        let $bwdId = $opticsId.$accessBackward$gen($currMagical, $(commaSeparated(args)))
    )
}

/// Returns the next magical expression for an affine method segment, referencing
/// the local `__magical${index}` binding (bound by `emitUserDefinedLeafBindings`).
func userDefinedNextMagicalExpr(index: Int64, name: Token, targs: ArrayList<TypeNode>): Tokens {
    let currMagical = Token(IDENTIFIER, "__magical${index}")
    let accessMagic = Token(IDENTIFIER, "__method_${name.value}_optics")
    let gen = generics(targs)
    quote($currMagical.$accessMagic$gen($currMagical))
}

/// Emits `let __magicalI = ...; let __nmagicI = ...; let __opticsI = ...;
/// let __fwdI = ...; let __bwdI = ...` for a coerce (iso) segment. The coerce
/// impl members take BOTH the source and the target registry; the target
/// registry is `magic<Target>()`, which also becomes the next segment's
/// magical expression.
func emitCoerceLeafBindings(index: Int64, targs: TypeNode, prevMagicalExpr: Tokens): Tokens {
    let currMagical = Token(IDENTIFIER, "__magical${index}")
    let nextMagical = Token(IDENTIFIER, "__nmagic${index}")
    let opticsId    = Token(IDENTIFIER, "__optics${index}")
    let fwdId       = Token(IDENTIFIER, "__fwd${index}")
    let bwdId       = Token(IDENTIFIER, "__bwd${index}")
    quote(
        let $currMagical = $prevMagicalExpr
        let $nextMagical = $magicCallexprId<$targs>()
        let $opticsId = $downcastMethodCoerceId($currMagical, $nextMagical)
        let $fwdId = $opticsId.$coerceForwardId($currMagical, $nextMagical)
        let $bwdId = $opticsId.$coerceBackwardId($currMagical, $nextMagical)
    )
}