macro package lucida.macrodsl

import std.ast.*
import std.collection.*

let opticFieldNames = ["source", "focus", "kind", "args", "forward", "backward"]
let opticKindNames = ["Lens", "Prism", "Affine", "Iso"]

private func isOpticFieldStart(toks: ArrayList<Token>, i: Int64): Bool {
    if (i + 1 >= toks.size) { return false }
    let t = toks[i]
    return t.kind == TokenKind.IDENTIFIER && opticFieldNames.contains(t.value) &&
        toks[i + 1].kind == TokenKind.COLON
}

/// Splits the bracket attribute into (fieldName, valueTokens) pairs. Values may
/// contain any tokens; nesting depth of (), {}, [] is tracked so a value ends at
/// the next top-level `name:` prefix.
private func splitOpticFields(attr: Tokens): ArrayList<(Token, Tokens)> {
    let toks = ArrayList<Token>()
    attr |> forEach { t: Token => toks.add(t) }
    let fields = ArrayList<(Token, Tokens)>()
    var i: Int64 = 0
    while (i < toks.size) {
        if (!isOpticFieldStart(toks, i)) {
            throw DiagReportException(
                "@LucidaOptic: unexpected token in fields",
                toks[i].toTokens(),
                hint: "Expected one of: source:, focus:, kind:, args:, forward:, backward:"
            )
        }
        let name = toks[i]
        i += 2
        let value = ArrayList<Token>()
        var depth: Int64 = 0
        while (i < toks.size) {
            if (depth == 0 && isOpticFieldStart(toks, i)) { break }
            let v = toks[i]
            match (v.kind) {
                case TokenKind.LPAREN | TokenKind.LCURL | TokenKind.LSQUARE => depth += 1
                case TokenKind.RPAREN | TokenKind.RCURL | TokenKind.RSQUARE => depth -= 1
                case _ => ()
            }
            value.add(v)
            i += 1
        }
        while (!value.isEmpty() && (value[value.size - 1].kind == TokenKind.COMMA || value[value.size - 1].kind == TokenKind.NL)) {
            value.remove(at: value.size - 1)
        }
        while (!value.isEmpty() && value[0].kind == TokenKind.NL) {
            value.remove(at: 0)
        }
        if (value.isEmpty()) {
            throw DiagReportException(
                "@LucidaOptic: field '${name.value}' is empty", name.toTokens())
        }
        fields.add((name, Tokens(value)))
    }
    return fields
}

private func getField(fields: ArrayList<(Token, Tokens)>, name: String): ?Tokens {
    for (p in fields) {
        let (fname, fvalue) = p
        if (fname.value == name) { return fvalue }
    }
    return None
}

private func requireSingleIdentifier(field: String, value: Tokens): Token {
    if (value.size != 1 || value[0].kind != TokenKind.IDENTIFIER) {
        throw DiagReportException(
            "@LucidaOptic: field '${field}' must be a single identifier", value)
    }
    return value[0]
}

/// Parses `args: (n: Int64, m: Bool)` by reusing real func-param parsing on a
/// fake declaration. Returns (name, typeTokens) pairs.
private func parseOpticArgs(value: Tokens): ArrayList<(Token, Tokens)> {
    let toks = ArrayList<Token>()
    value |> forEach { t: Token => toks.add(t) }
    var paramToks = toks
    if (toks.size >= 2 && toks[0].kind == TokenKind.LPAREN && toks[toks.size - 1].kind == TokenKind.RPAREN) {
        let inner = ArrayList<Token>()
        for (i in 1..toks.size - 1) {
            inner.add(toks[i])
        }
        paramToks = inner
    }
    let paramValue = Tokens(paramToks)
    let fd = match (parseDecl(quote(func __lucida_optic_args_probe($paramValue): Unit { }))) {
        case f: FuncDecl => f
        case _ => throw DiagReportException(
            "@LucidaOptic: cannot parse args list", value)
    }
    let out = ArrayList<(Token, Tokens)>()
    for (p in fd.funcParams) {
        if (p.identifier.value == "src" || p.identifier.value == "focus" || p.identifier.value == "_src") {
            throw DiagReportException(
                "@LucidaOptic: arg name '${p.identifier.value}' is reserved",
                p.toTokens(),
                hint: "src/_src/focus are fixed slots of the generated lambdas"
            )
        }
        out.add((p.identifier, p.paramType.toTokens()))
    }
    return out
}

