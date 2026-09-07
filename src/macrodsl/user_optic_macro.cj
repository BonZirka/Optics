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

/// A body is *param-form* when it starts with `IDENT|_ (, IDENT|_)* =>`:
/// those names bind the kind's slots positionally (source first, then focus)
/// and the remainder is the body. Returns the names and the remainder, or
/// None for a bare body. `_` names a slot to skip. Leading newlines and
/// newlines around commas are tolerated.
private func parseSlotRenames(body: Tokens): ?(ArrayList<Token>, Tokens) {
    let toks = ArrayList<Token>()
    body |> forEach { t: Token => toks.add(t) }
    var i: Int64 = 0
    while (i < toks.size && toks[i].kind == TokenKind.NL) { i += 1 }
    if (i >= toks.size || !(toks[i].kind == TokenKind.IDENTIFIER || toks[i].value == "_")) {
        return None
    }
    let names = ArrayList<Token>()
    while (i < toks.size && (toks[i].kind == TokenKind.IDENTIFIER || toks[i].value == "_")) {
        names.add(toks[i])
        i += 1
        while (i < toks.size && toks[i].kind == TokenKind.NL) { i += 1 }
        if (i < toks.size && toks[i].kind == TokenKind.COMMA) {
            i += 1
            while (i < toks.size && toks[i].kind == TokenKind.NL) { i += 1 }
        } else {
            break
        }
    }
    if (i >= toks.size || toks[i].value != "=>") {
        return None
    }
    let rest = ArrayList<Token>()
    for (j in i+1..toks.size) { rest.add(toks[j]) }
    while (!rest.isEmpty() && rest[0].kind == TokenKind.NL) { rest.remove(at: 0) }
    return Some((names, Tokens(rest)))
}

/// One generated lambda parameter for a slot rename: the user's name, or
/// `_ : T` for a skipped slot.
private func slotParam(name: Token, ty: Tokens): Tokens {
    if (name.value == "_") { return quote(_ : $ty) }
    return quote($name: $ty)
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
    let genHdr = carrierGenHdr(carrier)

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
    let fwdLambda = buildUserFwdLambda(kindTok.value, source, focus, forwardBody)
    let bwdLambda = buildUserBwdLambda(kindTok.value, source, focus, backwardBody)

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
        let parsed = parseOpticDeclFields(attr, input)
        let generated = emitUserOptic(carrier, parsed.kind, parsed.source, parsed.focus, parsed.args, parsed.forward, parsed.backward)
        quote(
            $decl
            $generated
        )
    } catch (e: DiagReportException) {
        diagReport(DiagReportLevel.ERROR, e.tokens, e.message, e.hint)
        quote($input)
    }
}

/// Builds the forward member body (lambda) for a user optic of the given kind.
/// Shared by the standalone @Optic emission and the @Optics namespace emission.
func buildUserFwdLambda(kind: String, source: Tokens, _: Tokens, forwardBody: Tokens): Tokens {
// Bind a slot only when the body uses it; otherwise name the parameter _
// so no unused-variable warning is emitted for user bodies like
// `forward: { 1 }` or single-field `backward: { GBox(focus) }`.
// Param-form bodies (`{ s => ... }`, `{ s, f => ... }`) bind their names
// positionally to the kind's slots and replace the fixed slots entirely;
// bare bodies keep fixed slots with auto-`_` naming for unused ones.
let isSourceful = kind == "Lens" || kind == "Affine"
let bwdSlotCount: Int64 = if (isSourceful) { 2 } else { 1 }
let (fwdParam, fwdRest): (Tokens, Tokens) = match (parseSlotRenames(forwardBody)) {
    case Some((names, rest)) =>
        if (names.size != 1) {
            throw DiagReportException(
                "@Optic: forward binds ${names.size} names but this kind has 1 slots",
                forwardBody,
                hint: "Use _ to skip a slot")
        }
        (slotParam(names[0], quote($source)), rest)
    case None =>
        let p = if (referencesAtAnyDepth(forwardBody, "source")) {
            quote(source: $source)
        } else {
            quote(_ : $source)
        }
        (p, forwardBody)
}
return quote({ $fwdParam => $fwdRest })
}

