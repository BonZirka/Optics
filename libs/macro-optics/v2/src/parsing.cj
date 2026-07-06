macro package lucida_macro

import std.ast.*
import std.collection.*

enum OpticalExpr {
    /**
     * Refers to the cases:
     *  @Lucida(val.x.y)
     *  @Lucida(call().x.y)
     *
     * NOTE: For setter Forward == Backward(id). That's not conventional, but for us that's quite handy
     * @Lucida(call().@Optic(someSetter)) will work
     */
    | OpticsForward(Expr, Array<CompositionNode>)
    /**
     * Refers to the cases:
     *  @Lucida(val.x.y = 3)
     *  @Lucida(call().x.y = 3)
     *
     * Basically translated to:
     *  @Lucida(call().@TypeOf(call()).x.y = 3)
     */
    | OpticsBackward(Expr, Array<CompositionNode>, Expr)
    /**
     * Refers to the cases:
     *  @Lucida(@Type(String).x.y)
     *  @Lucida(@Optic(optics).x.y)
     *  @Lucida(@TypeOf(val).x.y)
     */
    | FirstClassOptics(Array<CompositionNode>)
    /**
     * Refers to the cases:
     *  @Lucida(@Type(String).x.y = 3)
     *  @Lucida(@Optic(optics).x.y = 3)
     *  @Lucida(@TypeOf(val).x.y = 3)
     */
    | FirstClassSetter(Array<CompositionNode>, Expr)

    public prop compositionNodes: Array<CompositionNode> {
        get() {
            match (this) {
                case OpticsForward(_, nodes)     => nodes
                case OpticsBackward(_, nodes, _) => nodes
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

func parseOpticalExpression(input: Tokens): OpticalExpr {
    // Scan for '<-' token to detect assignment form: @Lucida(o.x.y <- 3)
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
        match (lensExpr) {
            case maccess: MemberAccess =>
                let (baseExpr, compositionNodes) = decomposeMemberAccessExpr(maccess)
                match (baseExpr) {
                    case Some(expr) => OpticsBackward(expr, compositionNodes, valueExpr)
                    case _ => FirstClassSetter(compositionNodes, valueExpr)
                }
            case opt: OptionalExpr =>
                let (baseExpr, compositionNodes) = decomposeMemberAccessExpr(opt)
                match (baseExpr) {
                    case Some(expr) => OpticsBackward(expr, compositionNodes, valueExpr)
                    case _ => FirstClassSetter(compositionNodes, valueExpr)
                }
            case cexpr: CallExpr where cexpr.callFunc is MemberAccess =>
                let (baseExpr, compositionNodes) = decomposeMemberAccessExpr(cexpr)
                match (baseExpr) {
                    case Some(expr) => OpticsBackward(expr, compositionNodes, valueExpr)
                    case _ => FirstClassSetter(compositionNodes, valueExpr)
                }
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
                FirstClassSetter(compositionNodes, valueExpr)
            case _ =>
                throw DiagReportException(
                    "Unknown expression, passed to ${mainMacroName} macro",
                    input
                )
        }
    } else {
        // No '<-': forward or first-class form
        let exprs = parseCommaSeparatedExpressions(input)
        if (exprs.size == 0) {
            throw DiagReportException(
                "${mainMacroName} expects at least one argument",
                input
            )
        }
        match (exprs[0]) {
            case maccess: MemberAccess =>
                let (baseExpr, compositionNodes) = decomposeMemberAccessExpr(maccess)
                match (baseExpr) {
                    case Some(expr) => OpticsForward(expr, compositionNodes)
                    case _ => FirstClassOptics(compositionNodes)
                }
            case opt: OptionalExpr =>
                let (baseExpr, compositionNodes) = decomposeMemberAccessExpr(opt)
                match (baseExpr) {
                    case Some(expr) => OpticsForward(expr, compositionNodes)
                    case _ => FirstClassOptics(compositionNodes)
                }
            case cexpr: CallExpr where cexpr.callFunc is MemberAccess =>
                let (baseExpr, compositionNodes) = decomposeMemberAccessExpr(cexpr)
                match (baseExpr) {
                    case Some(expr) => OpticsForward(expr, compositionNodes)
                    case _ => FirstClassOptics(compositionNodes)
                }
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
                FirstClassOptics(compositionNodes)
            case _ =>
                throw DiagReportException(
                    "Unknown expression, passed to ${mainMacroName} macro",
                    input
                )
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
    | Type(RefExpr)                    // start anchor @Type(T)
    | TypeOf(Tokens)                   // start anchor @TypeOf(x) or auto-derived from leading identifier
    | Optic(Token)                     // start anchor @Optic(o); forces fallback
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
                    "${mainMacroName}: '@Type' expects a plain type name, e.g. @Type(GBox)",
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
                hint: "Chains support field accesses, method calls, and the @Type/@TypeOf/@Optic anchors"
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
                        "${mainMacroName}: '?.' on a total optic (coerce) — its forward cannot miss, so there is no Either to unwrap. Use '.' for a plain read.",
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
