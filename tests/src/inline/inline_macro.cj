macro package tests.inline

import std.ast.*
import std.collection.*
import std.env.*

let inlineMacroName = "@InlineOptics"


// Parameter names an inlining body binds. They match the parameter names user optics
// themselves are written against, so a `@Lens` body can be pasted into the
// registry verbatim.
let inlineSourceParam = "source"
let inlineFocusParam = "focus"
let inlineBodyKeyword = "body"

// ===== token cursor over a macro attribute =====

class InlineToks {
    private let toks: ArrayList<Token>
    var i: Int64 = 0

    init(input: Tokens) {
        toks = ArrayList<Token>()
        for (idx in 0..input.size) { toks.add(input[idx]) }
    }

    func done(): Bool {
        i >= toks.size
    }

    func raw(): ArrayList<Token> {
        toks
    }

    func at(kind: TokenKind): Bool {
        i < toks.size && toks[i].kind == kind
    }

    func atOffset(kind: TokenKind, n: Int64): Bool {
        i + n < toks.size && toks[i + n].kind == kind
    }

    func peek(): Token {
        toks[i]
    }

    func skipNL(): Unit {
        while (i < toks.size && toks[i].kind == TokenKind.NL) { i += 1 }
    }

    func bump(): Token {
        let t = toks[i]
        i += 1
        return t
    }

    func expect(kind: TokenKind, what: String): Token {
        skipNL()
        if (!at(kind)) {
            throw DiagReportException(
                "${inlineMacroName}: expected ${what}",
                curTokens(),
                hint: shapeHint()
            )
        }
        return bump()
    }

    /// Accepts any token that can stand for a name. Built-in type names such as
    /// `Int64` do not arrive as IDENTIFIER, so only structural punctuation is
    /// rejected outright.
    func expectName(what: String): String {
        skipNL()
        if (i >= toks.size) {
            throw DiagReportException("${inlineMacroName}: expected ${what}", curTokens(), hint: shapeHint())
        }
        let t = toks[i]
        match (t.kind) {
            case TokenKind.LPAREN | TokenKind.RPAREN | TokenKind.LCURL | TokenKind.RCURL |
                 TokenKind.LSQUARE | TokenKind.RSQUARE | TokenKind.COMMA | TokenKind.COLON |
                 TokenKind.NL | TokenKind.DOT | TokenKind.DOUBLE_ARROW =>
                throw DiagReportException(
                    "${inlineMacroName}: expected ${what}",
                    t.toTokens(),
                    hint: shapeHint()
                )
            case _ => ()
        }
        i += 1
        return t.value
    }

    /// A type name plus, for `Option<M>`, the inner name `M`.
    ///
    /// A partial slot `?.f` focuses the payload of an `Option`, so the shape
    /// table has to be able to say which type the chain continues on. Every
    /// other generic (`Array<Int64>`) is a leaf as far as rebuilding goes and
    /// its argument is dropped.
    func expectTypeName(): (String, ?String) {
        let base = expectName("a type name")
        if (i < toks.size && toks[i].value == "<") {
            var depth: Int64 = 0
            var first: String = ""
            var haveFirst: Bool = false
            while (i < toks.size) {
                let v = toks[i].value
                if (v == "<") {
                    depth += 1
                    i += 1
                    continue
                }
                if (v == ">") {
                    depth -= 1
                    i += 1
                    if (depth == 0) { break }
                    continue
                }
                if (depth == 1 && v == ",") {
                    // a second argument: the rest of the type is a leaf anyway
                    i = toks.size
                    break
                }
                if (depth == 1 && !haveFirst && !isPunct(v)) {
                    first = v
                    haveFirst = true
                }
                i += 1
            }
            if (base == "Option" && haveFirst) { return (base, Some(first)) }
        }
        return (base, None)
    }

    private func isPunct(v: String): Bool {
        v == "," || v == ")" || v == ">" || v == "("
    }

    func curTokens(): Tokens {
        if (i < toks.size) { return toks[i].toTokens() }
        return toks[toks.size - 1].toTokens()
    }
}

private func shapeHint(): String {
    "shapes: (TypeA, (field, FieldType), ...), (TypeB, ...) lists every type on the chain with "
    + "its fields in constructor order; an enum is (TypeE, (CaseName, (field, FieldType)), ...); "
    + "an Option field is written (field, Option<InnerType>) so a '?.' slot knows what it "
    + "focuses; root: TypeA names the source value's type; "
    + "registry: (opticName, OwnerType, field) inlines a first-class derived-field optic"
}

// ===== shape model =====

class InlineField {
    let name: String
    let typeName: String
    // `Some(M)` when the declared type is `Option<M>`: a `?.` slot on this
    // field focuses `M`, and the chain continues there rather than on `Option`.
    let optionInner: ?String

    init(name: String, typeName: String, optionInner: ?String) {
        this.name = name
        this.typeName = typeName
        this.optionInner = optionInner
    }
}

/// One enum case and its payload, in declaration order. An empty payload is a
/// payloadless case, whose focus is `()`.
/// How a payloadless focus is spelled as a value: `()`. As a type
/// argument it is `Unit`; `noneTokOf` translates.
private let focusUnitTypeName = "()"

class InlineCase {
    let name: String
    let fields: ArrayList<InlineField>

    init(name: String, fields: ArrayList<InlineField>) {
        this.name = name
        this.fields = fields
    }

    /// The case's focus type as the DSL sees it: `()` when payloadless, the
    /// single payload's type, or `(A, B)` for several.
    /// The type this case focuses: Unit for a payloadless case, the payload
    /// type for one field, a tuple for several.
    ///
    /// `typeName` spells a payloadless focus as `()` (matching the `Some(())`
    /// forward); `asTypeName` spells it as `Unit` for use as a type argument.
    func focusTypeName(): String {
        if (fields.size == 0) { return focusUnitTypeName }
        if (fields.size == 1) { return fields[0].typeName }
        var out = "("
        for (i in 0..fields.size) {
            if (i > 0) { out += ", " }
            out += fields[i].typeName
        }
        return out + ")"
    }

    func asTypeName(): String {
        if (fields.size == 0) { return "Unit" }
        return focusTypeName()
    }
}

class InlineShape {
    let name: String
    var isEnum: Bool = false
    let fields: ArrayList<InlineField>
    let cases: ArrayList<InlineCase>

    init(name: String, fields: ArrayList<InlineField>) {
        this.name = name
        this.fields = fields
        this.cases = ArrayList<InlineCase>()
    }

    func indexOf(name: String): Int64 {
        for (i in 0..fields.size) {
            if (fields[i].name == name) { return i }
        }
        return -1
    }

    func indexOfCase(name: String): Int64 {
        for (i in 0..cases.size) {
            if (cases[i].name == name) { return i }
        }
        return -1
    }
}

/// Fresh binding names for the `match` arms the emitter introduces. Macro
/// expansion cannot introduce a `let` into the enclosing scope, so every
/// pattern variable has to be a name the emitter made up.
class InlineNames {
    private var n: Int64 = 0

    func fresh(): Token {
        n += 1
        return Token(TokenKind.IDENTIFIER, "__io${n}")
    }
}

// ===== registry model =====

enum InlineOpticKind {
    | Symbolic  // (name, OwnerType, field) -- a derived field optic
    | Body      // (name, body, { source => FWD }, { source, focus => BWD }, FocusType)
}

class InlineOpticMeta {
    let kind: InlineOpticKind
    // Symbolic entries only: the owning type and the field being focused.
    let ownerType: String
    let fieldIndex: Int64
    // Body entries only: the focus type the chain continues on once the optic
    // slot has been rebuilt.
    let focusType: String
    let forward: Tokens
    let backward: Tokens

    init(
        kind: InlineOpticKind,
        ownerType: String,
        fieldIndex: Int64,
        focusType: String,
        forward: Tokens,
        backward: Tokens,
    ) {
        this.kind = kind
        this.ownerType = ownerType
        this.fieldIndex = fieldIndex
        this.focusType = focusType
        this.forward = forward
        this.backward = backward
    }
}

// ===== named attribute splitting =====