/// Builds the backward member body (lambda) for a user optic of the given kind.
/// Shared by the standalone @Optic emission and the @Optics namespace emission.
func buildUserBwdLambda(kind: String, source: Tokens, focus: Tokens, backwardBody: Tokens): Tokens {
    let isSourceful = kind == "Lens" || kind == "Affine"
    let bwdSlotCount: Int64 = if (isSourceful) { 2 } else { 1 }
    return match (parseSlotRenames(backwardBody)) {
    case Some((names, rest)) =>
        if (names.size != bwdSlotCount) {
            if (!isSourceful && names.size == 2) {
                throw DiagReportException(
                    "@Optic: backward of kind '${kind}' has no source slot",
                    backwardBody,
                    hint: "Lens/Affine backwards receive source; Prism/Iso rebuild from focus")
            }
            throw DiagReportException(
                "@Optic: backward binds ${names.size} names but this kind has ${bwdSlotCount} slots",
                backwardBody,
                hint: "Use _ to skip a slot")
        }
        if (isSourceful) {
            quote({ $(slotParam(names[0], quote($source))), $(slotParam(names[1], quote($focus))) => $rest })
        } else {
            quote({ $(slotParam(names[0], quote($focus))) => $rest })
        }
    case None =>
        let lam = match (kind) {
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
        if (!isSourceful) {
            rejectSourceInSourcelessBackward(backwardBody, Token(IDENTIFIER, kind))
        }
        lam
}
}

/// Comma-joins the carrier's generic parameters into a `<T, U>` header.
func carrierGenHdr(carrier: StructDecl): Tokens {
// `genericParam.parameters` yields bare identifiers without separator
// commas (e.g. <T, U> -> ['T', 'U']), so comma-join explicitly; single
// params are unaffected. Skips COMMA/NL defensively.
return if (carrier.isGenericDecl) {
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
}

// ===== @Optics namespaces =====
//
// A namespace collects several user optics in one declaration:
//
//   @Optics({
//       @Lens[source: String, focus: Int64, forward: { ... }, backward: { ... }]
//       struct slen {}
//       @Lens[source: Array<Int64>, ...]
//       struct slen {}
//   })
//
// The kind attributes expand bottom-up (inner before outer) and leave a
// `@__OpticDecl[kind: K, ...fields]` marker on their declaration for the
// namespace macro to read, so every optic is validated before @Optics sees
// it. Optics sharing a name get ONE pair of unified interfaces
// (`__<name>_impl`, `__<name>_accessors`) with one conformance per
// declaration — that is what lets same-named optics over different source
// types coexist in one package (the per-optic emission of @Optic would
// redeclare the carrier and the interfaces). Same-named optics must still
// differ in source type: two declarations for one source would collide on
// the dispatch members.

struct ParsedOptic {
    let kind: Token
    let source: Tokens
    let focus: Tokens
    let args: ArrayList<(Token, Tokens)>
    let forward: Tokens
    let backward: Tokens

    init(kind: Token, source: Tokens, focus: Tokens, args: ArrayList<(Token, Tokens)>,
         forward: Tokens, backward: Tokens) {
        this.kind = kind
        this.source = source
        this.focus = focus
        this.args = args
        this.forward = forward
        this.backward = backward
    }
}

func parseOpticDeclFields(attr: Tokens, whereToks: Tokens): ParsedOptic {
    let fields = splitOpticFields(attr)
    let kindValue = getField(fields, "kind") ?? throw DiagReportException(
        "@Optic: missing required field 'kind'", whereToks)
    let kindTok = requireSingleIdentifier("kind", kindValue)
    if (!opticKindNames.contains(kindTok.value)) {
        throw DiagReportException(
            "@Optic: unknown kind '${kindTok.value}'", kindTok.toTokens(),
            hint: "kind must be one of: Lens, Prism, Affine, Iso")
    }
    let source = getField(fields, "source") ?? throw DiagReportException(
        "@Optic: missing required field 'source'", whereToks)
    let focus = getField(fields, "focus") ?? throw DiagReportException(
        "@Optic: missing required field 'focus'", whereToks)
    let forwardValue = getField(fields, "forward") ?? throw DiagReportException(
        "@Optic: missing required field 'forward'", whereToks)
    let backwardValue = getField(fields, "backward") ?? throw DiagReportException(
        "@Optic: missing required field 'backward'", whereToks)
    let args = match (getField(fields, "args")) {
        case Some(v) => parseOpticArgs(v)
        case None => ArrayList<(Token, Tokens)>()
    }
    return ParsedOptic(kindTok, source, focus, args,
        stripOuterBraces("forward", forwardValue), stripOuterBraces("backward", backwardValue))
}

public macro Lens(attr: Tokens, input: Tokens): Tokens {
    emitOpticNamespaceEntry("Lens", attr, input)
}

public macro Prism(attr: Tokens, input: Tokens): Tokens {
    emitOpticNamespaceEntry("Prism", attr, input)
}

public macro Affine(attr: Tokens, input: Tokens): Tokens {
    emitOpticNamespaceEntry("Affine", attr, input)
}

public macro Iso(attr: Tokens, input: Tokens): Tokens {
    emitOpticNamespaceEntry("Iso", attr, input)
}

private func emitOpticNamespaceEntry(kind: String, attr: Tokens, input: Tokens): Tokens {
    if (!insideParentContext("Optics")) {
        diagReport(
            DiagReportLevel.ERROR,
            input,
            "@${kind} must be used inside an @Optics block",
            "Move the declaration into @Optics({ ... }), or declare it standalone with @Optic[kind: ${kind}, ...]")
        return quote($input)
    }
    let kindTok = Token(IDENTIFIER, kind)
    return quote(
        @__OpticDecl[kind: $kindTok, $attr]
        $input
    )
}

public macro Optics(input: Tokens): Tokens {
    try {
        let toks = ArrayList<Token>()
        input |> forEach { t: Token => toks.add(t) }
        var i: Int64 = 0
        while (i < toks.size && toks[i].kind == TokenKind.NL) { i += 1 }
        if (i >= toks.size || toks[i].kind != TokenKind.LCURL) {
            throw DiagReportException("@Optics: expected a block of optic declarations", input)
        }
        i += 1
        let end = toks.size - 1
        let optics = ArrayList<(StructDecl, ParsedOptic)>()
        while (i < end) {
            if (toks[i].kind == TokenKind.NL) { i += 1; continue }
            if (!(toks[i].value == "@" && i + 1 < end && toks[i + 1].value == "__OpticDecl")) {
                throw DiagReportException(
                    "@Optics: unexpected content in the block", toks[i].toTokens(),
                    hint: "Each entry must be a kind-attributed struct: @Lens[...] struct name<T> {}")
            }
            i += 2
            while (i < end && toks[i].kind == TokenKind.NL) { i += 1 }
            if (i >= end || toks[i].kind != TokenKind.LSQUARE) {
                throw DiagReportException("@Optics: malformed optic marker", toks[i].toTokens())
            }
            let attrToks = ArrayList<Token>()
            var depth: Int64 = 0
            i += 1
            while (i < end) {
                let t = toks[i]
                if (depth == 0 && t.kind == TokenKind.RSQUARE) { break }
                match (t.kind) {
                    case TokenKind.LPAREN | TokenKind.LCURL | TokenKind.LSQUARE => depth += 1
                    case TokenKind.RPAREN | TokenKind.RCURL | TokenKind.RSQUARE => depth -= 1
                    case _ => ()
                }
                attrToks.add(t)
                i += 1
            }
            i += 1
            while (i < end && toks[i].kind == TokenKind.NL) { i += 1 }
            if (i >= end || toks[i].value != "struct") {
                throw DiagReportException(
                    "@Optics: expected a struct declaration after the optic marker", toks[i].toTokens())
            }
            let declStart = i
            i += 1
            if (i >= end || toks[i].kind != TokenKind.IDENTIFIER) {
                throw DiagReportException("@Optics: expected the optic name", toks[i].toTokens())
            }
            i += 1
            while (i < end && toks[i].kind == TokenKind.NL) { i += 1 }
            if (i < end && toks[i].value == "<") {
                var angle: Int64 = 0
                while (i < end) {
                    if (toks[i].value == "<") { angle += 1 }
                    if (toks[i].value == ">") {
                        angle -= 1
                        if (angle == 0) { i += 1; break }
                    }
                    i += 1
                }
                while (i < end && toks[i].kind == TokenKind.NL) { i += 1 }
            }
            if (i >= end || toks[i].kind != TokenKind.LCURL) {
                throw DiagReportException("@Optics: expected '{' in the carrier struct", toks[i].toTokens())
            }
            i += 1
            while (i < end && toks[i].kind == TokenKind.NL) { i += 1 }
            if (i >= end || toks[i].kind != TokenKind.RCURL) {
                throw DiagReportException(
                    "@Optics: the carrier struct must be empty", toks[i].toTokens(),
                    hint: "The struct only carries the optic name and type parameters")
            }
            i += 1
            let declToks = ArrayList<Token>()
            for (j in declStart..i) { declToks.add(toks[j]) }
            let decl = parseDecl(Tokens(declToks))
            let carrier = match (decl) {
                case s: StructDecl => s
                case _ => throw DiagReportException(
                    "@Optics: carrier must be a struct declaration", toks[declStart].toTokens())
            }
            if (carrier.body.decls.size != 0) {
                throw DiagReportException(
                    "@Optics: carrier struct must be empty", carrier.identifier.toTokens(),
                    hint: "The struct only carries the optic name and type parameters")
            }
            if (carrier.genericConstraint.size != 0) {
                throw DiagReportException(
                    "@Optics: generic constraints ('where' clauses) are not supported",
                    carrier.identifier.toTokens(),
                    hint: "Remove the constraint or hand-write the optics")
            }
            optics.add((carrier, parseOpticDeclFields(Tokens(attrToks), input)))
        }
        return emitOpticsNamespace(optics)
    } catch (e: DiagReportException) {
        diagReport(DiagReportLevel.ERROR, e.tokens, e.message, e.hint)
        return quote($input)
    }
}

private func argsSignature(args: ArrayList<(Token, Tokens)>): String {
    let sb = StringBuilder()
    for (p in args) {
        let (aname, aty) = p
        sb.append(aname.value)
        sb.append(":")
        aty |> forEach { t: Token => sb.append(t.value) }
        sb.append(";")
    }
    return sb.toString()
}

private func sourceSignature(source: Tokens): String {
    let sb = StringBuilder()
    source |> forEach { t: Token =>
        if (t.kind != TokenKind.NL) { sb.append(t.value) }
    }
    return sb.toString()
}

private func emitOpticsNamespace(optics: ArrayList<(StructDecl, ParsedOptic)>): Tokens {
    let names = ArrayList<Token>()
    let groups = ArrayList<ArrayList<(StructDecl, ParsedOptic)>>()
    for (p in optics) {
        let name = p[0].identifier
        var found = false
        for (g in 0..names.size) {
            if (names[g].value == name.value) {
                groups[g].add(p)
                found = true
                break
            }
        }
        if (!found) {
            names.add(name)
            let g = ArrayList<(StructDecl, ParsedOptic)>()
            g.add(p)
            groups.add(g)
        }
    }
    var out = quote()
    for (g in 0..names.size) {
        out = quote($out $(emitOpticNameGroup(names[g], groups[g])))
    }
    return out
}

private func emitOpticNameGroup(name: Token, decls: ArrayList<(StructDecl, ParsedOptic)>): Tokens {
    let firstArgs = argsSignature(decls[0][1].args)
    let seenSources = ArrayList<String>()
    let seenKinds = ArrayList<String>()
    for (p in decls) {
        let parsed = p[1]
        if (argsSignature(parsed.args) != firstArgs) {
            throw DiagReportException(
                "@Optics: optics named '${name.value}' declare different args", name.toTokens(),
                hint: "Same-named optics must share the argument list so chains can dispatch")
        }
        let src = sourceSignature(parsed.source)
        var idx = -1
        for (k in 0..seenSources.size) {
            if (seenSources[k] == src) { idx = k; break }
        }
        if (idx >= 0) {
            if (seenKinds[idx] != parsed.kind.value) {
                throw DiagReportException(
                    "@Optics: optics named '${name.value}' for source '${src}' have different kinds",
                    name.toTokens(),
                    hint: "The dispatch members would collide; rename one of the optics")
            }
            throw DiagReportException(
                "@Optics: optic '${name.value}' is declared more than once for source '${src}'",
                name.toTokens())
        }
        seenSources.add(src)
        seenKinds.add(parsed.kind.value)
    }

    let fwdId = Token(IDENTIFIER, "__method_${name.value}_impl_forward")
    let bwdId = Token(IDENTIFIER, "__method_${name.value}_impl_backward")
    let opticsId = Token(IDENTIFIER, "__method_${name.value}_optics")
    let downcastId = Token(IDENTIFIER, "__downcast_method_${name.value}")
    let implIface = Token(IDENTIFIER, "__${name.value}_impl")
    let accIface = Token(IDENTIFIER, "__${name.value}_accessors")
    let sP = Token(IDENTIFIER, "S")
    let fP = Token(IDENTIFIER, "F")
    let tfP = Token(IDENTIFIER, "T_F")
    let tbP = Token(IDENTIFIER, "T_B")
    let dP = Token(IDENTIFIER, "D")

    let firstArgsList = decls[0][1].args
    let groupSigTail = if (firstArgsList.isEmpty()) {
        quote(_: $registryMainId<$sP>)
    } else {
        quote(_: $registryMainId<$sP>, $(argParamTokens(firstArgsList)))
    }
    var out = quote(
        sealed interface $implIface<$sP, $tfP, $tbP> {
            @Frozen
            func $fwdId($groupSigTail): $tfP
            @Frozen
            func $bwdId($groupSigTail): $tbP
        }
        sealed interface $accIface<$sP, $fP, $dP> {
            @Frozen
            func $opticsId(_: $registryMainId<$sP>): $registryMainId<$fP>
            @Frozen
            func $downcastId(_: $registryMainId<$sP>): $dP
        }
    )
    for (p in decls) {
        let (carrier, parsed) = p
        let genHdr = carrierGenHdr(carrier)
        let registryId = match (parsed.kind.value) {
            case "Lens" => registryLensId
            case "Iso" => registryIsoId
            case "Prism" => registryPrismId
            case _ => registryOptionalId // Affine
        }
        let fwdLambda = buildUserFwdLambda(parsed.kind.value, parsed.source, parsed.focus, parsed.forward)
        let bwdLambda = buildUserBwdLambda(parsed.kind.value, parsed.source, parsed.focus, parsed.backward)
        let fwdFn = match (parsed.kind.value) {
            case "Lens" | "Iso" => quote(($(parsed.source)) -> $(parsed.focus))
            case _ => quote(($(parsed.source)) -> Option<$(parsed.focus)>)
        }
        let bwdFn = match (parsed.kind.value) {
            case "Lens" | "Affine" => quote(($(parsed.source), $(parsed.focus)) -> $(parsed.source))
            case _ => quote(($(parsed.focus)) -> $(parsed.source))
        }
        let paramsTail = if (parsed.args.isEmpty()) {
            quote(_: $registryMainId<$(parsed.source)>)
        } else {
            quote(_: $registryMainId<$(parsed.source)>, $(argParamTokens(parsed.args)))
        }
        out = quote(
            $out
            extend $genHdr $registryId<$(parsed.source)> <: $implIface<$(parsed.source), $fwdFn, $bwdFn> {
                @Frozen
                public func $fwdId($paramsTail): $fwdFn {
                    $fwdLambda
                }
                @Frozen
                public func $bwdId($paramsTail): $bwdFn {
                    $bwdLambda
                }
            }
            extend $genHdr $registryMainId<$(parsed.source)> <: $accIface<$(parsed.source), $(parsed.focus), $registryId<$(parsed.source)>> {
                @Frozen
                public func $opticsId(_: $registryMainId<$(parsed.source)>): $registryMainId<$(parsed.focus)> {
                    $registryMainId<$(parsed.focus)>()
                }
                @Frozen
                public func $downcastId(_: $registryMainId<$(parsed.source)>): $registryId<$(parsed.source)> {
                    $registryId<$(parsed.source)>()
                }
            }
        )
    }
    return out
}
