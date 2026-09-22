macro package lucida.macrodsl

import std.ast.*
import std.collection.*

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
    | SiblingBackward(Expr, Array<CompositionNode>, Array<Array<CompositionNode>>, Array<Expr>)
    /**
     * Refers to the case:
     *  @f(s.{ .field1 .field2 })
     *
     * A sibling-block read: the block lists lens fields on the anchor
     * chain's owner value; the result is a tuple of their forwards.
     */
    | SiblingForward(Expr, Array<CompositionNode>, Array<Array<CompositionNode>>)
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
        "${mainMacroName}: unknown modifier '${attr[0].value}'",
        attr
    )
}

// Lead-expression classification shared by the forward and backward forms:
// decompose the leading member access (or @use call) into an optional base
// expression — the chain's source anchor — plus the composition nodes. None
// means the chain is first-class (no source at the call site).
private func scanBlockChains(toks: Tokens, blockOpen: Int64, input: Tokens): ArrayList<Array<CompositionNode>> {
    // Split the block content on top-level ';' — each entry is an optic chain
    // that must START at a plain field access (DOT IDENT); start fields must
    // be pairwise distinct so two chains never write the same field twice.
    let chains = ArrayList<Array<CompositionNode>>()
    let starts = ArrayList<String>()
    var k = blockOpen + 1
    var depth: Int64 = 0
    var entry = ArrayList<Token>()
    var expectField = true
    while (k < toks.size && toks[k].kind != TokenKind.RCURL) {
        let t = toks[k]
        if (t.kind == TokenKind.NL) { k += 1; continue }
        if (depth == 0 && t.value == ";") {
            if (entry.size == 0) {
                throw DiagReportException("${mainMacroName}: empty block chain", t.toTokens())
            }
            chains.add(parseBlockChain(entry, starts, input))
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
                    "${mainMacroName}: expected a block chain starting with '.'",
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
                    "${mainMacroName}: block chains must start at a field access",
                    t.toTokens(),
                    hint: "The starting segment must be a plain '.' field")
            }
            var j = k + 1
            while (j < toks.size && toks[j].kind == TokenKind.NL) { j += 1 }
            if (j < toks.size && toks[j].kind == TokenKind.LPAREN) {
                throw DiagReportException(
                    "${mainMacroName}: block chains must start at a field access",
                    toks[j].toTokens(),
                    hint: "The starting segment must be a plain '.' field, not a call")
            }
        }
        entry.add(t)
        k += 1
    }
    if (entry.size > 0) {
        chains.add(parseBlockChain(entry, starts, input))
    }
    if (chains.size == 0) {
        throw DiagReportException(
            "${mainMacroName}: the block lists no chains", input)
    }
    return chains
}

private func parseBlockChain(entry: ArrayList<Token>, starts: ArrayList<String>, input: Tokens): Array<CompositionNode> {
    // The entry sans its leading dot parses as one expression whose leftmost
    // identifier is the starting field.
    let exprs = try {
        parseCommaSeparatedExpressions(Tokens(entry))
    } catch (e: Exception) {
        throw DiagReportException(
            "${mainMacroName}: cannot parse the block chain", Tokens(entry),
            hint: "Chains are ';'-separated and start at a field: { .field1.sub; .field2 }")
    }
    if (exprs.size != 1) {
        throw DiagReportException(
            "${mainMacroName}: cannot parse the block chain", Tokens(entry))
    }
    let (base, nodes): (?Expr, Array<CompositionNode>) = match (exprs[0]) {
        case re: RefExpr => (Some(re), Array<CompositionNode>())
        case other => classifyLead(other, input)
    }
    if (let Some(b) <- base) {
        let re = b as RefExpr
        if (let Some(fieldRef) <- re) {
            for (s in starts) {
                if (s == fieldRef.identifier.value) {
                    throw DiagReportException(
                        "${mainMacroName}: two block chains start at field '${s}'",
                        fieldRef.identifier.toTokens(),
                        hint: "Starting fields must be distinct so chains never write the same field twice")
                }
            }
            starts.add(fieldRef.identifier.value)
            var arr = ArrayList<CompositionNode>()
            arr.add(Derived(fieldRef.identifier, Lens))
            // classifyLead's node list carries the auto-derived TypeOf head
            // for the base field — the entry supplies its own Derived start.
            for (idx in 1..nodes.size) { arr.add(nodes[idx]) }
            return arr.toArray()
        }
    }
    throw DiagReportException(
        "${mainMacroName}: block chains must start at a field access",
        exprs[0].toTokens(),
        hint: "The starting segment must be a plain '.' field")
}

private func blockEnd(toks: Tokens, blockOpen: Int64): Int64 {
    // The first non-NL token after the block's closing brace.
    var k = blockOpen + 1
    while (k < toks.size && toks[k].kind != TokenKind.RCURL) { k += 1 }
    k += 1
    while (k < toks.size && toks[k].kind == TokenKind.NL) { k += 1 }
    return k
}

private func parseBlockAnchor(toks: Tokens, blockIdx: Int64, input: Tokens): (Expr, Array<CompositionNode>) {
    let anchorTokens = Tokens()
    for (t in 0..blockIdx) { anchorTokens.append(toks[t]) }
    if (anchorTokens.size == 0) {
        throw DiagReportException(
            "${mainMacroName}: the block needs an anchor before '{'",
            input,
            hint: "e.g. @f(s.{ .field1 .field2 }) or @f(s.{ .field1 .field2 } <- (v1, v2))")
    }
    let anchorExprs = parseCommaSeparatedExpressions(anchorTokens)
    if (anchorExprs.size == 0) {
        throw DiagReportException(
            "${mainMacroName}: invalid anchor before the block", anchorTokens)
    }
    // A bare identifier anchor (`o.{ ... }`) has no chain segments yet.
    let (baseExpr, anchorNodes): (?Expr, Array<CompositionNode>) = match (anchorExprs[0]) {
        case re: RefExpr => (Some(re), [TypeOf(re.toTokens())])
        case other => classifyLead(other, input)
    }
    if (let Some(src) <- baseExpr) {
        return (src, anchorNodes)
    }
    throw DiagReportException(
        "${mainMacroName}: blocks require a value anchor (e.g. s.{ ... })",
        input)
}