private func splitInlineFields(attr: Tokens): ArrayList<(Token, Tokens)> {
    let toks = ArrayList<Token>()
    for (i in 0..attr.size) { toks.add(attr[i]) }
    let fields = ArrayList<(Token, Tokens)>()
    var i: Int64 = 0
    while (i < toks.size) {
        if (toks[i].kind == TokenKind.NL || toks[i].kind == TokenKind.COMMA) { i += 1; continue }
        if (toks[i].kind != TokenKind.IDENTIFIER || i + 1 >= toks.size ||
            toks[i + 1].kind != TokenKind.COLON) {
            throw DiagReportException(
                "${inlineMacroName}: expected a 'name: value' attribute field",
                toks[i].toTokens(),
                hint: shapeHint()
            )
        }
        let name = toks[i]
        i += 2
        let value = ArrayList<Token>()
        var depth: Int64 = 0
        while (i < toks.size) {
            if (depth == 0 && toks[i].kind == TokenKind.IDENTIFIER &&
                i + 1 < toks.size && toks[i + 1].kind == TokenKind.COLON) { break }
            match (toks[i].kind) {
                case TokenKind.LPAREN | TokenKind.LCURL | TokenKind.LSQUARE => depth += 1
                case TokenKind.RPAREN | TokenKind.RCURL | TokenKind.RSQUARE => depth -= 1
                case _ => ()
            }
            value.add(toks[i])
            i += 1
        }
        while (!value.isEmpty() && (value[value.size - 1].kind == TokenKind.COMMA ||
                                    value[value.size - 1].kind == TokenKind.NL)) {
            value.remove(at: value.size - 1)
        }
        if (value.isEmpty()) {
            throw DiagReportException("${inlineMacroName}: field '${name.value}' is empty", name.toTokens())
        }
        fields.add((name, Tokens(value)))
    }
    return fields
}

private func inlineField(fields: ArrayList<(Token, Tokens)>, name: String): ?Tokens {
    for (p in fields) {
        let (fname, fvalue) = p
        if (fname.value == name) { return fvalue }
    }
    return None
}

// ===== shape table parsing =====

/// Reads a case's `(field, FieldType)` payload pairs.
///
/// The payload shares the case entry's closing paren, so this stops *at* that
/// paren and leaves it for the caller.
private func parseInlineCasePayload(sc: InlineToks): ArrayList<InlineField> {
    let fields = ArrayList<InlineField>()
    while (true) {
        sc.skipNL()
        if (sc.at(TokenKind.RPAREN)) { break }
        if (sc.at(TokenKind.COMMA)) { sc.bump(); continue }
        sc.expect(TokenKind.LPAREN, "'(' starting a case payload pair")
        let fname = sc.expectName("a field name")
        sc.expect(TokenKind.COMMA, "',' between a field name and its type")
        let (ftype, inner) = sc.expectTypeName()
        sc.expect(TokenKind.RPAREN, "')' closing a case payload pair")
        fields.add(InlineField(fname, ftype, inner))
    }
    return fields
}

/// Parses one type's layout.
///
///   struct  (S, (a, A), (b, B))
///   enum   (E, (Case1, (a, A)), (Case2))
///
/// A member whose second element is itself a parenthesised list is a case; a
/// member whose second element is a type name is a field. That is the only
/// distinction needed, and it is visible at the token after the comma.
private func parseInlineShapeEntry(sc: InlineToks, value: Tokens): InlineShape {
    sc.expect(TokenKind.LPAREN, "'(' starting a shape entry")
    let tname = sc.expectName("a type name")
    let shape = InlineShape(tname, ArrayList<InlineField>())
    while (true) {
        sc.skipNL()
        if (sc.at(TokenKind.RPAREN)) { sc.bump(); break }
        if (sc.at(TokenKind.COMMA)) { sc.bump(); continue }
        sc.expect(TokenKind.LPAREN, "'(' starting a field or case entry")
        let mname = sc.expectName("a field or case name")
        sc.expect(TokenKind.COMMA, "',' after a field or case name")
        sc.skipNL()
        if (sc.at(TokenKind.LPAREN) || sc.at(TokenKind.RPAREN)) {
            shape.isEnum = true
            // A case's payload is spelled like a struct's field list, so
            // `(Held, (v, Int64))` carries one field and `(Empty, ())` or a
            // bare `(Empty, )` carries none.
            let empty = sc.at(TokenKind.RPAREN) || sc.atOffset(TokenKind.RPAREN, 1)
            let payload = if (empty) {
                // `()` is an explicit spelling for "no payload"; a bare `, )`
                // has nothing to consume.
                if (sc.at(TokenKind.LPAREN)) {
                    sc.bump()
                    sc.expect(TokenKind.RPAREN, "')' closing an empty case payload")
                }
                ArrayList<InlineField>()
            } else {
                parseInlineCasePayload(sc)
            }
            sc.expect(TokenKind.RPAREN, "')' closing a case entry")
            shape.cases.add(InlineCase(mname, payload))
        } else {
            let (ftype, inner) = sc.expectTypeName()
            sc.expect(TokenKind.RPAREN, "')' closing a (field, fieldType) pair")
            shape.fields.add(InlineField(mname, ftype, inner))
        }
    }
    if (!shape.isEnum && shape.fields.isEmpty()) {
        throw DiagReportException(
            "${inlineMacroName}: shape '${tname}' has no fields",
            value,
            hint: shapeHint()
        )
    }
    if (shape.isEnum && shape.cases.isEmpty()) {
        throw DiagReportException(
            "${inlineMacroName}: enum shape '${tname}' has no cases",
            value,
            hint: shapeHint()
        )
    }
    return shape
}

private func parseInlineShapes(value: Tokens): HashMap<String, InlineShape> {
    let sc = InlineToks(value)
    let shapes = HashMap<String, InlineShape>()
    var count: Int64 = 0
    while (true) {
        sc.skipNL()
        if (sc.done()) { break }
        if (sc.at(TokenKind.COMMA)) { sc.bump(); continue }
        let shape = parseInlineShapeEntry(sc, value)
        shapes[shape.name] = shape
        count += 1
    }
    if (count == 0) {
        throw DiagReportException(
            "${inlineMacroName}: 'shapes' listed no types",
            value,
            hint: shapeHint()
        )
    }
    return shapes
}

/// The base name of a type's token run: `Int64` and `Array<Int64>` both read
/// as `Int64` / `Array`, which is how shape field types are compared.
private func typeNameOf(toks: Tokens): String {
    let sc = InlineToks(toks)
    if (sc.done()) { return "" }
    return sc.expectName("a type name")
}

private func shapeOf(shapes: HashMap<String, InlineShape>, typeName: String, at: Tokens): InlineShape {
    match (shapes.get(typeName)) {
        case Some(s) => s
        case None => throw DiagReportException(
            "${inlineMacroName}: no shape registered for type '${typeName}'",
            at,
            hint: "add (${typeName}, (field, FieldType), ...) to shapes"
        )
    }
}

// ===== registry parsing =====

/// Captures the expression part of `{ params => EXPR }`, rejecting anything else.
private func parseInlineBody(cur: InlineToks, what: String, paramCount: Int64): Tokens {
    cur.expect(TokenKind.LCURL, "'{' starting " + what)
    let toks = cur.raw()
    let paramStart = cur.i
    var depth: Int64 = 1
    var arrow: Int64 = -1
    while (cur.i < toks.size) {
        let k = toks[cur.i].kind
        if (k == TokenKind.LCURL) {
            depth += 1
        } else if (k == TokenKind.RCURL) {
            depth -= 1
            if (depth == 0) { break }
        } else if (k == TokenKind.DOUBLE_ARROW && depth == 1) {
            arrow = cur.i
            break
        }
        cur.i += 1
    }
    if (arrow < 0) {
        throw DiagReportException(
            "${inlineMacroName}: ${what} has no '=>'",
            cur.curTokens(),
            hint: inlineBodyHint(paramCount)
        )
    }
    let params = ArrayList<Token>()
    for (j in paramStart..arrow) {
        if (toks[j].kind == TokenKind.IDENTIFIER) { params.add(toks[j]) }
    }
    if (params.size != paramCount) {
        throw DiagReportException(
            "${inlineMacroName}: ${what} binds ${params.size} names, expected ${paramCount}",
            cur.curTokens(),
            hint: inlineBodyHint(paramCount)
        )
    }
    cur.i = arrow + 1
    let exprToks = ArrayList<Token>()
    depth = 1
    while (cur.i < toks.size) {
        let k = toks[cur.i].kind
        if (k == TokenKind.LCURL || k == TokenKind.LPAREN || k == TokenKind.LSQUARE) {
            depth += 1
        } else if (k == TokenKind.RCURL || k == TokenKind.RPAREN || k == TokenKind.RSQUARE) {
            depth -= 1
            if (depth == 0) { break }
        }
        exprToks.add(toks[cur.i])
        cur.i += 1
    }
    cur.expect(TokenKind.RCURL, "'}' closing " + what)
    return Tokens(exprToks)
}

private func inlineBodyHint(paramCount: Int64): String {
    if (paramCount == 1) {
        "write it as { ${inlineSourceParam} => EXPR }"
    }
    "write it as { ${inlineSourceParam}, ${inlineFocusParam} => EXPR }; use _ to skip a parameter"
}