/// Strips the outer `{ ... }` of a body field.
private func stripOuterBraces(field: String, value: Tokens): Tokens {
    let toks = ArrayList<Token>()
    value |> forEach { t: Token => toks.add(t) }
    if (toks.size < 2 || toks[0].kind != TokenKind.LCURL || toks[toks.size - 1].kind != TokenKind.RCURL) {
        throw DiagReportException(
            "@LucidaOptic: field '${field}' must be a { ... } block", value)
    }
    let inner = ArrayList<Token>()
    for (i in 1..toks.size - 1) {
        inner.add(toks[i])
    }
    return Tokens(inner)
}

/// Sourceless backwards (Prism/Iso) have no `src` slot. Scan only at brace
/// depth 0 of the body so nested lambdas that shadow `src` don't false-positive.
private func rejectSrcInSourcelessBackward(body: Tokens, kindTok: Token): Unit {
    let toks = ArrayList<Token>()
    body |> forEach { t: Token => toks.add(t) }
    var depth: Int64 = 0
    for (t in toks) {
        match (t.kind) {
            case TokenKind.LCURL => depth += 1
            case TokenKind.RCURL => depth -= 1
            case TokenKind.IDENTIFIER =>
                if (depth == 0 && t.value == "src") {
                    throw DiagReportException(
                        "@LucidaOptic: backward of kind '${kindTok.value}' has no src slot",
                        t.toTokens(),
                        hint: "Lens/Affine backwards receive src; Prism/Iso rebuild from focus"
                    )
                }
            case _ => ()
        }
    }
}

private func argParamTokens(args: ArrayList<(Token, Tokens)>): Tokens {
    let parts = args |> map { p: (Token, Tokens) =>
        let (pn, pt) = p
        quote($pn: $pt)
    } |> collectArray
    return commaSeparated(parts)
}

private func emitUserOptic(
    carrier: StructDecl,
    kindTok: Token,
    source: Tokens,
    focus: Tokens,
    args: ArrayList<(Token, Tokens)>,
    forwardBody: Tokens,
    backwardBody: Tokens
): Tokens {
    let name = carrier.identifier
    // `genericParam.parameters` yields bare identifiers without separator
    // commas (e.g. <T, U> -> ['T', 'U']), so comma-join explicitly; single
    // params are unaffected. Skips COMMA/NL defensively.
    let genHdr = if (carrier.isGenericDecl) {
        let parts = ArrayList<Tokens>()
        carrier.genericParam.parameters |> forEach { t: Token =>
            if (t.kind != TokenKind.COMMA && t.kind != TokenKind.NL) {
                parts.add(Tokens(ArrayList<Token>([t])))
            }
        }
        quote(<$(commaSeparated(parts))>)
    } else {
        quote()
    }

    let fwdId = Token(IDENTIFIER, "__method_${name.value}_impl_forward")
    let bwdId = Token(IDENTIFIER, "__method_${name.value}_impl_backward")
    let opticsId = Token(IDENTIFIER, "__method_${name.value}_optics")
    let downcastId = Token(IDENTIFIER, "__downcast_method_${name.value}")

    let argParams = argParamTokens(args)
    let sigTail = if (args.isEmpty()) {
        quote(_: $registryMainId<$source>)
    } else {
        quote(_: $registryMainId<$source>, $argParams)
    }

    let registryId = match (kindTok.value) {
        case "Lens" => registryLensId
        case "Iso" => registryIsoId
        case "Prism" => registryPrismId
        case _ => registryOptionalId // Affine
    }

    // Kind-exact signatures (spec v2). All members keep the method-optic
    // factory convention: take the registry + args, return the function value.
    let fwdType = match (kindTok.value) {
        case "Lens" | "Iso" => quote(($source) -> $focus)
        case _ => quote(($source) -> Option<$focus>)
    }
    let bwdType = match (kindTok.value) {
        case "Lens" | "Affine" => quote(($source, $focus) -> $source)
        case _ => quote(($focus) -> $source)
    }
    let fwdLambda = quote({ src: $source => $forwardBody })
    let bwdLambda = match (kindTok.value) {
        case "Lens" | "Affine" => quote({ src: $source, focus: $focus => $backwardBody })
        case _ => quote({ focus: $focus => $backwardBody })
    }

    return quote(
        extend $genHdr $registryId<$source> {
            public func $fwdId($sigTail): $fwdType {
                $fwdLambda
            }
            public func $bwdId($sigTail): $bwdType {
                $bwdLambda
            }
        }
        extend $genHdr $registryMainId<$source> {
            public func $opticsId(_: $registryMainId<$source>): $registryMainId<$focus> {
                $registryMainId<$focus>()
            }
            public func $downcastId(_: $registryMainId<$source>): $registryId<$source> {
                $registryId<$source>()
            }
        }
    )
}

