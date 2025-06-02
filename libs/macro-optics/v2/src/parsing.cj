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
    // @Lucida[unfuse](...) -> attr = [unfuse] tokens
    // @Lucida(...) -> attr = empty or just the bracket token from parser
    if (attr.size == 0) { return false }
    // Check for [modifier] pattern: first token is '[', last is ']'
    if (attr.size >= 3 && attr[0].value == "[" && attr[attr.size - 1].value == "]") {
        // Collect modifier name between brackets
        let modifier = StringBuilder()
        for (i in 1..attr.size - 1) {
            modifier.append(attr[i].value)
        }
        let mod = modifier.toString()
        if (mod == "unfuse") {
            return true
        }
        throw DiagReportException(
            "${mainMacroName}: unknown modifier [${mod}]",
            attr
        )
    }
    return false
}

func parseOpticalExpression(input: Tokens): OpticalExpr {
    let exprs = parseCommaSeparatedExpressions(input)
    if (exprs.size == 0) {
        throw DiagReportException(
            "${mainMacroName} expects at least one argument",
            input
        )
    }
    if (exprs.size > 2) {
        throw DiagReportException(
            "Expected 1-2 arguments, but got: ${exprs.size}",
            input
        )
    }
    match (exprs[0]) {
        case maccess: MemberAccess where exprs.size == 2 => 
            let (baseExpr, compositionNodes) = decomposeMemberAccessExpr(maccess)
            match (baseExpr) {
                case Some(expr) => OpticsBackward(expr, compositionNodes, exprs[1])
                case _ => FirstClassSetter(compositionNodes, exprs[1])
            }
        case maccess: MemberAccess where exprs.size == 1 => 
            let (baseExpr, compositionNodes) = decomposeMemberAccessExpr(maccess)
            match (baseExpr) {
                case Some(expr) => OpticsForward(expr, compositionNodes)
                case _ => FirstClassOptics(compositionNodes)
            }
        case cexpr: CallExpr where cexpr.callFunc is MemberAccess && exprs.size == 1 =>
            let (baseExpr, compositionNodes) = decomposeMemberAccessExpr(cexpr)
            match (baseExpr) {
                case Some(expr) => OpticsForward(expr, compositionNodes)
                case _ => FirstClassOptics(compositionNodes)
            }
        case cexpr: CallExpr where cexpr.callFunc is MemberAccess && exprs.size == 2 =>
            let (baseExpr, compositionNodes) = decomposeMemberAccessExpr(cexpr)
            match (baseExpr) {
                case Some(expr) => OpticsBackward(expr, compositionNodes, exprs[1])
                case _ => FirstClassSetter(compositionNodes, exprs[1])
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
            match {
                case exprs.size == 1 => FirstClassOptics(compositionNodes)
                case _ => FirstClassSetter(compositionNodes, exprs[1])
            }
        case _ => 
            throw DiagReportException(
                "Unknown expression, passed to ${mainMacroName} macro",
                input
            )
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
    // at/selectFirst -> Affine; everything else -> Unknown (fallback)
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
                let kind = if (re.identifier.value == "at" || re.identifier.value == "selectFirst") { Affine } else { Unknown }
                UserDefined(re.identifier, re.typeArguments, ce.arguments, kind)
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
    assert(maccess is CallExpr || maccess is MemberAccess) {
        "Expected 'CallExpr' or 'MemberAccess', but got: \n${maccess.dump()}"
    }
    var head: Expr = maccess
    let nodes = ArrayList<CompositionNode>()
    while (true) {
        match (head) {
            case member: MemberAccess =>
                let re = RefExpr(quote($(member.field)))
                let (kind, nextHead) = if (let Some(opt) <- (member.baseExpr as OptionalExpr)) {
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
                    head = if (let Some(opt) <- (member.baseExpr as OptionalExpr)) {
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
