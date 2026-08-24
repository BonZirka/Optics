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
                "@Optic: unexpected token in fields",
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
                "@Optic: field '${name.value}' is empty", name.toTokens())
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
            "@Optic: field '${field}' must be a single identifier", value)
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
            "@Optic: cannot parse args list", value)
    }
    let out = ArrayList<(Token, Tokens)>()
    for (p in fd.funcParams) {
        if (p.identifier.value == "source" || p.identifier.value == "focus" || p.identifier.value == "_source") {
            throw DiagReportException(
                "@Optic: arg name '${p.identifier.value}' is reserved",
                p.toTokens(),
                hint: "source/_source/focus are fixed slots of the generated lambdas"
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
            "@Optic: field '${field}' must be a { ... } block", value)
    }
    let inner = ArrayList<Token>()
    for (i in 1..toks.size - 1) {
        inner.add(toks[i])
    }
    return Tokens(inner)
}

/// Sourceless backwards (Prism/Iso) have no `source` slot. Scan only at brace
/// depth 0 of the body so nested lambdas that shadow `source` don't false-positive.
private func rejectSourceInSourcelessBackward(body: Tokens, kindTok: Token): Unit {
    if (referencesAtDepth0(body, "source")) {
        throw DiagReportException(
            "@Optic: backward of kind '${kindTok.value}' has no source slot",
            body,
            hint: "Lens/Affine backwards receive source; Prism/Iso rebuild from focus"
        )
    }
}

/// True when `name` appears as a bare identifier at brace depth 0 of `body`.
/// Nested lambdas that shadow the name don't count.
private func referencesAtDepth0(body: Tokens, name: String): Bool {
    let toks = ArrayList<Token>()
    body |> forEach { t: Token => toks.add(t) }
    var depth: Int64 = 0
    for (t in toks) {
        match (t.kind) {
            case TokenKind.LCURL => depth += 1
            case TokenKind.RCURL => depth -= 1
            case TokenKind.IDENTIFIER =>
                if (depth == 0 && t.value == name) { return true }
            case _ => ()
        }
    }
    return false
}

/// True when `name` appears as a bare identifier anywhere in `body` — the
/// right predicate for naming the generated src/focus slots: a use inside
/// an `if` block or `match` arm is as much a use as one at the top level.
/// (Nested lambdas that rebind the name only cause over-naming, which is
/// harmless; the depth-0 variant is reserved for src-rejection, where
/// shadowing semantics matter.)
private func referencesAtAnyDepth(body: Tokens, name: String): Bool {
    let toks = ArrayList<Token>()
    body |> forEach { t: Token => toks.add(t) }
    for (t in toks) {
        if (t.kind == TokenKind.IDENTIFIER && t.value == name) { return true }
    }
    return false
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
    // Bind a slot only when the body uses it; otherwise name the parameter _
    // so no unused-variable warning is emitted for user bodies like
    // `forward: { 1 }` or single-field `backward: { GBox(focus) }`.
    let fwdParam: Tokens = if (referencesAtAnyDepth(forwardBody, "source")) {
        quote(source: $source)
    } else {
        quote(_ : $source)
    }
    let fwdLambda = quote({ $fwdParam => $forwardBody })
    let bwdLambda = match (kindTok.value) {
        case "Lens" | "Affine" =>
            let usesSrc = referencesAtAnyDepth(backwardBody, "source")
            let usesFocus = referencesAtAnyDepth(backwardBody, "focus")
            let srcP: Tokens = if (usesSrc) { quote(source: $source) } else { quote(_ : $source) }
            let fcsP: Tokens = if (usesFocus) { quote(focus: $focus) } else { quote(_ : $focus) }
            quote({ $srcP, $fcsP => $backwardBody })
        case _ =>
            let fcsP: Tokens = if (referencesAtAnyDepth(backwardBody, "focus")) {
                quote(focus: $focus)
            } else {
                quote(_ : $focus)
            }
            quote({ $fcsP => $backwardBody })
    }

    // Cross-package visibility: cjc only imports extension members that
    // come through interface conformance — a plain `extend` block's members
    // stay package-local (same shape @DeriveOptics emits). Each optic gets
    // three sealed interfaces named after the carrier: impl members conformed
    // by the kind registry, optics and downcast members conformed by
    // RegistryMagical (split so neither conforming type faces members it
    // does not own).
    let implIfaceId = Token(IDENTIFIER, "__${name.value}_optics_impl")
    let accIfaceId = Token(IDENTIFIER, "__${name.value}_suboptics_accessors")
    let downIfaceId = Token(IDENTIFIER, "__${name.value}_downcast")

    return quote(
        sealed interface $implIfaceId$genHdr {
            @Frozen
            func $fwdId($sigTail): $fwdType
            @Frozen
            func $bwdId($sigTail): $bwdType
        }
        sealed interface $accIfaceId$genHdr {
            @Frozen
            func $opticsId(_: $registryMainId<$source>): $registryMainId<$focus>
        }
        sealed interface $downIfaceId$genHdr {
            @Frozen
            func $downcastId(_: $registryMainId<$source>): $registryId<$source>
        }
        extend $genHdr $registryId<$source> <: $implIfaceId$genHdr {
            @Frozen
            public func $fwdId($sigTail): $fwdType {
                $fwdLambda
            }
            @Frozen
            public func $bwdId($sigTail): $bwdType {
                $bwdLambda
            }
        }
        extend $genHdr $registryMainId<$source> <: $accIfaceId$genHdr {
            @Frozen
            public func $opticsId(_: $registryMainId<$source>): $registryMainId<$focus> {
                $registryMainId<$focus>()
            }
        }
        extend $genHdr $registryMainId<$source> <: $downIfaceId$genHdr {
            @Frozen
            public func $downcastId(_: $registryMainId<$source>): $registryId<$source> {
                $registryId<$source>()
            }
        }
    )
}