private func parseSiblingForward(input: Tokens, blockIdx: Int64, blockOpen: Int64): OpticalExpr {
    let chains = scanBlockChains(input, blockOpen, input)
    let k = blockEnd(input, blockOpen)
    if (k < input.size) {
        throw DiagReportException(
            "${mainMacroName}: unexpected content after the block", input[k].toTokens())
    }
    let (src, anchorNodes) = parseBlockAnchor(input, blockIdx, input)
    return SiblingForward(src, anchorNodes, chains.toArray())
}

private func parseSiblingBackward(
    leftTokens: Tokens,
    rightTokens: Tokens,
    blockIdx: Int64,
    blockOpen: Int64,
    input: Tokens
): OpticalExpr {
    let chains = scanBlockChains(leftTokens, blockOpen, input)
    let k = blockEnd(leftTokens, blockOpen)
    if (k < leftTokens.size) {
        throw DiagReportException(
            "${mainMacroName}: unexpected content after the update block", leftTokens[k].toTokens())
    }
    let rightExprs = parseCommaSeparatedExpressions(rightTokens)
    if (rightExprs.size == 0) {
        throw DiagReportException(
            "${mainMacroName} expects a value after '<-'", input)
    }
    let targetExpr = rightExprs[0]
    var targets = ArrayList<Expr>()
    targets.add(targetExpr)
    if (chains.size >= 2) {
        let tl = targetExpr as TupleLiteral ?? throw DiagReportException(
            "${mainMacroName}: updating ${chains.size} chains requires a tuple target",
            targetExpr.toTokens(),
            hint: "e.g. <- (v1, v2)")
        if (tl.elements.size != chains.size) {
            throw DiagReportException(
                "${mainMacroName}: tuple target has ${tl.elements.size} elements but the block lists ${chains.size} chains",
                targetExpr.toTokens())
        }
        targets = tl.elements
    }
    let (src, anchorNodes) = parseBlockAnchor(leftTokens, blockIdx, input)
    return SiblingBackward(src, anchorNodes, chains.toArray(), targets.toArray())
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
                "${mainMacroName}: unexpected callee form",
                cexpr.toTokens()
            )
            if (id.value != opticFakeCallexprId.value) {
                throw DiagReportException(
                    "Unknown expression, passed to ${mainMacroName} macro",
                    input
                )
            }
            let (_, compositionNodes) = decomposeMemberAccessExpr(cexpr)
            (None, compositionNodes)
        case _ =>
            throw DiagReportException(
                "Unknown expression, passed to ${mainMacroName} macro",
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
                "${mainMacroName} expects a lens chain before '<-'",
                input
            )
        }
        if (rightExprs.size == 0) {
            throw DiagReportException(
                "${mainMacroName} expects a value after '<-'",
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
                "${mainMacroName} expects at least one argument",
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
            let re = ce.callFunc as RefExpr ?? throw DiagReportException("${mainMacroName}: unsupported callee form in a chain segment", ce.toTokens())
            if (re.identifier.value == typeFakeCallexprId.value) {
                Type(ce.arguments[0].expr as RefExpr ?? throw DiagReportException(
                    "${mainMacroName}: '@ty' expects a plain type name, e.g. @ty(GBox)",
                    ce.arguments[0].expr.toTokens()
                ))
            } else if (re.identifier.value == typeOfFakeCallexprId.value) {
                TypeOf(ce.arguments[0].expr.toTokens())
            } else if (re.identifier.value == opticFakeCallexprId.value) {
                let re = RefExpr(quote($(ce.arguments[0].expr)))
                Optic(re.identifier)
            } else if (re.identifier.value == coercionFakeCallexprId.value && ce.arguments.size == 0) {
                if (re.typeArguments.size != 1) { throw DiagReportException(
                    "${mainMacroName}: coerce expects exactly one type argument, e.g. coerce<Int64>()",
                    re.toTokens()
                )}
                Coerce(re.typeArguments[0])
            } else {
                UserDefined(re.identifier, re.typeArguments, ce.arguments, total)
            }
        case re: RefExpr =>
            if (re.typeArguments.size != 0) {
                throw DiagReportException(
                    "${mainMacroName}: type arguments on a bare field access are not supported",
                    re.toTokens(),
                    hint: "Drop the type arguments, or call it as a method: field<T>()"
                )
            }
            Derived(re.identifier, Lens)   // default kind; decomposeMemberAccessExpr overrides to Prism for ?.
        case _ => 
            throw DiagReportException(
                "${mainMacroName}: unsupported expression in a chain",
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
                    // The segment is partial ('?.') when an OptionalExpr is pending
                    // from above or wraps this call's own base: `xs?.at2(1)`.
                    let segTotal = !(forcePrism || (member.baseExpr is OptionalExpr))
                    // Coerce is fixed-total (RegistryIsos); a '?.' mark promises a
                    // partial read/write that cannot exist. Rejected here (not in
                    // getCompositionNode) because ce2 is synthesized and its tokens
                    // carry no positions for diagReport.
                    if (funcName.value == coercionFakeCallexprId.value && !segTotal) { throw DiagReportException(
                        "${mainMacroName}: '?.' on a total optic (coerce) — its forward cannot miss, so there is no Option to unwrap. Use '.' for a plain read.",
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