private func parseInlineRegistry(
    value: Tokens,
    shapes: HashMap<String, InlineShape>
): HashMap<String, InlineOpticMeta> {
    let cur = InlineToks(value)
    let registry = HashMap<String, InlineOpticMeta>()
    while (true) {
        cur.skipNL()
        if (cur.done()) { break }
        if (cur.at(TokenKind.COMMA)) { cur.bump(); continue }
        cur.expect(TokenKind.LPAREN, "'(' starting a registry entry")
        let oname = cur.expectName("an optic name")
        cur.expect(TokenKind.COMMA, "',' after the optic name")
        let second = cur.expectName("an owner type name, or the keyword '${inlineBodyKeyword}'")
        if (second == inlineBodyKeyword) {
            cur.expect(TokenKind.COMMA, "',' before the forward body")
            let forward = parseInlineBody(cur, "the forward body", 1)
            cur.expect(TokenKind.COMMA, "',' between the forward and backward bodies")
            let backward = parseInlineBody(cur, "the backward body", 2)
            cur.expect(TokenKind.COMMA, "',' after the backward body")
            let focusType = cur.expectName("the optic's focus type name")
            cur.expect(TokenKind.RPAREN, "')' closing the registry entry")
            registry[oname] = InlineOpticMeta(InlineOpticKind.Body, "", -1, focusType, forward, backward)
        } else {
            cur.expect(TokenKind.COMMA, "',' after the owner type")
            let fname = cur.expectName("a field name")
            cur.expect(TokenKind.RPAREN, "')' closing the registry entry")
            let shape = shapeOf(shapes, second, value)
            let fidx = shape.indexOf(fname)
            if (fidx < 0) {
                throw DiagReportException(
                    "${inlineMacroName}: shape '${second}' has no field '${fname}'",
                    value,
                    hint: "check the field list against the struct declaration"
                )
            }
            registry[oname] = InlineOpticMeta(InlineOpticKind.Symbolic, second, fidx, "", Tokens(), Tokens())
        }
    }
    return registry
}
// ===== resolved chain steps =====

enum InlineStepKind {
    // Total field: the chain continues on the field, never fails.
    | Rebuild
    // `?.` over an Option -- a field's payload, or the value itself when a
    // first-class optic is applied partially. Fails to None / identity.
    | Partial
    // `?.Case` on an enum: matches one case, identity on a miss.
    | Case
    // A registered hand-written optic, inlined through its bodies.
    | Body
    // A sibling block's rebuild, already emitted against the block anchor.
    // Rebuilds that value and hands it back to the enclosing chain.
    | Block
}

extend InlineStepKind {
    /// The kinds a guarded match can rebuild through: a value that may be
    /// absent, so a block anchored on one has to put its whole rebuild inside
    /// the match and hand the source back on a miss.
    func isPartialStep(): Bool {
        match (this) {
            case Partial | Case => true
            case _ => false
        }
    }
}

class InlineStep {
    let kind: InlineStepKind
    // The type this step reads from. For a Partial with fieldIndex -1 the whole
    // value is matched rather than one of its fields.
    let ownerType: String
    let fieldIndex: Int64
    // Case index, for the Case kind.
    let caseIndex: Int64
    // What the chain continues on, for Partial steps.
    let focusType: String
    // The type of the value this step reads. A Partial needs the *next* step's
    // type to spell the Option it returns.
    var chainType: String
    let forward: Tokens
    let backward: Tokens

    init(
        kind: InlineStepKind,
        ownerType: String,
        fieldIndex: Int64,
        caseIndex: Int64,
        focusType: String,
        forward: Tokens,
        backward: Tokens,
        chainType!: String = ""
    ) {
        this.chainType = chainType
        this.kind = kind
        this.ownerType = ownerType
        this.fieldIndex = fieldIndex
        this.caseIndex = caseIndex
        this.focusType = focusType
        this.forward = forward
        this.backward = backward
    }
}

extend OpticKind {
    func isPartial(): Bool {
        match (this) {
            case OpticKind.Prism => true
            case _ => false
        }
    }
}

private func missingRegistryDiag(tok: Token): DiagReportException {
    DiagReportException(
        "${inlineMacroName}: no inlining metadata registered for '${tok.value}'",
        tok.toTokens(),
        hint: "a derived field optic registers as registry: (${tok.value}, OwnerType, field); "
            + "a hand-written one registers as registry: (${tok.value}, ${inlineBodyKeyword}, "
            + "{ ${inlineSourceParam} => FWD }, { ${inlineSourceParam}, ${inlineFocusParam} => BWD }, FocusType)"
    )
}

// ===== token assembly =====

private func tn(v: String): Token {
    return Token(TokenKind.IDENTIFIER, v)
}

private func cat(parts: Array<Tokens>): Tokens {
    let out = Tokens()
    for (part in parts) {
        for (i in 0..part.size) { out.append(part[i]) }
    }
    return out
}

/// The source text a structural token kind stands for. `Token` validates its
/// value against its kind, so punctuation cannot be emitted with an empty value.
private func punctText(kind: TokenKind): String {
    match (kind) {
        case TokenKind.LPAREN => "("
        case TokenKind.RPAREN => ")"
        case TokenKind.LCURL => "{"
        case TokenKind.RCURL => "}"
        case TokenKind.LSQUARE => "["
        case TokenKind.RSQUARE => "]"
        case TokenKind.COMMA => ","
        case TokenKind.COLON => ":"
        case TokenKind.DOT => "."
        case TokenKind.LT => "<"
        case TokenKind.GT => ">"
        case TokenKind.DOUBLE_ARROW => "=>"
        case _ => throw IllegalArgumentException("punctText: unsupported token kind")
    }
}

private func punct(kind: TokenKind): Tokens {
    let out = Tokens()
    out.append(Token(kind, punctText(kind)))
    return out
}

private func word(v: String): Tokens {
    let out = Tokens()
    out.append(tn(v))
    return out
}

/// `match (S) { case Some (v) => A case None => B }`
private func matchSome(subject: Tokens, binding: Token, onSome: Tokens, onNone: Tokens): Tokens {
    return cat([
        word("match"), punct(TokenKind.LPAREN), subject, punct(TokenKind.RPAREN), punct(TokenKind.LCURL),
        word("case"), word("Some"), punct(TokenKind.LPAREN), word(binding.value), punct(TokenKind.RPAREN),
        punct(TokenKind.DOUBLE_ARROW), onSome,
        word("case"), word("None"), punct(TokenKind.DOUBLE_ARROW), onNone,
        punct(TokenKind.RCURL)
    ])
}

/// `match (S) { case C (p0, p1) => A case _ => B }`
private func matchCase(
    subject: Tokens,
    caseName: String,
    binders: Array<Token>,
    onMatch: Tokens,
    fallback: Tokens
): Tokens {
    var head = cat([
        word("match"), punct(TokenKind.LPAREN), subject, punct(TokenKind.RPAREN), punct(TokenKind.LCURL),
        word("case"), word(caseName)
    ])
    // A payloadless case takes no pattern list at all (`case Empty`), the same
    // shape `@f` derives.
    if (!binders.isEmpty()) {
        head = cat([head, punct(TokenKind.LPAREN)])
        for (i in 0..binders.size) {
            if (i > 0) { head = cat([head, punct(TokenKind.COMMA)]) }
            head = cat([head, word(binders[i].value)])
        }
        head = cat([head, punct(TokenKind.RPAREN)])
    }
    return cat([
        head, punct(TokenKind.DOUBLE_ARROW), onMatch,
        word("case"), word("_"), punct(TokenKind.DOUBLE_ARROW), fallback,
        punct(TokenKind.RCURL)
    ])
}

/// `match (S) { case (t0, t1) => A case _ => B }` -- destructures a tuple
/// target so a multi-payload case can be rebuilt field by field.
private func matchTuple(subject: Tokens, binders: Array<Token>, onMatch: Tokens, fallback: Tokens): Tokens {
    // The space after `case` matters: without it the next token lexes as part of
    // the keyword and the arm silently matches nothing.
    var head = cat([
        word("match"), punct(TokenKind.LPAREN), subject, punct(TokenKind.RPAREN), punct(TokenKind.LCURL),
        word("case"), punct(TokenKind.LPAREN)
    ])
    for (i in 0..binders.size) {
        if (i > 0) { head = cat([head, punct(TokenKind.COMMA)]) }
        head = cat([head, word(binders[i].value)])
    }
    return cat([
        head, punct(TokenKind.RPAREN), punct(TokenKind.DOUBLE_ARROW), onMatch,
        word("case"), word("_"), punct(TokenKind.DOUBLE_ARROW), fallback,
        punct(TokenKind.RCURL)
    ])
}

/// `match (SUBJECT) { case (a, b, ...) => ONMATCH }`
///
/// No fallback arm: a tuple pattern covers every tuple of that arity, and one is
/// needed anyway -- the fallback would have to produce the same type as
/// `onMatch`, and a multi-payload case rebuilds an *enum* from the target tuple,
/// which cannot be done without destructuring it.
private func destructureTuple(subject: Tokens, binders: Array<Token>, onMatch: Tokens): Tokens {
    var head = cat([
        word("match"), punct(TokenKind.LPAREN), subject, punct(TokenKind.RPAREN), punct(TokenKind.LCURL),
        word("case"), punct(TokenKind.LPAREN)
    ])
    for (i in 0..binders.size) {
        if (i > 0) { head = cat([head, punct(TokenKind.COMMA)]) }
        head = cat([head, word(binders[i].value)])
    }
    return cat([head, punct(TokenKind.RPAREN), punct(TokenKind.DOUBLE_ARROW), onMatch,
                punct(TokenKind.RCURL)])
}

