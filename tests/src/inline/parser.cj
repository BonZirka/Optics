macro package tests.inline

import std.ast.*
import std.env.*
import std.collection.*

// This file is a COPY of the chain parser in lucida.macrodsl
// (core/src/macrodsl/parsing.cj), plus the three helpers and four token names
// that parser needs. It is duplicated rather than imported on purpose: the
// harness must not reach into lucida.macrodsl's internals, and making them
// public to let it would turn private macro machinery into API surface.
//
// The consequence is stated plainly: two parsers for one grammar, and the copy
// can drift. What catches drift is mechanical, not editorial —
// tests/src/inline_optics.cj expands every @f form both ways and compares
// values, and scripts/check_diagnostics.sh pins the failure surface. A grammar
// change in core that the copy does not learn shows up as a failing probe or a
// mismatched value, not as a quietly different benchmark.
//
// When core's parser changes, change it here too. The substitution to watch
// for: every diagnostic says `@InlineOptics`, not `@f`.

/// Token names the copied parser matches on. These are the same fakes
/// lucida.macrodsl's inner macros expand to; the harness sees their output.
let typeFakeCallexprId     = Token(IDENTIFIER, "__lucida_type_fake_callexpr")
let typeOfFakeCallexprId   = Token(IDENTIFIER, "__lucida_type_of_fake_callexpr")
let opticFakeCallexprId    = Token(IDENTIFIER, "__lucida_optic_fake_callexpr")
let coercionFakeCallexprId = Token(IDENTIFIER, "coerce")

class DiagReportException <: Exception {
    DiagReportException(
        message: String,
        public let tokens: Tokens,
        public let hint!: String = ""
    ) { super(message) }
}

