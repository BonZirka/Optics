macro package lucida_macro

import std.ast.*
import std.collection.*

enum OpticalExpr {
    /**
     * Reffers to the cases:
     *  @Lucida(val.x.y)
     *  @Lucida(call().x.y)
     *
     * NOTE: For setter Forward == Backward(id). That's not conventional, but for us that's quite handy
     * @Lucida(call().@Optic(someSetter)) will work
     */
    | OpticsForward(Expr, Array<CompositionNode>)
    /**
     * Reffers to the cases:
     *  @Lucida(val.x.y = 3)
     *  @Lucida(call().x.y = 3)
     *
     * Basically translated to:
     *  @Lucida(call().@TypeOf(call()).x.y = 3)
     */
    | OpticsBackward(Expr, Array<CompositionNode>, Expr)
    /**
     * Reffers to the cases:
     *  @Lucida(@Type(String).x.y)
     *  @Lucida(@Optic(optics).x.y)
     *  @Lucida(@TypeOf(val).x.y)
     */
    | FirstClassOptics(Array<CompositionNode>)
    /**
     * Reffers to the cases:
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

enum OpticKind {
    | Lens       // total: forward returns A;          backward takes (S, A) -> S
    | Prism      // partial: forward returns Either<S, A>; backward takes (A) -> S (sourceless)
    | Affine     // partial: forward returns Either<S, A>; backward takes (S, A) -> S (sourceful)
    | Iso        // total: forward returns A;          backward takes (A) -> S (sourceless)
    | Unknown    // fallback to binary compose
}

enum CompositionNode {
    | Derived(Token, OpticKind)        // kind set by parser: . -> Lens, ?. -> Prism
    | Type(RefExpr)                    // start anchor @Type(T)
    | TypeOf(Tokens)                   // start anchor @TypeOf(x) or auto-derived from leading identifier
    | Optic(Token)                     // start anchor @Optic(o); forces fallback
    | Coerce(TypeNode)                 // kind = Iso
    | UserDefined(Token, ArrayList<TypeNode>, ArrayList<Argument>, OpticKind)
    // Uniform-shape convention: every @LucidaOptic-declared method optic is
    // affine-shaped, so all user methods classify as Affine (fused). Raw
    // arbitrary-shape dunders must migrate to @LucidaOptic or @Lucida[unfuse].
}

private func getCompositionNode(input: Expr): CompositionNode {
    match (input) {
        case ce: CallExpr =>
            let re = ce.callFunc as RefExpr ?? throw DiagReportException("You've done something wrong", ce.toTokens())
            if (re.identifier.value == typeFakeCallexprId.value) {
                Type(ce.arguments[0].expr as RefExpr ?? throw DiagReportException(
                    "You've done something wrong",
                    ce.arguments[0].expr.toTokens()
                ))
            } else if (re.identifier.value == typeOfFakeCallexprId.value) {
                TypeOf(ce.arguments[0].expr.toTokens())
            } else if (re.identifier.value == opticFakeCallexprId.value) {
                let re = RefExpr(quote($(ce.arguments[0].expr)))
                Optic(re.identifier)
            } else if (re.identifier.value == coercionFakeCallexprId.value) {
                if (re.typeArguments.size != 1) { throw DiagReportException(
                    "A number of generic parameters should be exactly one",
                    re.typeArguments.toTokens()
                )}
                Coerce(re.typeArguments[0])
            } else {
                UserDefined(re.identifier, re.typeArguments, ce.arguments, Affine)
            }
        case re: RefExpr =>
            if (re.typeArguments.size != 0) {
                throw DiagReportException(
                    "Generics in Derived optics expression",
                    re.toTokens(),
                    hint: "Remove or redesign"
                )
            }
            Derived(re.identifier, Lens)   // default kind; decomposeMemberAccessExpr overrides to Prism for ?.
        case _ => 
            throw DiagReportException(
                "Some unexpected kind of token",
                input.toTokens()
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
                    let genericParams = if (member.typeArguments.size == 0) { quote() } else { quote(<$(member.typeArguments)>)}
                    let arguments = ce.arguments
                    let ce2 = CallExpr(quote($funcName$genericParams($arguments)))
                    nodes.add(getCompositionNode(ce2))
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