/// `Some (EXPR)`
private func some(expr: Tokens): Tokens {
    return cat([word("Some"), punct(TokenKind.LPAREN), expr, punct(TokenKind.RPAREN)])
}

/// `None`
/// `Option<T>.None`. The explicit argument is needed wherever the match arms
/// give the compiler nothing to infer the Option's type from. A focus spelled
/// `()` — a payloadless case — is `Unit` when it appears as a type argument.
private func noneTokOf(typeName: String): Tokens {
    if (typeName == "") { return noneTok() }
    let arg = if (typeName == focusUnitTypeName) { "Unit" } else { typeName }
    return cat([
        word("Option"), punct(TokenKind.LT), word(arg), punct(TokenKind.GT),
        punct(TokenKind.DOT), word("None")
    ])
}

private func noneTok(): Tokens {
    return word("None")
}

/// `Ctor (a0, a1, ...)`
private func ctorCall(name: String, args: Array<Tokens>): Tokens {
    var out = cat([word(name), punct(TokenKind.LPAREN)])
    for (i in 0..args.size) {
        if (i > 0) { out = cat([out, punct(TokenKind.COMMA)]) }
        out = cat([out, args[i]])
    }
    return cat([out, punct(TokenKind.RPAREN)])
}

/// `(p0, p1, ...)`
private func tupleOf(parts: Array<Tokens>): Tokens {
    var out = cat([punct(TokenKind.LPAREN)])
    for (i in 0..parts.size) {
        if (i > 0) { out = cat([out, punct(TokenKind.COMMA)]) }
        out = cat([out, parts[i]])
    }
    return cat([out, punct(TokenKind.RPAREN)])
}

private func toWords(toks: Array<Token>): Array<Tokens> {
    let out = ArrayList<Tokens>()
    for (t in toks) { out.add(word(t.value)) }
    return out.toArray()
}

private func namesOf(n: InlineNames, count: Int64): Array<Token> {
    let out = ArrayList<Token>()
    for (_ in 0..count) { out.add(n.fresh()) }
    return out.toArray()
}

private func access(base: Tokens, field: String): Tokens {
    return cat([base, punct(TokenKind.DOT), word(field)])
}

/// The payload type of an Option-typed field, found by its declared type.
///
/// A `?.` slot needs this when the *owner* is the Option rather than one of
/// its fields: `o.m?.a` unwraps `o.m`, so the chain resumes on `InlBox`.
private func optionInnerOf(shapes: HashMap<String, InlineShape>, typeName: String): ?String {
    for ((_, shape) in shapes) {
        for (f in shape.fields) {
            if (f.typeName == typeName) {
                match (f.optionInner) {
                    case Some(inner) => return Some(inner)
                    case None => ()
                }
            }
        }
    }
    return None
}

// ===== chain resolution =====

private func resolveInlineOptic(
    tok: Token,
    partialCall: Bool,
    shapes: HashMap<String, InlineShape>,
    registry: HashMap<String, InlineOpticMeta>,
    current: String,
    steps: ArrayList<InlineStep>
): String {
    let meta = match (registry.get(tok.value)) {
        case Some(m) => m
        case None => throw missingRegistryDiag(tok)
    }
    match (meta.kind) {
        case InlineOpticKind.Symbolic =>
            let shape = shapeOf(shapes, meta.ownerType, tok.toTokens())
            let field = shape.fields[meta.fieldIndex]
            if (partialCall) {
                // Applied with `?.`: the value itself must be an Option, so the
                // chain continues on the field's type once unwrapped.
                steps.add(InlineStep(InlineStepKind.Partial, current, -1, -1, field.typeName,
                                     Tokens(), Tokens()))
                return field.typeName
            }
            if (current == "") {
                throw DiagReportException(
                    "${inlineMacroName}: the type before '${tok.value}' is unknown",
                    tok.toTokens(),
                    hint: "name it with root:"
                )
            }
            if (current != meta.ownerType) {
                throw DiagReportException(
                    "${inlineMacroName}: optic '${tok.value}' focuses '${meta.ownerType}', "
                    + "but the chain is at '${current}'",
                    tok.toTokens(),
                    hint: "the chain reached a different type than the registered owner"
                )
            }
            steps.add(InlineStep(InlineStepKind.Rebuild, meta.ownerType, meta.fieldIndex, -1, "",
                                 Tokens(), Tokens()))
            return field.typeName
        case InlineOpticKind.Body =>
            if (partialCall) {
                steps.add(InlineStep(InlineStepKind.Partial, "", -1, -1, meta.focusType,
                                     meta.forward, meta.backward))
            } else {
                steps.add(InlineStep(InlineStepKind.Body, "", -1, -1, meta.focusType,
                                     meta.forward, meta.backward))
            }
            return meta.focusType
    }
}

private func resolveInlineSteps(
    nodes: Array<CompositionNode>,
    shapes: HashMap<String, InlineShape>,
    registry: HashMap<String, InlineOpticMeta>,
    rootType: String,
    input: Tokens
): (ArrayList<InlineStep>, String) {
    let steps = ArrayList<InlineStep>()
    var current = rootType
    for (idx in 0..nodes.size) {
        let node = nodes[idx]
        let enterType = current
        let mark = steps.size
        var afterUnwrap = ""
        match (node) {
            case Derived(tok, kind) =>
                // `?.` reaches through an Option owner: unwrap first, then read
                // the named field of the payload type. The `?.` is spent on the
                // unwrap, so the field itself is a plain total lens.
                var reachedThroughOption = false
                if (kind.isPartial() && current != "" && !shapes.contains(current)) {
                    match (optionInnerOf(shapes, current)) {
                        case Some(inner) =>
                            steps.add(InlineStep(InlineStepKind.Partial, current, -1, -1, inner,
                                                 Tokens(), Tokens()))
                            current = inner
                            afterUnwrap = inner
                            reachedThroughOption = true
                        case None => throw DiagReportException(
                            "${inlineMacroName}: '?.' needs an Option-typed value, but "
                            + "the chain is at '${current}'",
                            tok.toTokens(),
                            hint: "declare the field as (${tok.value}, Option<PayloadType>) in shapes"
                        )
                    }
                }
                if (current == "") {
                    throw DiagReportException(
                        "${inlineMacroName}: the type before '.${tok.value}' is unknown",
                        tok.toTokens(),
                        hint: "name it with root:"
                    )
                }
                let shape = shapeOf(shapes, current, tok.toTokens())
                if (shape.isEnum) {
                    let cidx = shape.indexOfCase(tok.value)
                    if (cidx < 0) {
                        throw DiagReportException(
                            "${inlineMacroName}: enum '${current}' has no case '${tok.value}'",
                            tok.toTokens(),
                            hint: "list the case's payload in shapes, or check the spelling"
                        )
                    }
                    if (!kind.isPartial()) {
                        throw DiagReportException(
                            "${inlineMacroName}: case '${tok.value}' needs a partial slot",
                            tok.toTokens(),
                            hint: "write '?.${tok.value}': an enum case cannot be focused totally"
                        )
                    }
                    steps.add(InlineStep(InlineStepKind.Case, current, -1, cidx, "", Tokens(), Tokens()))
                    current = shape.cases[cidx].focusTypeName()
                } else {
                    let fidx = shape.indexOf(tok.value)
                    if (fidx < 0) {
                        throw DiagReportException(
                            "${inlineMacroName}: '${current}' has no field '${tok.value}'",
                            tok.toTokens(),
                            hint: "the shape list must match the struct declaration"
                        )
                    }
                    let field = shape.fields[fidx]
                    if (kind.isPartial() && !reachedThroughOption) {
                        // `?.` applies to the optic *before* it, so a struct field
                        // reached this way was already unwrapped: `@f` reads
                        // `x?.f` as "unwrap `x`, then read `f`", and `x` is a
                        // struct here.
                        throw DiagReportException(
                            "${inlineMacroName}: '?.' on a total optic (Lens/Iso) — "
                            + "'${current}' cannot miss, so there is no Option to unwrap",
                            tok.toTokens(),
                            hint: "write '.${tok.value}': an Option field is already partial. "
                                + "'?.' names a partial optic, as in 'value?.at(1)'"
                        )
                    } else {
                        steps.add(InlineStep(InlineStepKind.Rebuild, current, fidx, -1, "",
                                             Tokens(), Tokens()))
                        current = field.typeName
                    }
                }
            case Optic(tok) =>
                current = resolveInlineOptic(tok, false, shapes, registry, current, steps)
            case UserDefined(name, _, _, total) =>
                current = resolveInlineOptic(name, !total, shapes, registry, current, steps)
            case Type(re) =>
                current = re.identifier.value
            case TypeOf(_) => ()
            case Coerce(t) =>
                // A coercion resolves against a one-field derivation and its
                // field type, so forward is the field read and backward is the
                // single-argument constructor -- the same pair the rebuild
                // emits for that field. Nothing extra to inline; the check is
                // that the shape really is that pair, since `@f` would fail
                // the same lookup at the registry.
                let ctarget = typeNameOf(t.toTokens())
                let cshape = shapeOf(shapes, current, t.toTokens())
                let oneField = !cshape.isEnum && cshape.fields.size == 1
                if (!oneField || cshape.fields[0].typeName != ctarget) {
                    let spelled = if (cshape.isEnum) {
                        "'${current}' is an enum, so it has no iso to coerce"
                    } else if (!oneField) {
                        "a coercion needs a one-field shape; '${current}' has ${cshape.fields.size}"
                    } else {
                        "'${current}' is an iso to '${cshape.fields[0].typeName}', not to '${ctarget}'"
                    }
                    throw DiagReportException(
                        "${inlineMacroName}: cannot inline coerce<${t.toTokens()}> on '${current}'",
                        t.toTokens(),
                        hint: spelled
                    )
                }
                steps.add(InlineStep(InlineStepKind.Rebuild, current, 0, -1, "", Tokens(), Tokens()))
                current = ctarget
        }
        // Steps before an owner unwrap read the Option; the ones after read
        // the payload.
        for (k in mark..steps.size) {
            steps[k].chainType = if (afterUnwrap != "" && k > mark) { afterUnwrap } else { enterType }
        }
    }
    return (steps, current)
}

