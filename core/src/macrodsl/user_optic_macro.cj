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
private func splitOpticFields(macroName: String, attr: Tokens): ArrayList<(Token, Tokens)> {
    let toks = ArrayList<Token>()
    attr |> forEach { t: Token => toks.add(t) }
    let fields = ArrayList<(Token, Tokens)>()
    var i: Int64 = 0
    while (i < toks.size) {
        if (!isOpticFieldStart(toks, i)) {
            throw DiagReportException(
                "@${macroName}: unexpected token in fields",
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
                "@${macroName}: field '${name.value}' is empty", name.toTokens())
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

private func requireSingleIdentifier(macroName: String, field: String, value: Tokens): Token {
    if (value.size != 1 || value[0].kind != TokenKind.IDENTIFIER) {
        throw DiagReportException(
            "@${macroName}: field '${field}' must be a single identifier", value)
    }
    return value[0]
}

/// Parses `args: (n: Int64, m: Bool)` by reusing real func-param parsing on a
/// fake declaration. Returns (name, typeTokens) pairs.
private func parseOpticArgs(macroName: String, value: Tokens): ArrayList<(Token, Tokens)> {
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
            "@${macroName}: cannot parse args list", value)
    }
    let out = ArrayList<(Token, Tokens)>()
    for (p in fd.funcParams) {
        if (p.identifier.value == "source" || p.identifier.value == "focus" || p.identifier.value == "_source") {
            throw DiagReportException(
                "@${macroName}: arg name '${p.identifier.value}' is reserved",
                p.toTokens(),
                hint: "source/_source/focus are fixed slots of the generated lambdas"
            )
        }
        out.add((p.identifier, p.paramType.toTokens()))
    }
    return out
}

/// Strips the outer `{ ... }` of a body field.
private func stripOuterBraces(macroName: String, field: String, value: Tokens): Tokens {
    let toks = ArrayList<Token>()
    value |> forEach { t: Token => toks.add(t) }
    if (toks.size < 2 || toks[0].kind != TokenKind.LCURL || toks[toks.size - 1].kind != TokenKind.RCURL) {
        throw DiagReportException(
            "@${macroName}: field '${field}' must be a { ... } block", value)
    }
    let inner = ArrayList<Token>()
    for (i in 1..toks.size - 1) {
        inner.add(toks[i])
    }
    return Tokens(inner)
}

/// Sourceless backwards (Prism/Iso) have no `source` slot. Scan only at brace
/// depth 0 of the body so nested lambdas that shadow `source` don't false-positive.
private func rejectSourceInSourcelessBackward(macroName: String, body: Tokens, kindTok: Token): Unit {
    if (referencesAtDepth0(body, "source")) {
        throw DiagReportException(
            "@${macroName}: backward of kind '${kindTok.value}' has no source slot",
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
    macroName: String,
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
    let fwdLambda = buildUserFwdLambda(macroName, kindTok.value, source, focus, forwardBody)
    let bwdLambda = buildUserBwdLambda(macroName, kindTok.value, source, focus, backwardBody)

    // Cross-package visibility: cjc only imports extension members that
    // come through interface conformance — a plain `extend` block's members
    // stay package-local (same shape @DeriveOptics emits). Each optic gets
    // three sealed interfaces named after the carrier: impl members conformed
    // by the kind registry, optics and downcast members conformed by
    // RegistryMagical (split so neither conforming type faces members it
    // does not own).
    let implIfaceId = mangleUserIface("impl", name, kindTok, source, focus, args)
    let accIfaceId = mangleUserIface("accessors", name, kindTok, source, focus, args)
    let downIfaceId = mangleUserIface("downcast", name, kindTok, source, focus, args)

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


// The interface-name mangle. An optic's three generated interfaces are named
// after its full signature (kind, source, focus, args) rather than after the
// optic's name alone, so two declarations reusing one name over different
// shapes get distinct interfaces instead of colliding on one.
//
// The mangled text is spliced into the generated source, so it must be a
// plain Cangjie identifier. Every byte outside [A-Za-z0-9] is escaped: '_'
// becomes _u, and anything else becomes _x plus two lowercase hex digits
// (so Array<T> mangles to Array_x3cT_x3e). Because no byte of the signature
// can ever produce a bare '_', the literal separators in the name below
// cannot be forged, and the encoding is injective -- two different
// signatures cannot end up sharing an interface name. Token boundaries are
// deliberately not encoded: spellings that differ only in tokenization name
// the same optic and should mangle identically.
private func mangleHexDigit(nibble: UInt8): UInt8 {
    return if (nibble < 10) { 48 + nibble } else { 87 + nibble }
}

/// Encodes tokens into an identifier-safe string. `[A-Za-z0-9]` pass through,
/// `_` becomes `_u`, and any other byte becomes `_x` plus two lowercase hex
/// digits. The scheme is prefix-free, so it is injective and two distinct
/// signatures can never produce the same name.
///
/// Whitespace is canonicalised rather than encoded: a run of space/tab bytes
/// collapses to a single `_x20`, and NL tokens are dropped outright, so a type
/// written across two lines mangles the same as one written inline. That keeps
/// generated identifiers — which surface verbatim in compiler errors — from
/// growing with the author's indentation.
private func mangleToks(toks: Tokens): String {
    let bytes = ArrayList<UInt8>()
    var pendingSpace = false
    for (t in toks) {
        if (t.kind == TokenKind.NL) {
            continue
        }
        let v = t.value
        if (v.size == 0) {
            continue
        }
        var allSpace = true
        for (i in 0..v.size) {
            if (v[i] != 32 && v[i] != 9) {
                allSpace = false
                break
            }
        }
        if (allSpace) {
            pendingSpace = true
            continue
        }
        if (pendingSpace) {
            bytes.add(95)
            bytes.add(120)
            bytes.add(50)
            bytes.add(48)
            pendingSpace = false
        }
        for (i in 0..v.size) {
            let b = v[i]
            if ((b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)) {
                bytes.add(b)
            } else if (b == 95) {
                bytes.add(95)
                bytes.add(117)
            } else if (b == 32 || b == 9) {
                if (i + 1 < v.size) {
                    bytes.add(95)
                    bytes.add(120)
                    bytes.add(50)
                    bytes.add(48)
                }
            } else {
                bytes.add(95)
                bytes.add(120)
                bytes.add(mangleHexDigit(b / 16))
                bytes.add(mangleHexDigit(b % 16))
            }
        }
    }
    return String.fromUtf8(bytes.toArray())
}

private func mangleUserIface(
    suffix: String, name: Token, kind: Token, source: Tokens, focus: Tokens,
    args: ArrayList<(Token, Tokens)>
): Token {
    let sb = StringBuilder()
    sb.append("__")
    sb.append(name.value)
    sb.append("_")
    sb.append(suffix)
    sb.append("_kind_")
    sb.append(kind.value)
    sb.append("_source_")
    sb.append(mangleToks(source))
    sb.append("_focus_")
    sb.append(mangleToks(focus))
    if (!args.isEmpty()) {
        sb.append("_args")
        for ((an, at) in args) {
            sb.append("_")
            sb.append(an.value)
            sb.append("_of_type_")
            sb.append(mangleToks(at))
        }
    }
    return Token(IDENTIFIER, sb.toString())
}

public macro Optic(attr: Tokens, input: Tokens): Tokens {
    expandUserOptic("Optic", "", attr, input)
}

/// Expands one user optic. `macroName` is the macro the user actually wrote, so
/// diagnostics blame `@Lens` rather than `@Optic` when an alias is used;
/// `kindOverride` is non-empty for the aliases, which fix the kind themselves.
private func expandUserOptic(macroName: String, kindOverride: String, attr: Tokens, input: Tokens): Tokens {
    try {
        let decl = parseDecl(input)
        let carrier = match (decl) {
            case s: StructDecl => s
            case _ => throw DiagReportException(
                "@${macroName}: carrier must be a struct declaration", input,
                hint: "Use: @${macroName}[fields] struct Name<T> {}")
        }
        if (carrier.body.decls.size != 0) {
            throw DiagReportException(
                "@${macroName}: carrier struct must be empty",
                carrier.identifier.toTokens(),
                hint: "The struct only carries the optic name and type parameters")
        }
        if (carrier.genericConstraint.size != 0) {
            throw DiagReportException(
                "@${macroName}: generic constraints ('where' clauses) are not supported",
                carrier.identifier.toTokens(),
                hint: "Remove the constraint or hand-write the optics")
        }
        let parsed = parseOpticDeclFields(macroName, attr, input, kindOverride)
        let generated = emitUserOptic(macroName, carrier, parsed.kind, parsed.source, parsed.focus, parsed.args, parsed.forward, parsed.backward)
        quote($generated)
    } catch (e: DiagReportException) {
        println("@ODIAG: ${e.message}")
        reportCaughtDiag(e.tokens, e.message, e.hint)
        quote($input)
    }
}

/// Builds the forward member body (lambda) for a user optic of the given kind.
/// Shared by every user-optic emission.
func buildUserFwdLambda(macroName: String, _: String, source: Tokens, _: Tokens, forwardBody: Tokens): Tokens {
// Bind a slot only when the body uses it; otherwise name the parameter _
// so no unused-variable warning is emitted for user bodies like
// `forward: { 1 }` or single-field `backward: { GBox(focus) }`.
// Param-form bodies (`{ s => ... }`, `{ s, f => ... }`) bind their names
// positionally to the kind's slots and replace the fixed slots entirely;
// bare bodies keep fixed slots with auto-`_` naming for unused ones.
let (fwdParam, fwdRest): (Tokens, Tokens) = match (parseSlotRenames(forwardBody)) {
    case Some((names, rest)) =>
        if (names.size != 1) {
            throw DiagReportException(
                "@${macroName}: forward binds ${names.size} names but this kind has 1 slots",
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
/// Shared by every user-optic emission.
func buildUserBwdLambda(macroName: String, kind: String, source: Tokens, focus: Tokens, backwardBody: Tokens): Tokens {
    let isSourceful = kind == "Lens" || kind == "Affine"
    let bwdSlotCount: Int64 = if (isSourceful) { 2 } else { 1 }
    return match (parseSlotRenames(backwardBody)) {
    case Some((names, rest)) =>
        if (names.size != bwdSlotCount) {
            if (!isSourceful && names.size == 2) {
                throw DiagReportException(
                    "@${macroName}: backward of kind '${kind}' has no source slot",
                    backwardBody,
                    hint: "Lens/Affine backwards receive source; Prism/Iso rebuild from focus")
            }
            throw DiagReportException(
                "@${macroName}: backward binds ${names.size} names but this kind has ${bwdSlotCount} slots",
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
            rejectSourceInSourcelessBackward(macroName, backwardBody, Token(IDENTIFIER, kind))
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

// ===== user optics =====
//
// A user optic is one kind-attributed carrier declaration:
//
//   @Lens[source: String, focus: Int64, forward: { ... }, backward: { ... }]
//   struct slen {}
//
// The carrier declaration is parsed for its optic name and generic parameters
// (carrierGenHdr) but never re-emitted: it carries no members and nothing
// references it as a type, so emitting it would only make the name a second
// collision point alongside the mangled interfaces.

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

func parseOpticDeclFields(macroName: String, attr: Tokens, whereToks: Tokens, kindOverride: String): ParsedOptic {
    let fields = splitOpticFields(macroName, attr)
    var kindTok: Token
    if (kindOverride != "") {
        if (getField(fields, "kind").isSome()) {
            throw DiagReportException(
                "@${macroName}: takes no 'kind' field", whereToks,
                hint: "@${macroName} already fixes the kind; drop the kind: field or use @Optic[kind: ...]")
        }
        kindTok = Token(IDENTIFIER, kindOverride)
    } else {
        let kindValue = getField(fields, "kind") ?? throw DiagReportException(
            "@${macroName}: missing required field 'kind'", whereToks,
            hint: "Or use the shorthand: @Lens/@Prism/@Affine/@Iso, which fix the kind for you")
        let k = requireSingleIdentifier(macroName, "kind", kindValue)
        if (!opticKindNames.contains(k.value)) {
            throw DiagReportException(
                "@${macroName}: unknown kind '${k.value}'", k.toTokens(),
                hint: "kind must be one of: Lens, Prism, Affine, Iso")
        }
        kindTok = k
    }
    let source = getField(fields, "source") ?? throw DiagReportException(
        "@${macroName}: missing required field 'source'", whereToks)
    let focus = getField(fields, "focus") ?? throw DiagReportException(
        "@${macroName}: missing required field 'focus'", whereToks)
    let forwardValue = getField(fields, "forward") ?? throw DiagReportException(
        "@${macroName}: missing required field 'forward'", whereToks)
    let backwardValue = getField(fields, "backward") ?? throw DiagReportException(
        "@${macroName}: missing required field 'backward'", whereToks)
    let args = match (getField(fields, "args")) {
        case Some(v) => parseOpticArgs(macroName, v)
        case None => ArrayList<(Token, Tokens)>()
    }
    return ParsedOptic(kindTok, source, focus, args,
        stripOuterBraces(macroName, "forward", forwardValue), stripOuterBraces(macroName, "backward", backwardValue))
}

// The kind macros are spelling sugar for @Optic[kind: <Kind>, ...]:
//
//   @Lens[source: String, focus: Int64, forward: { ... }, backward: { ... }]
//   struct slen {}
public macro Lens(attr: Tokens, input: Tokens): Tokens {
    emitKindAlias("Lens", attr, input)
}

public macro Prism(attr: Tokens, input: Tokens): Tokens {
    emitKindAlias("Prism", attr, input)
}

public macro Affine(attr: Tokens, input: Tokens): Tokens {
    emitKindAlias("Affine", attr, input)
}

public macro Iso(attr: Tokens, input: Tokens): Tokens {
    emitKindAlias("Iso", attr, input)
}

private func emitKindAlias(kind: String, attr: Tokens, input: Tokens): Tokens {
    expandUserOptic(kind, kind, attr, input)
}
