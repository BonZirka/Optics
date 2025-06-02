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

func parseOpticalExpression(input: Tokens): OpticalExpr {
    let exprs = parseCommaSeparatedExpressions(input)
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
            let id = (cexpr.callFunc as RefExpr)?.identifier ?? throw Exception("WTF")
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

enum CompositionNode {
    | Derived(Token)        /// an identifier to derived optic
    | Type(RefExpr)         /// typename with generics
    | TypeOf(Tokens)        /// an expression, type of which should be inferred
    | Optic(Token)          /// a reference to a first class optics
    | Coerce(TypeNode)      /// coerce<Type>()
    | UserDefined(Token, ArrayList<TypeNode>, ArrayList<Argument>) /// TODO
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
                UserDefined(re.identifier, re.typeArguments, ce.arguments) // TODO: generics
            }
        case re: RefExpr =>
            if (re.typeArguments.size != 0) {
                throw DiagReportException(
                    "Generics in Derived optics expression",
                    re.toTokens(),
                    hint: "Remove or redesign"
                )
            }
            Derived(re.identifier)
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
                nodes.add(getCompositionNode(re))
                head = member.baseExpr
            case ce: CallExpr =>
                if (let Some(member) <- (ce.callFunc as MemberAccess)) {
                    let funcName = member.field
                    let genericParams = if (member.typeArguments.size == 0) { quote() } else { quote(<$(member.typeArguments)>)}
                    let arguments = ce.arguments
                    let ce = CallExpr(quote($funcName$genericParams($arguments)))
                    nodes.add(getCompositionNode(ce))
                    head = member.baseExpr
                } else { break }
            case _ => break
        }
    }
    let last = getCompositionNode(head)
    let (base, out): /* WHY?! */ (?Expr, CompositionNode) = match (last) { // TODO, report type inference bug
        case Derived(x) => (head, TypeOf(quote($x)))
        case UserDefined(name, _, args) => (head, TypeOf(quote($name($args)))) // TODO: Remove
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