// ===== emission =====

/// The rebuild for steps `lo..steps.size`, entering at `src`.
///
/// A partial slot decides whether the update happens at all, so its `match`
/// is hoisted over the *whole* chain: the hit arm carries every level, and the
/// miss arm hands back the source as it was. Wrapping the levels above the
/// partial around the `match` instead would keep the types right but allocate a
/// fresh object on every miss to copy something that did not change.
/// `levelSrc[k]` is the value entering step `lo + k`, read off the original
/// source, so every level can copy its untouched fields from it.
private func inlineLevelSrc(
    steps: ArrayList<InlineStep>,
    shapes: HashMap<String, InlineShape>,
    lo: Int64,
    src: Tokens
): ArrayList<Tokens> {
    let levelSrc = ArrayList<Tokens>()
    levelSrc.add(src)
    for (i in lo..steps.size) {
        let st = steps[i]
        match (st.kind) {
            case InlineStepKind.Rebuild =>
                let shape = shapes.get(st.ownerType).getOrThrow()
                levelSrc.add(access(levelSrc[i - lo], shape.fields[st.fieldIndex].name))
            case _ =>
                levelSrc.add(levelSrc[i - lo])
        }
    }
    return levelSrc
}

private func emitInlineRebuild(
    steps: ArrayList<InlineStep>,
    shapes: HashMap<String, InlineShape>,
    names: InlineNames,
    lo: Int64,
    src: Tokens,
    target: Tokens
): Tokens {
    let levelSrc = inlineLevelSrc(steps, shapes, lo, src)

    var i = lo
    while (i < steps.size) {
        let st = steps[i]
        let k = i - lo
        match (st.kind) {
            case InlineStepKind.Rebuild => i += 1
            case InlineStepKind.Body =>
                // A registered body is terminal: it takes the old focus and the
                // new one and hands back the rebuilt owner.
                return emitOuterWrap(steps, shapes, names, lo, i, levelSrc,
                                     emitInlineBodyRebuild(st, names, levelSrc[k], target))
            case InlineStepKind.Partial =>
                let subject = if (st.fieldIndex >= 0) {
                    let shape = shapes.get(st.ownerType).getOrThrow()
                    access(levelSrc[k], shape.fields[st.fieldIndex].name)
                } else {
                    levelSrc[k]
                }
                let bound = names.fresh()
                let inner = match (st.forward.size == 0) {
                    case true => emitInlineRebuild(steps, shapes, names, i + 1,
                                                   bound.toTokens(), target)
                    case false => emitInlineBodyRebuild(st, names, bound.toTokens(), target)
                }
                return matchSome(subject, bound,
                                 emitOuterWrap(steps, shapes, names, lo, i, levelSrc, inner),
                                 levelSrc[0])
            case InlineStepKind.Case =>
                let shape = shapes.get(st.ownerType).getOrThrow()
                let c = shape.cases[st.caseIndex]
                let binders = namesOf(names, c.fields.size)
                // The case is rebuilt through its type name: an unqualified case
                // name is ambiguous outside the enum's own declarations.
                let caseName = st.ownerType + "." + c.name
                // The chain below rebuilds off the *old* payload, so it reads the
                // pattern's binders rather than the new focus.
                let below = match (c.fields.size) {
                    case 0 => cat([punct(TokenKind.LPAREN), punct(TokenKind.RPAREN)])
                    case 1 => binders[0].toTokens()
                    case _ => tupleOf(toWords(binders))
                }
                let inner = emitInlineRebuild(steps, shapes, names, i + 1, below, target)
                // The case wraps whatever the chain below produced, so a chain
                // that continues into the payload's own fields rebuilds those
                // first and the case closes over the result.
                let rebuilt = match (c.fields.size) {
                    case 0 => word(caseName)
                    case 1 => ctorCall(caseName, [inner])
                    case _ =>
                        // The focus is the whole payload tuple, so destructure it
                        // and hand one component to each constructor argument.
                        let parts = namesOf(names, c.fields.size)
                        destructureTuple(inner, parts, ctorCall(caseName, toWords(parts)))
                }
                return matchCase(levelSrc[k], c.name, binders,
                                 emitOuterWrap(steps, shapes, names, lo, i, levelSrc, rebuilt),
                                 levelSrc[0])
            case InlineStepKind.Block =>
                return emitOuterWrap(steps, shapes, names, lo, i, levelSrc, st.forward)
        }
    }
    return emitOuterWrap(steps, shapes, names, lo, steps.size, levelSrc, target)
}

/// Rebuilds the total levels `lo..hi` outward, from `inner` -- the value the
/// chain has produced -- back out to the level that `lo` enters.
private func emitOuterWrap(
    steps: ArrayList<InlineStep>,
    shapes: HashMap<String, InlineShape>,
    names: InlineNames,
    lo: Int64,
    hi: Int64,
    levelSrc: ArrayList<Tokens>,
    inner: Tokens
): Tokens {
    var expr = inner
    var i = hi - 1
    while (i >= lo) {
        let st = steps[i]
        match (st.kind) {
            case InlineStepKind.Rebuild =>
                let shape = shapes.get(st.ownerType).getOrThrow()
                let args = ArrayList<Tokens>()
                for (j in 0..shape.fields.size) {
                    if (j == st.fieldIndex) {
                        args.add(expr)
                    } else {
                        args.add(access(levelSrc[i - lo], shape.fields[j].name))
                    }
                }
                expr = ctorCall(st.ownerType, args.toArray())
            case InlineStepKind.Body =>
                expr = emitInlineBodyRebuild(st, names, levelSrc[i - lo], expr)
            case InlineStepKind.Block =>
                // A block's rebuild was already emitted against its anchor, and
                // it yields the anchor's value rather than a leaf.
                expr = st.forward
            case _ => ()
        }
        i -= 1
    }
    return expr
}

/// A registered optic's inlined bodies: the forward reads the old focus off the
/// source so the chain below can rebuild it, then the backward wraps the new
/// focus back up.
private func emitInlineBodyRebuild(st: InlineStep, names: InlineNames, src: Tokens, target: Tokens): Tokens {
    let oldFocus = substituteInlineParams(st.forward, src, word(inlineFocusParam))
    let newFocus = target
    return substituteInlineParams(st.backward, oldFocus, newFocus)
}

/// The Option type an inline forward at `idx` evaluates to.
///
/// Every partial slot threads one Option: `?.` unwraps without producing a
/// nested Option of its own unless another partial slot follows it, which is
/// how `@f` composes adjacent affines.
private func inlineForwardOptionType(steps: ArrayList<InlineStep>, idx: Int64, finalType: String): String {
    var nested = false
    for (j in (idx + 1)..steps.size) {
        match (steps[j].kind) {
            case InlineStepKind.Partial => nested = true
            case InlineStepKind.Case => nested = true
            case _ => ()
        }
    }
    return if (nested) { "Option<${finalType}>" } else { finalType }
}