public macro Optic(attr: Tokens, input: Tokens): Tokens {
    try {
        let decl = parseDecl(input)
        let carrier = match (decl) {
            case s: StructDecl => s
            case _ => throw DiagReportException(
                "@Optic: carrier must be a struct declaration", input,
                hint: "Use: @Optic[fields] struct Name<T> {}")
        }
        if (carrier.body.decls.size != 0) {
            throw DiagReportException(
                "@Optic: carrier struct must be empty",
                carrier.identifier.toTokens(),
                hint: "The struct only carries the optic name and type parameters")
        }
        if (carrier.genericConstraint.size != 0) {
            throw DiagReportException(
                "@Optic: generic constraints ('where' clauses) are not supported",
                carrier.identifier.toTokens(),
                hint: "Remove the constraint or hand-write the optics")
        }
        let fields = splitOpticFields(attr)

        let kindValue = getField(fields, "kind") ?? throw DiagReportException(
            "@Optic: missing required field 'kind'", carrier.identifier.toTokens())
        let kindTok = requireSingleIdentifier("kind", kindValue)
        if (!opticKindNames.contains(kindTok.value)) {
            throw DiagReportException(
                "@Optic: unknown kind '${kindTok.value}'", kindTok.toTokens(),
                hint: "kind must be one of: Lens, Prism, Affine, Iso")
        }

        let source = getField(fields, "source") ?? throw DiagReportException(
            "@Optic: missing required field 'source'", carrier.identifier.toTokens())
        let focus = getField(fields, "focus") ?? throw DiagReportException(
            "@Optic: missing required field 'focus'", carrier.identifier.toTokens())

        let forwardValue = getField(fields, "forward") ?? throw DiagReportException(
            "@Optic: missing required field 'forward'", carrier.identifier.toTokens())
        let forward = stripOuterBraces("forward", forwardValue)
        let backwardValue = getField(fields, "backward") ?? throw DiagReportException(
            "@Optic: missing required field 'backward'", carrier.identifier.toTokens())
        let backward = stripOuterBraces("backward", backwardValue)

        let args = match (getField(fields, "args")) {
            case Some(v) => parseOpticArgs(v)
            case None => ArrayList<(Token, Tokens)>()
        }

        if (kindTok.value == "Prism" || kindTok.value == "Iso") {
            rejectSourceInSourcelessBackward(backward, kindTok)
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