// Re-emit a caught macro failure so it is always visible. diagReport is the
// compiler-facing channel; LUCIDA_VERBOSE_DIAGS=1 additionally printlns the
// message, which survives the paths where diagReport output is swallowed.
func reportCaughtDiag(tokens: Tokens, message: String, hint: String): Unit {
    if (let Some(_) <- getVariable("LUCIDA_VERBOSE_DIAGS")) {
        if (hint == "") {
            println("@MACRO-DIAG: ${message}")
        } else {
            println("@MACRO-DIAG: ${message} | hint: ${hint}")
        }
    }
    // Tokens handed to a macro can span several files once a nested macro has
    // expanded, and diagReport rejects that. Narrow to the first token so the
    // message still reaches the user.
    try {
        diagReport(DiagReportLevel.ERROR, tokens, message, hint)
    } catch (_: Exception) {
        if (tokens.size == 0) {
            return
        }
        diagReport(DiagReportLevel.ERROR, tokens[0..1].toTokens(), message, hint)
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

// ===== chain parser: copy of core/src/macrodsl/parsing.cj =====

/// One entry of a sibling block: a prefix chain from the block's anchor to
/// the entry's focus, optionally a nested block operating on that focus, and
/// (for writes) the target of its leaf chains (resolved at parse time; a
/// nested entry's target is the sub-tuple expression, destructured at
/// runtime so its effects run exactly once).
class BlockEntry {
    let prefix: Array<CompositionNode>
    var inner: ?BlockSpec
    var target: ?Expr

    init(prefix: Array<CompositionNode>, inner!: ?BlockSpec = None, target!: ?Expr = None) {
        this.prefix = prefix
        this.inner = inner
        this.target = target
    }
}

/// The contents of a `{ ... }` block.
class BlockSpec {
    let entries: Array<BlockEntry>

    init(entries: Array<BlockEntry>) {
        this.entries = entries
    }
}

enum OpticalExpr {
    /**
     * Refers to the cases:
     *  @f(val.x.y)
     *  @f(call().x.y)
     *
     * NOTE: For setter Forward == Backward(id). That's not conventional, but for us that's quite handy
     * @f(call().@use(someSetter)) will work
     */
    | OpticsForward(Expr, Array<CompositionNode>)
    /**
     * Refers to the cases:
     *  @f(val.x.y = 3)
     *  @f(call().x.y = 3)
     *
     * Basically translated to:
     *  @f(call().@typeof(call()).x.y = 3)
     */
    | OpticsBackward(Expr, Array<CompositionNode>, Expr)
    /**
     * Refers to the case:
     *  @f(s.{ .field1 .field2 .field3 } <- (v1, v2, v3))
     *
     * A sibling-block update: the block lists lens fields on the anchor
     * chain's owner value; the tuple target is spread across them and the
     * fields' backwards apply in order on the threaded owner.
     */
    | SiblingBackward(Expr, Array<CompositionNode>, BlockSpec, Array<Expr>)
    /**
     * Refers to the case:
     *  @f(s.{ .field1 .field2 })
     *
     * A sibling-block read: the block lists lens fields on the anchor
     * chain's owner value; the result is a tuple of their forwards.
     */
    | SiblingForward(Expr, Array<CompositionNode>, BlockSpec)
    /**
     * Refers to the cases:
     *  @f(@ty(String).x.y)
     *  @f(@use(optics).x.y)
     *  @f(@typeof(val).x.y)
     */
    | FirstClassOptics(Array<CompositionNode>)
    /**
     * Refers to the cases:
     *  @f(@ty(String).x.y = 3)
     *  @f(@use(optics).x.y = 3)
     *  @f(@typeof(val).x.y = 3)
     */
    | FirstClassSetter(Array<CompositionNode>, Expr)

    public prop compositionNodes: Array<CompositionNode> {
        get() {
            match (this) {
                case OpticsForward(_, nodes)     => nodes
                case OpticsBackward(_, nodes, _) => nodes
                case SiblingBackward(_, nodes, _, _) => nodes
                case SiblingForward(_, nodes, _) => nodes
                case FirstClassOptics(nodes)     => nodes
                case FirstClassSetter(nodes, _)  => nodes
            }
        }
    }
}

func parseModifier(attr: Tokens): Bool {
    if (attr.size == 0) { return false }
    if (attr.size == 1 && attr[0].value == "unfuse") {
        return true
    }
    throw DiagReportException(
        "${inlineMacroName}: unknown modifier '${attr[0].value}'",
        attr
    )
}

// Lead-expression classification shared by the forward and backward forms:
// decompose the leading member access (or @use call) into an optional base
// expression — the chain's source anchor — plus the composition nodes. None
// means the chain is first-class (no source at the call site).
private func scanBlockSpec(toks: Tokens, startIdx: Int64, input: Tokens): BlockSpec {
    // Collect entries separated by top-level ';'. An entry may end in a
    // nested `.{ ... }` block: its prefix chain is SHARED (traversed once)
    // and the inner block operates on the prefix's focus.
    let entries = ArrayList<BlockEntry>()
    let leafPaths = ArrayList<Array<CompositionNode>>()
    var k = startIdx
    var depth: Int64 = 0
    var entry = ArrayList<Token>()
    var expectField = true
    while (k < toks.size) {
        if (depth == 0 && toks[k].kind == TokenKind.RCURL) { break }
        let t = toks[k]
        if (t.kind == TokenKind.NL) { k += 1; continue }
        if (depth == 0 && t.value == ";") {
            if (entry.size == 0) {
                throw DiagReportException("${inlineMacroName}: empty block chain", t.toTokens())
            }
            appendBlockEntry(entry, entries, leafPaths, input)
            entry = ArrayList<Token>()
            expectField = true
            k += 1
            continue
        }
        match (t.kind) {
            case TokenKind.LPAREN | TokenKind.LCURL | TokenKind.LSQUARE => depth += 1
            case TokenKind.RPAREN | TokenKind.RCURL | TokenKind.RSQUARE => depth -= 1
            case _ => ()
        }
        if (expectField) {
            if (t.kind != TokenKind.DOT) {
                throw DiagReportException(
                    "${inlineMacroName}: expected a block chain starting with '.'",
                    t.toTokens(),
                    hint: "Chains are ';'-separated and start at a field: { .field1.sub; .field2 }")
            }
            expectField = false
            k += 1
            continue
        }
        if (entry.size == 0) {
            if (t.kind != TokenKind.IDENTIFIER) {
                throw DiagReportException(
                    "${inlineMacroName}: block chains must start at a field access",
                    t.toTokens(),
                    hint: "The starting slot must be a plain '.' field")
            }
            var j = k + 1
            while (j < toks.size && toks[j].kind == TokenKind.NL) { j += 1 }
            if (j < toks.size && toks[j].kind == TokenKind.LPAREN) {
                throw DiagReportException(
                    "${inlineMacroName}: block chains must start at a field access",
                    toks[j].toTokens(),
                    hint: "The starting slot must be a plain '.' field, not a call")
            }
        }
        entry.add(t)
        k += 1
    }
    if (entry.size > 0) {
        appendBlockEntry(entry, entries, leafPaths, input)
    }
    if (entries.size == 0) {
        throw DiagReportException(
            "${inlineMacroName}: the block lists no chains", input)
    }
    return BlockSpec(entries.toArray())
}

/// Appends one entry: a plain chain, or a chain with a nested block whose
/// prefix is shared (traversed once) and whose inner entries' leaf paths
/// join the duplicate-accident check.
private func appendBlockEntry(entry: ArrayList<Token>, entries: ArrayList<BlockEntry>, leafPaths: ArrayList<Array<CompositionNode>>, input: Tokens): Unit {
    var dotIdx = -1
    var openIdx = -1
    var depth: Int64 = 0
    var i: Int64 = 0
    while (i < entry.size) {
        let t = entry[i]
        match (t.kind) {
            case TokenKind.LPAREN | TokenKind.LCURL | TokenKind.LSQUARE => depth += 1
            case TokenKind.RPAREN | TokenKind.RCURL | TokenKind.RSQUARE => depth -= 1
            case _ => ()
        }
        if (depth == 0 && t.kind == TokenKind.DOT && i + 1 < entry.size && entry[i + 1].kind == TokenKind.LCURL) {
            dotIdx = i
            openIdx = i + 1
            break
        }
        i += 1
    }
    if (dotIdx < 0) {
        let nodes = parseBlockChain(entry, input)
        for (prev in leafPaths) {
            if (blockChainsConflict(prev, nodes)) {
                throw DiagReportException(
                    "${inlineMacroName}: block chains conflict on a shared prefix",
                    input,
                    hint: "Two leaf chains writing the identical path would overwrite each other; diverge them or drop one")
            }
        }
        entries.add(BlockEntry(nodes))
        leafPaths.add(nodes)
        return
    }
    let prefixToks = ArrayList<Token>()
    for (j in 0..dotIdx) { prefixToks.add(entry[j]) }
    let prefix = parseBlockChain(prefixToks, input)
    var innerDepth: Int64 = 0
    var k2 = openIdx + 1
    var innerEnd = entry.size
    while (k2 < entry.size) {
        if (entry[k2].kind == TokenKind.LCURL) { innerDepth += 1 }
        if (entry[k2].kind == TokenKind.RCURL) {
            if (innerDepth == 0) { innerEnd = k2; break }
            innerDepth -= 1
        }
        k2 += 1
    }
    let innerToks = Tokens()
    for (j in openIdx + 1..innerEnd) { innerToks.append(entry[j]) }
    let inner = scanBlockSpec(innerToks, 0, input)
    for (leaf in collectLeafPaths(inner)) {
        for (prev in leafPaths) {
            if (blockChainsConflict(prev, leaf)) {
                throw DiagReportException(
                    "${inlineMacroName}: block chains conflict on a shared prefix",
                    input,
                    hint: "Two leaf chains writing the identical path would overwrite each other; diverge them or drop one")
            }
        }
        leafPaths.add(leaf)
    }
    entries.add(BlockEntry(prefix, inner: Some(inner)))
}

/// The full chains of a spec's leaf entries (recursively through nesting).
private func collectLeafPaths(spec: BlockSpec): ArrayList<Array<CompositionNode>> {
    let out = ArrayList<Array<CompositionNode>>()
    for (e in spec.entries) {
        match (e.inner) {
            case Some(inner) =>
                for (leaf in collectLeafPaths(inner)) {
                    let full = ArrayList<CompositionNode>()
                    for (nd in e.prefix) { full.add(nd) }
                    for (nd in leaf) { full.add(nd) }
                    out.add(full.toArray())
                }
            case None => out.add(e.prefix)
        }
    }
    return out
}

/// Two leaf chains conflict iff identical — the same field written twice.
/// Everything else composes through the threading; quirks from unlawful
/// optics are accepted by design (see docs/api/macros/f.md#blocks).
private func blockChainsConflict(a: Array<CompositionNode>, b: Array<CompositionNode>): Bool {
    if (a.size != b.size) { return false }
    for (i in 0..a.size) {
        match ((a[i], b[i])) {
            case (Derived(fa, _), Derived(fb, _)) =>
                if (fa.value != fb.value) { return false }
            case _ => ()
        }
    }
    return true
}

private func parseBlockChain(entry: ArrayList<Token>, input: Tokens): Array<CompositionNode> {
    // The entry sans its leading dot parses as one expression whose leftmost
    // identifier is the starting field.
    let exprs = try {
        parseCommaSeparatedExpressions(Tokens(entry))
    } catch (e: Exception) {
        throw DiagReportException(
            "${inlineMacroName}: cannot parse the block chain", Tokens(entry),
            hint: "Chains are ';'-separated and start at a field: { .field1.sub; .field2 }")
    }
    if (exprs.size != 1) {
        throw DiagReportException(
            "${inlineMacroName}: cannot parse the block chain", Tokens(entry))
    }
    let (base, nodes): (?Expr, Array<CompositionNode>) = match (exprs[0]) {
        case re: RefExpr => (Some(re), Array<CompositionNode>())
        case other => classifyLead(other, input)
    }
    if (let Some(b) <- base) {
        let re = b as RefExpr
        if (let Some(fieldRef) <- re) {

            var arr = ArrayList<CompositionNode>()
            arr.add(Derived(fieldRef.identifier, Lens))
            // classifyLead's node list carries the auto-derived TypeOf head
            // for the base field — the entry supplies its own Derived start.
            for (idx in 1..nodes.size) { arr.add(nodes[idx]) }
            return arr.toArray()
        }
    }
    throw DiagReportException(
        "${inlineMacroName}: block chains must start at a field access",
        exprs[0].toTokens(),
        hint: "The starting slot must be a plain '.' field")
}

private func blockEnd(toks: Tokens, blockOpen: Int64): Int64 {
    // The first non-NL token after the block's MATCHING closing brace
    // (inner blocks may nest inside the entries).
    var depth: Int64 = 0
    var k = blockOpen + 1
    while (k < toks.size) {
        match (toks[k].kind) {
            case TokenKind.LPAREN | TokenKind.LCURL | TokenKind.LSQUARE => depth += 1
            case TokenKind.RPAREN | TokenKind.RCURL | TokenKind.RSQUARE => depth -= 1
            case _ => ()
        }
        if (depth < 0) {
            k += 1
            break
        }
        k += 1
    }
    while (k < toks.size && toks[k].kind == TokenKind.NL) { k += 1 }
    return k
}

private func leafCount(spec: BlockSpec): Int64 {
    var n: Int64 = 0
    for (e in spec.entries) {
        match (e.inner) {
            case Some(inner) => n += leafCount(inner)
            case None => n += 1
        }
    }
    return n
}

private func resolveSpecTargets(spec: BlockSpec, tl: TupleLiteral): Unit {
    if (tl.elements.size != spec.entries.size) {
        throw DiagReportException(
            "${inlineMacroName}: the nested entry's target has ${tl.elements.size} values but its block lists ${spec.entries.size} entries",
            tl.toTokens())
    }
    for (i in 0..spec.entries.size) {
        let e = spec.entries[i]
        let elem = tl.elements[i]
        match (e.inner) {
            case Some(inner) =>
                // A literal sub-tuple resolves recursively; an opaque
                // sub-tuple expression (e.g. a call) is left whole — the
                // emitter destructures it at runtime, so its effects run
                // exactly once and cjc checks the arity at the destructure.
                match (elem) {
                    case tl2: TupleLiteral => resolveSpecTargets(inner, tl2)
                    case _ => ()
                }
            case None => e.target = Some(elem)
        }
    }
}

private func parseBlockAnchor(toks: Tokens, blockIdx: Int64, input: Tokens): (Expr, Array<CompositionNode>) {
    let anchorTokens = Tokens()
    for (t in 0..blockIdx) { anchorTokens.append(toks[t]) }
    if (anchorTokens.size == 0) {
        throw DiagReportException(
            "${inlineMacroName}: the block needs an anchor before '{'",
            input,
            hint: "e.g. @f(s.{ .field1 .field2 }) or @f(s.{ .field1 .field2 } <- (v1, v2))")
    }
    let anchorExprs = parseCommaSeparatedExpressions(anchorTokens)
    if (anchorExprs.size == 0) {
        throw DiagReportException(
            "${inlineMacroName}: invalid anchor before the block", anchorTokens)
    }
    // A bare identifier anchor (`o.{ ... }`) has no chain slots yet.
    let (baseExpr, anchorNodes): (?Expr, Array<CompositionNode>) = match (anchorExprs[0]) {
        case re: RefExpr => (Some(re), [TypeOf(re.toTokens())])
        case other => classifyLead(other, input)
    }
    if (let Some(src) <- baseExpr) {
        return (src, anchorNodes)
    }
    throw DiagReportException(
        "${inlineMacroName}: blocks require a value anchor (e.g. s.{ ... })",
        input)
}

private func parseSiblingForward(input: Tokens, blockIdx: Int64, blockOpen: Int64): OpticalExpr {
    let spec = scanBlockSpec(input, blockOpen + 1, input)
    let k = blockEnd(input, blockOpen)
    if (k < input.size) {
        throw DiagReportException(
            "${inlineMacroName}: unexpected content after the block", input[k].toTokens())
    }
    let (src, anchorNodes) = parseBlockAnchor(input, blockIdx, input)
    return SiblingForward(src, anchorNodes, spec)
}

private func parseSiblingBackward(
    leftTokens: Tokens,
    rightTokens: Tokens,
    blockIdx: Int64,
    blockOpen: Int64,
    input: Tokens
): OpticalExpr {
    let spec = scanBlockSpec(leftTokens, blockOpen + 1, input)
    let k = blockEnd(leftTokens, blockOpen)
    if (k < leftTokens.size) {
        throw DiagReportException(
            "${inlineMacroName}: unexpected content after the update block", leftTokens[k].toTokens())
    }
    let rightExprs = parseCommaSeparatedExpressions(rightTokens)
    if (rightExprs.size == 0) {
        throw DiagReportException(
            "${inlineMacroName} expects a value after '<-'", input)
    }
    let targetExpr = rightExprs[0]
    var targets = ArrayList<Expr>()
    targets.add(targetExpr)
    if (spec.entries.size >= 2) {
        let tl = targetExpr as TupleLiteral ?? throw DiagReportException(
            "${inlineMacroName}: updating ${spec.entries.size} entries requires a tuple target",
            targetExpr.toTokens(),
            hint: "e.g. <- (v1, v2)")
        if (tl.elements.size != spec.entries.size) {
            throw DiagReportException(
                "${inlineMacroName}: tuple target has ${tl.elements.size} elements but the block lists ${spec.entries.size} entries",
                targetExpr.toTokens())
        }
        // Resolve each entry's target: a flat entry takes its element; a
        // nested entry's element is a sub-tuple whose elements resolve the
        // inner entries recursively (destructured at runtime, so their
        // effects run exactly once).
        resolveSpecTargets(spec, tl)
        targets = tl.elements
    }
    let (src, anchorNodes) = parseBlockAnchor(leftTokens, blockIdx, input)
    return SiblingBackward(src, anchorNodes, spec, targets.toArray())
}

private func classifyLead(lead: Expr, input: Tokens): (?Expr, Array<CompositionNode>) {
    match (lead) {
        case maccess: MemberAccess =>
            decomposeMemberAccessExpr(maccess)
        case opt: OptionalExpr =>
            decomposeMemberAccessExpr(opt)
        case cexpr: CallExpr where cexpr.callFunc is MemberAccess =>
            decomposeMemberAccessExpr(cexpr)
        case cexpr: CallExpr where cexpr.callFunc is RefExpr =>
            let id = (cexpr.callFunc as RefExpr)?.identifier ?? throw DiagReportException(
                "${inlineMacroName}: unexpected callee form",
                cexpr.toTokens()
            )
            if (id.value != opticFakeCallexprId.value) {
                throw DiagReportException(
                    "Unknown expression, passed to ${inlineMacroName} macro",
                    input
                )
            }
            let (_, compositionNodes) = decomposeMemberAccessExpr(cexpr)
            (None, compositionNodes)
        case _ =>
            throw DiagReportException(
                "Unknown expression, passed to ${inlineMacroName} macro",
                input
            )
    }
}

func parseOpticalExpression(input: Tokens): OpticalExpr {
    // Scan for '<-' token to detect assignment form: @f(o.x.y <- 3)
    var arrowIdx = -1
    for (i in 0..input.size) {
        if (input[i].value == "<-") {
            arrowIdx = i
            break
        }
    }

    if (arrowIdx >= 0) {
        // Split at '<-': left = lens chain, right = value
        let leftTokens = Tokens()
        for (i in 0..arrowIdx) {
            leftTokens.append(input[i])
        }
        let rightTokens = Tokens()
        for (i in arrowIdx + 1..input.size) {
            rightTokens.append(input[i])
        }
        // Block-update form: `anchor.{ .f1 .f2 } <- (v1, v2)` — a DOT directly
        // followed by a brace block of sibling lens fields.
        var blockIdx = -1
        var blockOpen = -1
        var i = 0
        while (i < leftTokens.size) {
            if (leftTokens[i].kind == TokenKind.DOT) {
                var j = i + 1
                while (j < leftTokens.size && leftTokens[j].kind == TokenKind.NL) { j += 1 }
                if (j < leftTokens.size && leftTokens[j].kind == TokenKind.LCURL) {
                    blockIdx = i
                    blockOpen = j
                    break
                }
            }
            i += 1
        }
        if (blockIdx >= 0) {
            return parseSiblingBackward(leftTokens, rightTokens, blockIdx, blockOpen, input)
        }
        let leftExprs = parseCommaSeparatedExpressions(leftTokens)
        let rightExprs = parseCommaSeparatedExpressions(rightTokens)
        if (leftExprs.size == 0) {
            throw DiagReportException(
                "${inlineMacroName} expects a lens chain before '<-'",
                input
            )
        }
        if (rightExprs.size == 0) {
            throw DiagReportException(
                "${inlineMacroName} expects a value after '<-'",
                input
            )
        }
        let lensExpr = leftExprs[0]
        let valueExpr = rightExprs[0]
        let (baseExpr, compositionNodes) = classifyLead(lensExpr, input)
        match (baseExpr) {
            case Some(expr) => OpticsBackward(expr, compositionNodes, valueExpr)
            case _ => FirstClassSetter(compositionNodes, valueExpr)
        }
    } else {
        // Sibling-block read: `anchor.{ .f1 .f2 }` — a DOT directly followed
        // by a brace block of sibling lens fields.
        var blockIdx = -1
        var blockOpen = -1
        var i = 0
        while (i < input.size) {
            if (input[i].kind == TokenKind.DOT) {
                var j = i + 1
                while (j < input.size && input[j].kind == TokenKind.NL) { j += 1 }
                if (j < input.size && input[j].kind == TokenKind.LCURL) {
                    blockIdx = i
                    blockOpen = j
                    break
                }
            }
            i += 1
        }
        if (blockIdx >= 0) {
            return parseSiblingForward(input, blockIdx, blockOpen)
        }
        let exprs = parseCommaSeparatedExpressions(input)
        if (exprs.size == 0) {
            throw DiagReportException(
                "${inlineMacroName} expects at least one argument",
                input
            )
        }
        let (baseExpr, compositionNodes) = classifyLead(exprs[0], input)
        match (baseExpr) {
            case Some(expr) => OpticsForward(expr, compositionNodes)
            case _ => FirstClassOptics(compositionNodes)
        }
    }
}

// Operator-derived kind expectation at parse level. The full kind matrix
// (Affine/Iso semantics, registry mapping) is decided at the call site by the
// optic's registry; the parser only records '.' (total) vs '?.' (partial).
enum OpticKind {
    | Lens       // '.'  on a derived member: total expectation
    | Prism      // '?.' on a derived member: partial expectation
}

enum CompositionNode {
    | Derived(Token, OpticKind)        // kind set by parser: . -> Lens, ?. -> Prism
    | Type(RefExpr)                    // start anchor @ty(T)
    | TypeOf(Tokens)                   // start anchor @typeof(x) or auto-derived from leading identifier
    | Optic(Token)                     // start anchor @use(o); forces fallback
    | Coerce(TypeNode)                 // kind = Iso
    | UserDefined(Token, ArrayList<TypeNode>, ArrayList<Argument>, Bool)
    // Bool = total: operator-derived call-site expectation.
    // '.' (plain member access) => true, '?.' (OptionalExpr) => false.
}

private func getCompositionNode(input: Expr, total!: Bool = true): CompositionNode {
    match (input) {
        case ce: CallExpr =>
            let re = ce.callFunc as RefExpr ?? throw DiagReportException("${inlineMacroName}: unsupported callee form in a chain slot", ce.toTokens())
            if (re.identifier.value == typeFakeCallexprId.value) {
                Type(ce.arguments[0].expr as RefExpr ?? throw DiagReportException(
                    "${inlineMacroName}: '@ty' expects a plain type name, e.g. @ty(GBox)",
                    ce.arguments[0].expr.toTokens()
                ))
            } else if (re.identifier.value == typeOfFakeCallexprId.value) {
                TypeOf(ce.arguments[0].expr.toTokens())
            } else if (re.identifier.value == opticFakeCallexprId.value) {
                let re = RefExpr(quote($(ce.arguments[0].expr)))
                Optic(re.identifier)
            } else if (re.identifier.value == coercionFakeCallexprId.value && ce.arguments.size == 0) {
                if (re.typeArguments.size != 1) { throw DiagReportException(
                    "${inlineMacroName}: coerce expects exactly one type argument, e.g. coerce<Int64>()",
                    re.toTokens()
                )}
                Coerce(re.typeArguments[0])
            } else {
                UserDefined(re.identifier, re.typeArguments, ce.arguments, total)
            }
        case re: RefExpr =>
            if (re.typeArguments.size != 0) {
                throw DiagReportException(
                    "${inlineMacroName}: type arguments on a bare field access are not supported",
                    re.toTokens(),
                    hint: "Drop the type arguments, or call it as a method: field<T>()"
                )
            }
            Derived(re.identifier, Lens)   // default kind; decomposeMemberAccessExpr overrides to Prism for ?.
        case _ => 
            throw DiagReportException(
                "${inlineMacroName}: unsupported expression in a chain",
                input.toTokens(),
                hint: "Chains support field accesses, method calls, and the @ty/@typeof/@use anchors"
            )
    }
}

private func decomposeMemberAccessExpr(maccess: Expr): (?Expr, Array<CompositionNode>) {
    assert(maccess is CallExpr || maccess is MemberAccess || maccess is OptionalExpr) {
        "Expected 'CallExpr', 'MemberAccess', or 'OptionalExpr', but got: \n${maccess.dump()}"
    }
    var head: Expr = maccess
    var forcePrism = false
    if (let Some(opt) <- (maccess as OptionalExpr)) {
        head = opt.baseExpr
        forcePrism = true
    }
    let nodes = ArrayList<CompositionNode>()
    while (true) {
        match (head) {
            case member: MemberAccess =>
                let re = RefExpr(quote($(member.field)))
                let (kind, nextHead) = if (forcePrism) {
                    forcePrism = false
                    (Prism, member.baseExpr)
                } else if (let Some(opt) <- (member.baseExpr as OptionalExpr)) {
                    (Prism, opt.baseExpr)
                } else {
                    (Lens, member.baseExpr)
                }
                nodes.add(Derived(re.identifier, kind))
                head = nextHead
            case ce: CallExpr =>
                if (let Some(member) <- (ce.callFunc as MemberAccess)) {
                    let funcName = member.field
                    // typeArguments splices with '&' separators (supertype-list
                    // semantics); the reconstructed call needs comma separation.
                    let genericParams = if (member.typeArguments.size == 0) { quote() } else { quote(<$(commaSeparated(member.typeArguments))>) }
                    let arguments = ce.arguments
                    let ce2 = CallExpr(quote($funcName$genericParams($arguments)))
                    // The slot is partial ('?.') when an OptionalExpr is pending
                    // from above or wraps this call's own base: `xs?.at2(1)`.
                    let segTotal = !(forcePrism || (member.baseExpr is OptionalExpr))
                    // Coerce is fixed-total (RegistryIsos); a '?.' mark promises a
                    // partial read/write that cannot exist. Rejected here (not in
                    // getCompositionNode) because ce2 is synthesized and its tokens
                    // carry no positions for diagReport.
                    if (funcName.value == coercionFakeCallexprId.value && !segTotal) { throw DiagReportException(
                        "${inlineMacroName}: '?.' on a total optic (coerce) — its forward cannot miss, so there is no Option to unwrap. Use '.' for a plain read.",
                        ce.toTokens()
                    )}
                    nodes.add(getCompositionNode(ce2, total: segTotal))
                    head = if (forcePrism) {
                        forcePrism = false
                        member.baseExpr
                    } else if (let Some(opt) <- (member.baseExpr as OptionalExpr)) {
                        opt.baseExpr
                    } else {
                        member.baseExpr
                    }
                } else { break }
            case _ => break
        }
    }
    let last = getCompositionNode(head)
    let (base, out): (?Expr, CompositionNode) = match (last) {
        case Derived(x, _) => (head, TypeOf(quote($x)))
        case UserDefined(name, _, args, _) => (head, TypeOf(quote($name($args))))
        case Coerce(t) => throw DiagReportException(
            "Cannot make '${coercionFakeCallexprId.value}<Type>()' method first",
            head.toTokens()
        )
        case x => (Option<Expr>.None, x)
    }
    nodes.add(out)
    nodes.reverse()
    (base, nodes.toArray())
}