private func emitInlineForward(
    steps: ArrayList<InlineStep>,
    shapes: HashMap<String, InlineShape>,
    names: InlineNames,
    idx: Int64,
    src: Tokens,
    chainFinal!: String
): Tokens {
    if (idx >= steps.size) { return src }
    let st = steps[idx]
    match (st.kind) {
        case InlineStepKind.Block => return src
        case InlineStepKind.Rebuild =>
            let shape = shapes.get(st.ownerType).getOrThrow()
            return emitInlineForward(steps, shapes, names, idx + 1, access(src, shape.fields[st.fieldIndex].name), chainFinal: chainFinal)
        case InlineStepKind.Partial =>
            let subject = if (st.fieldIndex >= 0) {
                let shape = shapes.get(st.ownerType).getOrThrow()
                access(src, shape.fields[st.fieldIndex].name)
            } else {
                src
            }
            let bound = names.fresh()
            let inner = match (st.forward.size == 0) {
                case true => emitInlineForward(steps, shapes, names, idx + 1, bound.toTokens(), chainFinal: chainFinal)
                case false => substituteInlineParams(st.forward, bound.toTokens(), word(inlineFocusParam))
            }
            // When a later partial slot follows, the rest of the chain already
            // produces the Option; wrapping it again would nest the channels.
            let hit = if (inlineForwardOptionType(steps, idx, chainFinal) == chainFinal) {
                some(inner)
            } else {
                inner
            }
            return matchSome(subject, bound, hit,
                             noneTokOf(inlineForwardOptionType(steps, idx, chainFinal)))
        case InlineStepKind.Case =>
            let shape = shapes.get(st.ownerType).getOrThrow()
            let c = shape.cases[st.caseIndex]
            let binders = namesOf(names, c.fields.size)
            let payload = match (c.fields.size) {
                case 0 => cat([punct(TokenKind.LPAREN), punct(TokenKind.RPAREN)])
                case 1 => word(binders[0].value)
                case _ => tupleOf(binders.toArray().map({ it => word(it.value) }))
            }
            // Slots below the case read the payload, not the enum: a case
            // holding a struct continues into that struct's fields, and a case
            // holding a tuple continues into its elements. The payload is
            // therefore the subject for the rest of the walk, and the same
            // Option-nesting rule as a partial slot decides whether this
            // level opens a channel or lets a later one.
            let below = emitInlineForward(steps, shapes, names, idx + 1, payload, chainFinal: chainFinal)
            let hit = if (inlineForwardOptionType(steps, idx, chainFinal) == chainFinal) {
                some(below)
            } else {
                below
            }
            return matchCase(src, c.name, binders, hit,
                             noneTokOf(inlineForwardOptionType(steps, idx, chainFinal)))
        case InlineStepKind.Body =>
            let oldFocus = substituteInlineParams(st.forward, src, word(inlineFocusParam))
            return emitInlineForward(steps, shapes, names, idx + 1, oldFocus, chainFinal: chainFinal)
    }
}

/// Replaces the `source`/`focus` parameter names in a registered body with real
/// token runs.
private func substituteInlineParams(body: Tokens, src: Tokens, focus: Tokens): Tokens {
    let out = Tokens()
    for (i in 0..body.size) {
        let t = body[i]
        if (t.kind == TokenKind.IDENTIFIER && t.value == inlineSourceParam) {
            out.append(src)
        } else if (t.kind == TokenKind.IDENTIFIER && t.value == inlineFocusParam) {
            out.append(focus)
        } else {
            out.append(t)
        }
    }
    return out
}

// ===== sibling blocks =====

/// A block entry resolved against the anchor type: the steps down to the field
/// it writes, plus the tuple element holding its target.
private class BlockWrite {
    let steps: ArrayList<InlineStep>
    let inner: ?BlockSpec
    let target: Tokens

    init(steps: ArrayList<InlineStep>, inner: ?BlockSpec, target: Tokens) {
        this.steps = steps
        this.inner = inner
        this.target = target
    }
}

/// A sibling block anchored on a value that can be absent.
///
/// `@f` accepts this and composes it: the anchor's forward yields an `Option`,
/// the block rebuild happens on the payload *inside* the guard, and a miss is
/// the identity for a write and `None` for a read. The harness emits the same
/// shape directly, so the two agree token for token:
///
///   @InlineOptics[...](k?.On.{ .x; .y } <- (7, 8))
///
///     match (k) {
///         case On(inner) => PKind.On(PInner(inner.x, 8))
///         case _         => k
///     }
///
/// The prefix chain is rebuilt around the guarded focus, so an anchor like
/// `o.inner?.slot.{ ... }` puts the block two constructor calls deep.
/// The expression a guard matches on: what the anchor's last step actually reads.
/// A case matches the enum itself, so the prefix chain is the subject; a partial
/// matches the field it unwraps (`o?.m` guards on `o.m`), or the source itself
/// when the partial is registered or first-class and so has no field of its own.
private func guardedSubject(
    shapes: HashMap<String, InlineShape>,
    names: InlineNames,
    anchorSteps: ArrayList<InlineStep>,
    last: Int64,
    source: Tokens
): Tokens {
    let st = anchorSteps[last]
    let prefix = ArrayList<InlineStep>()
    for (i in 0..last) { prefix.add(anchorSteps[i]) }
    return emitInlineForward(prefix, shapes, names, 0, source, chainFinal: st.ownerType)
}

private func emitGuardedBlockUpdate(
    shapes: HashMap<String, InlineShape>,
    registry: HashMap<String, InlineOpticMeta>,
    names: InlineNames,
    anchorSteps: ArrayList<InlineStep>,
    last: Int64,
    ownerType: String,
    spec: BlockSpec,
    targets: Array<Expr>,
    source: Expr,
    input: Tokens
): Tokens {
    let st = anchorSteps[last]
    let bound = names.fresh()
    let subject = guardedSubject(shapes, names, anchorSteps, last, source.toTokens())

    var tuple = ArrayList<Tokens>()
    for (t in targets) { tuple.add(t.toTokens()) }
    let focus = emitBlockSpecUpdate(shapes, names, ownerType, spec,
                                    tupleOf(tuple.toArray()), bound.toTokens(), input)
    // The guard already unwrapped the anchor, so the hit arm puts the block's
    // value straight back into the anchor and wraps the levels below it outwards.
    // Going back through the rebuild machinery would match the same case twice.
    let sealed = match (st.kind) {
        case InlineStepKind.Case =>
            let shape = shapes.get(st.ownerType).getOrThrow()
            ctorCall(st.ownerType + "." + shape.cases[st.caseIndex].name, [focus])
        case _ => match (st.forward.size == 0) {
            case true => some(focus)
            case false => emitInlineBodyRebuild(st, names, subject, focus)
        }
    }
    let levelSrc = inlineLevelSrc(anchorSteps, shapes, 0, source.toTokens())
    let inner = emitOuterWrap(anchorSteps, shapes, names, 0, last, levelSrc, sealed)
    return guardedMatch(st, shapes, names, subject, bound, inner, source.toTokens())
}

/// The read half: the same guard, with the block's tuple on a hit and `None`
/// on a miss.
private func emitGuardedBlockRead(
    shapes: HashMap<String, InlineShape>,
    registry: HashMap<String, InlineOpticMeta>,
    names: InlineNames,
    anchorSteps: ArrayList<InlineStep>,
    last: Int64,
    ownerType: String,
    spec: BlockSpec,
    source: Expr,
    input: Tokens
): Tokens {
    let st = anchorSteps[last]
    let bound = names.fresh()
    let subject = guardedSubject(shapes, names, anchorSteps, last, source.toTokens())

    var parts = ArrayList<Tokens>()
    var entryTypes = ArrayList<String>()
    for (e in spec.entries) {
        let (st, entryType) = resolveInlineSteps(e.prefix, shapes, registry, ownerType, input)
        parts.add(emitInlineForward(st, shapes, names, 0, bound.toTokens(), chainFinal: entryType))
        entryTypes.add(entryType)
    }
    let inner = ctorCall("Some", [tupleOf(parts.toArray())])
    // The miss arm cannot be a bare `None`: the match arms give the compiler
    // nothing to infer the Option's argument from, so it is spelled out the way
    // a plain case read spells it.
    return guardedMatch(st, shapes, names, subject, bound, inner,
                        noneTokOf(tupleTypeName(entryTypes.toArray())))
}

/// `(A, B)` -- the type a block read evaluates to, spelled from the types its
/// entries read.
private func tupleTypeName(types: Array<String>): String {
    var out = "("
    for (i in 0..types.size) {
        if (i > 0) { out += ", " }
        out += types[i]
    }
    return out + ")"
}

/// The match itself: `case Some(b) => hit` / `case On(b) => hit`, with the
/// miss arm already spelled by the caller.
private func guardedMatch(
    st: InlineStep,
    shapes: HashMap<String, InlineShape>,
    names: InlineNames,
    subject: Tokens,
    bound: Token,
    onHit: Tokens,
    onMiss: Tokens
): Tokens {
    match (st.kind) {
        case InlineStepKind.Partial =>
            return matchSome(subject, bound, onHit, onMiss)
        case InlineStepKind.Case =>
            let shape = shapes.get(st.ownerType).getOrThrow()
            let c = shape.cases[st.caseIndex]
            // The body was emitted around `bound`, so the pattern has to bind
            // that name. A case whose payload is a tuple would need the block to
            // address its elements by position, which is the tuple gap.
            if (c.fields.size != 1) {
                throw DiagReportException(
                    "${inlineMacroName}: a sibling block anchored on a case needs a single "
                    + "payload field",
                    st.forward.toTokens(),
                    hint: "'${c.name}' carries ${c.fields.size} payload fields; anchor the block on a "
                        + "field of the payload instead"
                )
            }
            return matchCase(subject, c.name, [bound], onHit, onMiss)
        case _ => throw DiagReportException(
            "${inlineMacroName}: a sibling block anchor cannot cross a partial slot",
            st.forward.toTokens(),
            hint: "anchor the block on a value that is always there"
        )
    }
}