public macro LucidaOptic(attr: Tokens, input: Tokens): Tokens {
    try {
        let decl = parseDecl(input)
        let carrier = match (decl) {
            case s: StructDecl => s
            case _ => throw DiagReportException(
                "@LucidaOptic: carrier must be a struct declaration", input,
                hint: "Use: @LucidaOptic[fields] struct Name<T> {}")
        }
        if (carrier.body.decls.size != 0) {
            throw DiagReportException(
                "@LucidaOptic: carrier struct must be empty",
                carrier.identifier.toTokens(),
                hint: "The struct only carries the optic name and type parameters")
        }
        if (carrier.genericConstraint.size != 0) {
            throw DiagReportException(
                "@LucidaOptic: generic constraints ('where' clauses) are not supported",
                carrier.identifier.toTokens(),
                hint: "Remove the constraint or hand-write the optics")
        }
        let fields = splitOpticFields(attr)

        let kindValue = getField(fields, "kind") ?? throw DiagReportException(
            "@LucidaOptic: missing required field 'kind'", carrier.identifier.toTokens())
        let kindTok = requireSingleIdentifier("kind", kindValue)
        if (!opticKindNames.contains(kindTok.value)) {
            throw DiagReportException(
                "@LucidaOptic: unknown kind '${kindTok.value}'", kindTok.toTokens(),
                hint: "kind must be one of: Lens, Prism, Affine, Iso")
        }

        let source = getField(fields, "source") ?? throw DiagReportException(
            "@LucidaOptic: missing required field 'source'", carrier.identifier.toTokens())
        let focus = getField(fields, "focus") ?? throw DiagReportException(
            "@LucidaOptic: missing required field 'focus'", carrier.identifier.toTokens())

        let forwardValue = getField(fields, "forward") ?? throw DiagReportException(
            "@LucidaOptic: missing required field 'forward'", carrier.identifier.toTokens())
        let forward = stripOuterBraces("forward", forwardValue)
        let backwardValue = getField(fields, "backward") ?? throw DiagReportException(
            "@LucidaOptic: missing required field 'backward'", carrier.identifier.toTokens())
        let backward = stripOuterBraces("backward", backwardValue)

        let args = match (getField(fields, "args")) {
            case Some(v) => parseOpticArgs(v)
            case None => ArrayList<(Token, Tokens)>()
        }

        if (kindTok.value == "Prism" || kindTok.value == "Iso") {
            rejectSrcInSourcelessBackward(backward, kindTok)
        }

        let generated = emitUserOptic(carrier, kindTok, source, focus, args, forward, backward)
        quote(
            $decl
            $generated
        )
    } catch (e: DiagReportException) {
        diagReport(DiagReportLevel.ERROR, e.tokens, e.message, e.hint)
        quote($input)
    }
}