/// A block rebuilds every field it does not name, so neither its anchor nor one
/// of its entries may depend on a value that can be absent: a `None` there would
/// silently drop the writes on the fields that *are* named.
private func blockHasPartialStep(steps: ArrayList<InlineStep>): Bool {
    for (s in steps) {
        if (s.kind.isPartialStep()) {
            return true
        }
    }
    return false
}

private func blockStepUnsupported(w: BlockWrite, input: Tokens): Nothing {
    throw DiagReportException(
        "${inlineMacroName}: a sibling block entry cannot cross a partial slot",
        input,
        hint: "inline the partial slot as its own chain, then compare"
    )
}

/// Rebuilds `ownerType` once, replacing every field the block writes.
///
/// Entries that share a prefix are merged at the field they diverge from, so
/// `.{ .i.a; .i.b }` rebuilds `i` exactly once rather than nesting two
/// rebuilds of the same level.
private func emitBlockUpdate(
    shapes: HashMap<String, InlineShape>,
    names: InlineNames,
    ownerType: String,
    writes: Array<BlockWrite>,
    src: Tokens,
    input: Tokens
): Tokens {
    let shape = shapes.get(ownerType).getOrThrow()
    let groupOrder = ArrayList<Int64>()
    let groups = ArrayList<ArrayList<Int64>>()
    for (i in 0..writes.size) {
        let st = writes[i].steps[0]
        match (st.kind) {
            case InlineStepKind.Rebuild => ()
            case _ => blockStepUnsupported(writes[i], input)
        }
        var found: Int64 = -1
        for (g in 0..groupOrder.size) {
            if (groupOrder[g] == st.fieldIndex) { found = g; break }
        }
        if (found < 0) {
            groupOrder.add(st.fieldIndex)
            groups.add(ArrayList<Int64>())
            found = groupOrder.size - 1
        }
        groups[found].add(i)
    }

    let args = ArrayList<Tokens>()
    for (j in 0..shape.fields.size) {
        var g: Int64 = -1
        for (k in 0..groupOrder.size) {
            if (groupOrder[k] == j) { g = k; break }
        }
        if (g < 0) {
            args.add(access(src, shape.fields[j].name))
            continue
        }
        let idxs = groups[g]
        if (idxs.size == 1 && writes[idxs[0]].steps.size == 1) {
            let w = writes[idxs[0]]
            match (w.inner) {
                case Some(inner) =>
                    args.add(emitBlockSpecUpdate(shapes, names, ownerType, inner, w.target, src, input))
                case None => args.add(w.target)
            }
            continue
        }
        // Several entries under this field: rebuild it once, from the rest of
        // their prefixes.
        let subs = ArrayList<BlockWrite>()
        for (i in idxs) {
            let full = writes[i].steps
            let rest = ArrayList<InlineStep>()
            for (k in 1..full.size) { rest.add(full[k]) }
            subs.add(BlockWrite(rest, writes[i].inner, writes[i].target))
        }
        args.add(emitBlockUpdate(shapes, names, shape.fields[j].typeName, subs.toArray(),
                                 access(src, shape.fields[j].name), input))
    }
    return ctorCall(ownerType, args.toArray())
}


/// The top-level elements of a parenthesised tuple literal, or `None` when the
/// token run is not one.
///
/// A block's update value is a tuple, and the rebuild needs its elements apart.
/// If the caller wrote the tuple out -- `.(.a; .b) <- (10, 20)` -- the elements
/// are already separate expressions and can be used directly. Emitting a
/// `match` to pull them out would produce code that is correct but is not what
/// anyone would write: the optimizer has to fold the match away before the two
/// are the same program.
private func splitTupleLiteral(target: Tokens, arity: Int64): ?ArrayList<Tokens> {
    if (target.size < 2 || target[0].kind != TokenKind.LPAREN) { return None }
    let parts = ArrayList<Tokens>()
    var cur = Tokens()
    var depth: Int64 = 0
    var closed: Bool = false
    for (i in 1..target.size) {
        let t = target[i]
        if (t.kind == TokenKind.RPAREN && depth == 0) {
            if (cur.size > 0 || parts.size > 0) { parts.add(cur) }
            closed = true
            break
        }
        match (t.kind) {
            case TokenKind.LPAREN | TokenKind.LSQUARE | TokenKind.LCURL => depth += 1
            case TokenKind.RPAREN | TokenKind.RSQUARE | TokenKind.RCURL => depth -= 1
            case _ => ()
        }
        if (t.kind == TokenKind.COMMA && depth == 0) {
            parts.add(cur)
            cur = Tokens()
            continue
        }
        cur.append(t)
    }
    if (!closed || parts.size != arity) { return None }
    for (p in parts) {
        if (p.size == 0) { return None }
    }
    return Some(parts)
}

/// Rebuilds `spec` against the block's target value, through `emitBlockUpdate`.
private func emitBlockSpecUpdate(
    shapes: HashMap<String, InlineShape>,
    names: InlineNames,
    ownerType: String,
    spec: BlockSpec,
    target: Tokens,
    src: Tokens,
    input: Tokens
): Tokens {
    // A literal tuple needs no destructuring: its elements are already the
    // per-entry values, so the rebuild is a plain nest of constructors.
    match (splitTupleLiteral(target, spec.entries.size)) {
        case Some(parts) =>
            var direct = ArrayList<BlockWrite>()
            for (i in 0..spec.entries.size) {
                let (steps, _) = resolveInlineSteps(spec.entries[i].prefix, shapes,
                                                     HashMap<String, InlineOpticMeta>(), ownerType, input)
                direct.add(BlockWrite(steps, spec.entries[i].inner, parts[i]))
            }
            return emitBlockUpdate(shapes, names, ownerType, direct.toArray(), src, input)
        case None => ()
    }
    var writes = ArrayList<BlockWrite>()
    for (e in spec.entries) {
        let (steps, _) = resolveInlineSteps(e.prefix, shapes, HashMap<String, InlineOpticMeta>(), ownerType, input)
        writes.add(BlockWrite(steps, e.inner, target))
    }
    if (writes.size == 1) {
        let only = writes[0]
        match (only.inner) {
            case Some(inner) => return emitBlockSpecUpdate(shapes, names, ownerType, inner, target, src, input)
            case None => return only.target
        }
    }
    let binders = namesOf(names, writes.size)
    let rebuild = emitBlockUpdateWith(shapes, names, ownerType, writes, binders, src, input)
    return matchTuple(target, binders, rebuild, src)
}

private func emitBlockUpdateWith(
    shapes: HashMap<String, InlineShape>,
    names: InlineNames,
    ownerType: String,
    writes: ArrayList<BlockWrite>,
    targets: Array<Token>,
    src: Tokens,
    input: Tokens
): Tokens {
    let shape = shapes.get(ownerType).getOrThrow()
    let groupOrder = ArrayList<Int64>()
    let groups = ArrayList<ArrayList<Int64>>()
    for (i in 0..writes.size) {
        let st = writes[i].steps[0]
        match (st.kind) {
            case InlineStepKind.Rebuild => ()
            case _ => blockStepUnsupported(writes[i], input)
        }
        var found: Int64 = -1
        for (g in 0..groupOrder.size) {
            if (groupOrder[g] == st.fieldIndex) { found = g; break }
        }
        if (found < 0) {
            groupOrder.add(st.fieldIndex)
            groups.add(ArrayList<Int64>())
            found = groupOrder.size - 1
        }
        groups[found].add(i)
    }
    let args = ArrayList<Tokens>()
    for (j in 0..shape.fields.size) {
        var g: Int64 = -1
        for (k in 0..groupOrder.size) {
            if (groupOrder[k] == j) { g = k; break }
        }
        if (g < 0) {
            args.add(access(src, shape.fields[j].name))
            continue
        }
        let idxs = groups[g]
        if (idxs.size == 1 && writes[idxs[0]].steps.size == 1) {
            let w = writes[idxs[0]]
            match (w.inner) {
                case Some(inner) =>
                    args.add(emitBlockSpecUpdate(shapes, names, ownerType, inner, w.target, src, input))
                case None => args.add(word(targets[idxs[0]].value))
            }
            continue
        }
        // Entries sharing this field descend together, so hand the recursion
        // only their own targets and the field's own sub-value.
        let subs = ArrayList<BlockWrite>()
        let subTargets = ArrayList<Token>()
        for (i in idxs) {
            let full = writes[i].steps
            let rest = ArrayList<InlineStep>()
            for (k in 1..full.size) { rest.add(full[k]) }
            subs.add(BlockWrite(rest, writes[i].inner, writes[i].target))
            subTargets.add(targets[i])
        }
        args.add(emitBlockUpdateWith(shapes, names, shape.fields[j].typeName, subs, subTargets.toArray(),
                                     access(src, shape.fields[j].name), input))
    }
    return ctorCall(ownerType, args.toArray())
}

// ===== attribute / input handling =====

private func inlineFieldIdent(value: Tokens, name: String): String {
    let sc = InlineToks(value)
    sc.skipNL()
    let ident = sc.expectName(name)
    sc.skipNL()
    if (!sc.done()) {
        throw DiagReportException(
            "${inlineMacroName}: field '${name}' takes a single type name",
            value,
            hint: shapeHint()
        )
    }
    return ident
}

/// `@f(...)` is itself a macro, so a nested one is expanded before this macro
/// runs and the original expression tokens are already gone. Say so plainly
/// instead of failing deep inside the expression parser.
private func rejectNestedOptics(input: Tokens): Unit {
    if (input.size >= 3 && input[0].kind == TokenKind.AT &&
        input[1].kind == TokenKind.IDENTIFIER && input[1].value == "f") {
        throw DiagReportException(
            "${inlineMacroName}: do not wrap the expression in @f",
            input[0..3].toTokens(),
            hint: "pass the optical expression itself: "
                + "@InlineOptics[shapes: ..., root: ...](o.x.y <- 3)"
        )
    }
}

private func inlineRootType(nodes: Array<CompositionNode>, rootToks: ?Tokens, input: Tokens): String {
    if (rootToks.isSome()) {
        return inlineFieldIdent(rootToks.getOrThrow(), "root")
    }
    if (nodes.size > 0) {
        match (nodes[0]) {
            case CompositionNode.Type(re) => return re.identifier.value
            case _ => ()
        }
    }
    throw DiagReportException(
        "${inlineMacroName}: the source value's type is unknown",
        input,
        hint: "macros cannot see types, so pass root: TypeName"
    )
}

private func translateInline(
    expr: OpticalExpr,
    shapes: HashMap<String, InlineShape>,
    registry: HashMap<String, InlineOpticMeta>,
    rootToks: ?Tokens,
    input: Tokens
): Tokens {
    match (expr) {
        case OpticsBackward(source, nodes, target) =>
            let (steps, _) = resolveInlineSteps(nodes, shapes, registry,
                                                inlineRootType(nodes, rootToks, input), input)
            return emitInlineRebuild(steps, shapes, InlineNames(), 0, source.toTokens(), target.toTokens())
        case OpticsForward(source, nodes) =>
            let (steps, finalType) = resolveInlineSteps(nodes, shapes, registry,
                                                        inlineRootType(nodes, rootToks, input), input)
            return emitInlineForward(steps, shapes, InlineNames(), 0, source.toTokens(),
                                     chainFinal: finalType)
        case FirstClassOptics(_) => throw DiagReportException(
            "${inlineMacroName}: this chain mints an optic value, not a read",
            input,
            hint: "@f reads `@f(value.field)`; a chain led by @use/@typeof/@ty builds an optic "
                + "instead, which has no constructor-call form. Give the chain a value to start from"
        )
        case FirstClassSetter(_, _) => throw DiagReportException(
            "${inlineMacroName}: this chain mints a Setter value, not an update",
            input,
            hint: "@f updates `@f(value.field <- v)`; a chain led by @use/@typeof/@ty builds a "
                + "Setter instead, which has no constructor-call form. Add a field after the anchor"
        )
        case SiblingBackward(source, anchorNodes, spec, targets) =>
            let names = InlineNames()
            let (anchorSteps, ownerType) = resolveInlineSteps(
                anchorNodes, shapes, registry, inlineRootType(anchorNodes, rootToks, input), input)
            let last = anchorSteps.size - 1
            if (last >= 0 && anchorSteps[last].kind.isPartialStep()) {
                return emitGuardedBlockUpdate(shapes, registry, names, anchorSteps, last, ownerType, spec,
                                              targets, source, input)
            }
            if (blockHasPartialStep(anchorSteps)) {
                throw DiagReportException(
                    "${inlineMacroName}: a sibling block anchor cannot cross a partial slot",
                    input,
                    hint: "read the value out first, then build the block from the non-Option value"
                )
            }
            let owner = emitInlineForward(anchorSteps, shapes, names, 0, source.toTokens(), chainFinal: ownerType)
            var tuple = ArrayList<Tokens>()
            for (t in targets) { tuple.add(t.toTokens()) }
            // The block rebuilds its anchor value; the anchor chain then has to
            // be rebuilt around it so the whole expression keeps its root type.
            let blockUpdate = emitBlockSpecUpdate(shapes, names, ownerType, spec,
                                                  tupleOf(tuple.toArray()), owner, input)
            let steps = ArrayList<InlineStep>()
            for (a in anchorSteps) { steps.add(a) }
            steps.add(InlineStep(InlineStepKind.Block, ownerType, -1, -1, "", blockUpdate, Tokens()))
            return emitInlineRebuild(steps, shapes, names, 0, source.toTokens(), targets[0].toTokens())
        case SiblingForward(source, anchorNodes, spec) =>
            let names = InlineNames()
            let (anchorSteps, ownerType) = resolveInlineSteps(
                anchorNodes, shapes, registry, inlineRootType(anchorNodes, rootToks, input), input)
            let last = anchorSteps.size - 1
            if (last >= 0 && anchorSteps[last].kind.isPartialStep()) {
                return emitGuardedBlockRead(shapes, registry, names, anchorSteps, last, ownerType, spec,
                                            source, input)
            }
            if (blockHasPartialStep(anchorSteps)) {
                throw DiagReportException(
                    "${inlineMacroName}: a sibling block anchor cannot cross a partial slot",
                    input,
                    hint: "read the value out first, then build the block from the non-Option value"
                )
            }
            let owner = emitInlineForward(anchorSteps, shapes, names, 0, source.toTokens(), chainFinal: ownerType)
            var parts = ArrayList<Tokens>()
            for (e in spec.entries) {
                let (st, entryType) = resolveInlineSteps(e.prefix, shapes, registry, ownerType, input)
                parts.add(emitInlineForward(st, shapes, names, 0, owner, chainFinal: entryType))
            }
            return tupleOf(parts.toArray())
    }
}

/**
 * Translates an `@f` optical expression into a single nested series of
 * constructor calls.
 *
 *   @InlineOptics[
 *       shapes: (BlkOuter, (i, BlkInner), (n, Int64)), (BlkInner, (a, Int64), (b, Int64)),
 *       root: BlkOuter,
 *       registry: (iLens, BlkOuter, i)
 *   ](o.@use(iLens).a <- 7)
 *
 * expands to `BlkOuter(BlkInner(o.i.a, 7), o.n)` -- the same update `@f`
 * performs, with the registry lookup, generic calls and closures inlined away.
 *
 * Macros cannot see types, so `shapes` supplies the constructor layout of every
 * type on the chain and `root` names the source value's type. `registry`
 * supplies the inlining metadata for first-class optics: a derived field optic
 * as `(name, OwnerType, field)`, which inlines to a field access, or a
 * hand-written one as `(name, body, { source => FWD }, { source, focus => BWD },
 * FocusType)`. Anything with no constructor-call equivalent -- prisms, affine
 * and iso slots, block updates, and chains that mint an optic value -- is a
 * compile error rather than a silent fallback to runtime dispatch.
 */
public macro InlineOptics(attr: Tokens, input: Tokens): Tokens {
    try {
        let fields = splitInlineFields(attr)
        let shapesToks = inlineField(fields, "shapes") ?? throw DiagReportException(
            "${inlineMacroName}: missing required field 'shapes'",
            input,
            hint: shapeHint()
        )
        let shapes = parseInlineShapes(shapesToks)
        let registry = match (inlineField(fields, "registry")) {
            case Some(v) => parseInlineRegistry(v, shapes)
            case None => HashMap<String, InlineOpticMeta>()
        }
        let rootToks = inlineField(fields, "root")
        rejectNestedOptics(input)
        let out = translateInline(parseOpticalExpression(input), shapes, registry, rootToks, input)
        // LUCIDA_DUMP_INLINE=1 prints the expansion one token run per line, so
        // scripts/check_codegen.sh can compare it against the hand-written
        // expression the generator wrote. Same program, provably, rather than
        // same program "within a couple of percent on the timer".
        if (let Some(_) <- getVariable("LUCIDA_DUMP_INLINE")) {
            println("@EXPAND: ${out.toString()}")
        }
        out
    } catch (e: DiagReportException) {
        println("@IDIAG: ${e.message}")
        reportCaughtDiag(e.tokens, e.message, e.hint)
        quote($input)
    } catch (e: Exception) {
        let detail = if (e.message.isEmpty()) {
            "the optical expression could not be parsed"
        } else {
            e.message
        }
        reportCaughtDiag(input, "inline translation failed: ${detail}",
                         "check the chain syntax; @InlineOptics reads the same grammar as @f")
        quote($input)
    }
}
