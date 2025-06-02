macro package lucida_macro

import std.ast.*
import std.collection.*

public macro Lucida(input: Tokens): Tokens {
    lucidaDispatch(false, input)
}

public macro Lucida(attr: Tokens, input: Tokens): Tokens {
    lucidaDispatch(parseModifier(attr), input)
}

private func lucidaDispatch(unfuse: Bool, input: Tokens): Tokens {
    try {
        expansionMain { =>
            evalOptics(parseOpticalExpression(input), unfuse)
        }
    } catch (e: DiagReportException) {
        diagReport(
            DiagReportLevel.ERROR,
            e.tokens,
            e.message,
            e.hint
        )
        quote($input)
    }
}

private func expansionMain(cont: () -> Tokens): Tokens {
    quote(
        { =>
            $(cont())
        }()
    )
}

private func isFusible(nodes: Array<CompositionNode>): Bool {
    if (nodes.size == 0) { return false }
    match (nodes[0]) {
        case Optic(_) => return false
        case _ => ()
    }
    for (i in 1..nodes.size) {
        let node = nodes[i]
        match (node) {
            case Derived(_, k) => match (k) { case Unknown => return false case _ => () }
            case UserDefined(_, _, _, k) => match (k) { case Unknown => return false case _ => () }
            case Coerce(_) => ()
            case _ => return false
        }
    }
    return true
}

private func evalOptics(expr: OpticalExpr, unfuse: Bool): Tokens {
    let nodes = expr.compositionNodes
    match (expr) {
        case OpticsForward(source, _) =>
            if (!unfuse && isFusible(nodes)) {
                emitFusedForwardWalk(nodes, source)
            } else {
                composeOptics(nodes)({ forward: Token, backward: Token =>
                    quote($forward($source))
                })
            }
        case OpticsBackward(source, _, target) =>
            if (!unfuse && isFusible(nodes)) {
                emitFusedBackwardWalk(nodes, source, target)
            } else {
                composeOptics(nodes)({ forward: Token, backward: Token =>
                    quote($evalBackwardCallexprId($backward, $source, $target))
                })
            }
        case FirstClassOptics(_) =>
            composeOptics(nodes)({ forward: Token, backward: Token =>
                quote($constructFirstClassCallexprId($forward, $backward))
            })
        case FirstClassSetter(_, target) =>
            composeOptics(nodes)({ forward: Token, backward: Token =>
                quote(
                    let $finalSetterForwardVarname = $finalizingSetterForwardCallexpr($backward, $target)
                    let $finalSetterBackwardVarname = $finalizingSetterBackwardCallexpr($backward, $target)
                    $constructFirstClassCallexprId($finalSetterForwardVarname, $finalSetterBackwardVarname)
                )
            })
    }
}

private func composeOptics(nodes: Array<CompositionNode>): ((Token, Token) -> Tokens) -> Tokens {
    let iter = nodes.iterator()

    var currentNode: ?CompositionNode = iter.next()
    let magicCont: ((Tokens) -> Tokens) -> Tokens = if (let Some(node) <- currentNode) {
        match (node) {
            case Derived(input, _)     => throw DiagReportException(
                "${mainMacroName}: a derived field optic cannot start a chain here",
                input.toTokens(),
                hint: "Start the chain with the owning value, @Type, @TypeOf or @Optic"
            )
            case Type(input)        =>
                currentNode = iter.next()
                unwrapType(input)
            case TypeOf(input)      =>
                currentNode = iter.next()
                unwrapTypeOf(input)
            case Optic(input)       => { x => x(quote()) }    // TODO: REMOVE after making normal CPS. It will never be used if we encounter Optic first
            case Coerce(input)      => throw DiagReportException(
                "${mainMacroName}: '${coercionFakeCallexprId.value}<Type>()' cannot start a chain",
                input.toTokens()
            )
            case UserDefined(name, _, _, _) => throw DiagReportException(
                "${mainMacroName}: user-defined method optics cannot start a chain",
                name.toTokens(),
                hint: "Start the chain with the owning value, @Type, @TypeOf or @Optic"
            )
        }
    } else {
        throw DiagReportException(
            "${mainMacroName}: internal error: empty composition",
            quote()
        )
    }

    var compositionCont: ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens = { _ => quote() }
    var first = true
    while (let Some(node) <- currentNode) {
        let currentCont = compositionCont
        match (node) {
            case Derived(input, _) =>
                if (first) {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        magicCont { currMagicalExpr: Tokens =>
                            unwrapDerivedStart(input)(currMagicalExpr)(cont)
                        }
                    }
                } else {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        currentCont { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
                            unwrapDerived(input)(currMagicalExpr, expectOptics, forward, backward, index)(cont)
                        }
                    }
                }
            case Type(input)        => throw DiagReportException(
                "${mainMacroName}: @Type is only allowed at the start of a chain",
                input.toTokens()
            )
            case TypeOf(input)      => throw DiagReportException(
                "${mainMacroName}: @TypeOf is only allowed at the start of a chain",
                input.toTokens()
            )
            case Optic(input)       => 
                if (first) {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        magicCont { currMagicalExpr: Tokens =>
                            unwrapOpticStart(input)(currMagicalExpr)(cont)
                        }
                    }
                } else {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        currentCont { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
                            unwrapOptic(input)(currMagicalExpr, expectOptics, forward, backward, index)(cont)
                        }
                    }
                }
            case Coerce(input)      => 
                if (first) {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        magicCont { currMagicalExpr: Tokens =>
                            unwrapCoercionStart(input)(currMagicalExpr)(cont)
                        }
                    }
                } else {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        currentCont { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
                            unwrapCoercion(input)(currMagicalExpr, expectOptics, forward, backward, index)(cont)
                        }
                    }
                }
            case UserDefined(name, targs, args, _) =>
                if (first) {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        magicCont { currMagicalExpr: Tokens =>
                            unwrapUserDefinedStart(name, targs, args)(currMagicalExpr)(cont)
                        }
                    }
                } else {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        currentCont { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
                            unwrapUserDefined(name, targs, args)(currMagicalExpr, expectOptics, forward, backward, index)(cont)
                        }
                    }
                }
        }
        first = false
        currentNode = iter.next()
    }
    let currentCont = compositionCont
    { cont: (Token, Token) -> Tokens =>
        currentCont { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
            cont(forward, backward)
        }
    }
}

private func isPureLensChain(nodes: Array<CompositionNode>): Bool {
    for (i in 1..nodes.size) {
        match (nodes[i]) {
            case Derived(_, k) => match (k) { case Lens => () case _ => return false }
            case _ => return false
        }
    }
    return true
}

private func emitLeafBindingsAndIds(nodes: Array<CompositionNode>): (Tokens, ArrayList<Token>, ArrayList<Token>) {
    let startNode = nodes[0]
    let startMagicalExpr: Tokens = match (startNode) {
        case TypeOf(input) => quote($magicCallexprId({ => $input }))
        case Type(input) => quote($magicCallexprId<$input>())
        case _ => throw DiagReportException("internal: unsupported start anchor for fused emission", quote())
    }
    let bindings = ArrayList<Tokens>()
    let fwdIds = ArrayList<Token>()
    let bwdIds = ArrayList<Token>()
    var prevMagical = startMagicalExpr
    for (i in 1..nodes.size) {
        let idx: Int64 = Int64(i - 1)
        match (nodes[i]) {
            case Derived(fieldTok, _) =>
                bindings.add(emitDerivedLeafBindings(idx, fieldTok, prevMagical))
                fwdIds.add(Token(IDENTIFIER, "__fwd${idx}"))
                bwdIds.add(Token(IDENTIFIER, "__bwd${idx}"))
                prevMagical = derivedNextMagicalExpr(idx, fieldTok)
            case _ => throw DiagReportException("internal: non-Derived segment in pure-Lens fused path", quote())
        }
    }
    var allBindings = quote()
    for (b in bindings) {
        allBindings = quote($allBindings $b)
    }
    (allBindings, fwdIds, bwdIds)
}

private func buildForwardWalk(fwdIds: ArrayList<Token>, src: Token): Tokens {
    var walk = quote($src)
    for (i in 0..fwdIds.size) {
        let fwdId = fwdIds[i]
        walk = quote($fwdId($walk))
    }
    walk
}

/// Builds backward walk using pre-bound forward intermediates.
/// intermediates[i] = Token for i-th forward result (t0=src, t1=fwd0(t0), ...).
/// Produces: __bwd0(__t0, __bwd1(__t1, ... __bwdN(__tN, fcs)...))
private func buildBackwardWalk(
    intermediates: Array<Token>,
    bwdIds: ArrayList<Token>,
    fcs: Token
): Tokens {
    var backwardInner = quote($fcs)
    let n = bwdIds.size
    for (i in 0..n) {
        let bi = n - 1 - i
        let bwdId = bwdIds[bi]
        let srcAtI = intermediates[bi]
        backwardInner = quote($bwdId($srcAtI, $backwardInner))
    }
    backwardInner
}

private func emitFusedForwardWalk(nodes: Array<CompositionNode>, source: Expr): Tokens {
    if (!isPureLensChain(nodes)) {
        return composeOptics(nodes)({ forward: Token, backward: Token =>
            quote($forward($source))
        })
    }
    let (allBindings, fwdIds, _) = emitLeafBindingsAndIds(nodes)
    let src = idTok("src")
    let forwardWalk = buildForwardWalk(fwdIds, src)
    let forwardId = idTok("__fusedForward")
    let forwardBinding = quote(
        let $forwardId = $pinForwardCallexprId({ => $source }, { $src => $forwardWalk })
    )
    quote(
        $allBindings
        $forwardBinding
        $forwardId($source)
    )
}

private func emitFusedBackwardWalk(nodes: Array<CompositionNode>, source: Expr, target: Expr): Tokens {
    if (!isPureLensChain(nodes)) {
        return composeOptics(nodes)({ forward: Token, backward: Token =>
            quote($evalBackwardCallexprId($backward, $source, $target))
        })
    }
    let (allBindings, fwdIds, bwdIds) = emitLeafBindingsAndIds(nodes)
    let src = idTok("src")
    let fcs = idTok("fcs")

    // Build forward intermediate bindings (inside the lambda body).
    // t0 = src, t1 = __fwd0(t0), t2 = __fwd1(t1), ...
    let n = fwdIds.size
    let intermediates = ArrayList<Token>()
    intermediates.add(src)
    var lambdaBody = quote()
    var prevT = src
    for (i in 0..n) {
        let tId = Token(IDENTIFIER, "__t${Int64(i)}")
        let fwdId = fwdIds[i]
        let binding = quote(let $tId = $fwdId($prevT))
        lambdaBody = if (i == 0) {
            quote($binding)
        } else {
            quote(
                $lambdaBody
                $binding
            )
        }
        intermediates.add(tId)
        prevT = tId
    }

    let backwardWalk = buildBackwardWalk(intermediates.toArray(), bwdIds, fcs)
    lambdaBody = quote(
        $lambdaBody
        $backwardWalk
    )

    let backwardId = idTok("__fusedBackward")
    let backwardBinding = quote(
        let $backwardId = $pinBackwardCallexprId({ => $source }, { => $target }, { $src, $fcs => $lambdaBody })
    )
    quote(
        $allBindings
        $backwardBinding
        $evalBackwardCallexprId($backwardId, $source, $target)
    )
}

private func unwrapDerivedStart(input: Token): (Tokens) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens =>
        let index: UInt64 = 0
        let currMagical = Token(IDENTIFIER, "magic${index}")
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")

        let accessForward  = Token(IDENTIFIER, "__${input.value}_impl_forward")
        let accessBackward = Token(IDENTIFIER, "__${input.value}_impl_backward")
        let accessMagic = Token(IDENTIFIER, "__${input.value}_optics")
        let nextMagicalExpr = quote($currMagical.$accessMagic($currMagical))
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $currMagical = $currMagicalExpr
                let $opticsId = $currMagical.__downcast($currMagical)
                let $opticsIdImplForward = $opticsId.$accessForward
                let $opticsIdImplBackward = $opticsId.$accessBackward
                $(cont(nextMagicalExpr, opticsId, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}


private func unwrapDerived(input: Token): (Tokens, Token, Token, Token, UInt64) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
        let currMagical = Token(IDENTIFIER, "magic${index}")
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")

        let accessForward  = Token(IDENTIFIER, "__${input.value}_impl_forward")
        let accessBackward = Token(IDENTIFIER, "__${input.value}_impl_backward")
        let accessMagic = Token(IDENTIFIER, "__${input.value}_optics")
        let nextMagicalExpr = quote($currMagical.$accessMagic($currMagical))

        let newExpect = Token(IDENTIFIER, "__expect${index}")
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $currMagical = $currMagicalExpr
                let $opticsId = $currMagical.__downcast($currMagical)
                let $newExpect = $opticsUpcastCallexprId($expectOptics, $opticsId)
                let $opticsIdImplForward  = $composeForwardCallexprId($expectOptics, $opticsId)($forward, $opticsId.$accessForward, $backward, $opticsId.$accessBackward)
                let $opticsIdImplBackward = $composeBackwardCallexprId($expectOptics, $opticsId)($forward, $opticsId.$accessForward, $backward, $opticsId.$accessBackward)
                $(cont(nextMagicalExpr, newExpect, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}

private func unwrapType(input: RefExpr): ((Tokens) -> Tokens) -> Tokens {
    { thisMagicCont: (Tokens) -> Tokens  =>
        let tokens = quote($magicCallexprId<$input>())
        quote(
            $(thisMagicCont(tokens))
        )
    }
}

private func unwrapTypeOf(input: Tokens): ((Tokens) -> Tokens) -> Tokens {
    let magicId = Token(IDENTIFIER, "magicStart")
    { thisMagicCont: (Tokens) -> Tokens  =>
        let tokens = quote($magicCallexprId({ => $input}))
        quote(
            $(thisMagicCont(tokens))
        )
    }
}

private func unwrapOpticStart(input: Token): (Tokens) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { _: Tokens =>
        let index: UInt64 = 0
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")
        let nextMagicalExpr = quote(magicFirstClass($input))
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $opticsId = magicFirstClassDowncast($input)
                let $opticsIdImplForward = $forwardFieldId($input)
                let $opticsIdImplBackward = $backwardFieldId($input)
                $(cont(nextMagicalExpr, opticsId, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}


private func unwrapOptic(input: Token): (Tokens, Token, Token, Token, UInt64) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")
        let nextMagicalExpr = quote(magicFirstClass($input))
        let newExpect = Token(IDENTIFIER, "__expect${index}")
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $opticsId = magicFirstClassDowncast($input)
                let $newExpect = $opticsUpcastCallexprId($expectOptics, $opticsId)
                let $opticsIdImplForward  = $composeForwardCallexprId($expectOptics, $opticsId)($forward, $forwardFieldId($input), $backward, $backwardFieldId($input))
                let $opticsIdImplBackward = $composeBackwardCallexprId($expectOptics, $opticsId)($forward, $forwardFieldId($input), $backward, $backwardFieldId($input))
                $(cont(nextMagicalExpr, newExpect, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}

private func unwrapCoercionStart(input: TypeNode): (Tokens) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens =>
        let index: UInt64 = 0
        let currMagical = Token(IDENTIFIER, "magic${index}")
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")

        let nextMagicalExpr = quote($magicCallexprId<$input>())
        let accessForward  = quote($coerceForwardId($currMagical, $nextMagicalExpr))
        let accessBackward = quote($coerceBackwardId($currMagical, $nextMagicalExpr))

        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $currMagical = $currMagicalExpr
                let $opticsId = $downcastMethodCoerceId($currMagical, $nextMagicalExpr)
                let $opticsIdImplForward = $opticsId.$accessForward
                let $opticsIdImplBackward = $opticsId.$accessBackward
                $(cont(nextMagicalExpr, opticsId, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}

private func unwrapCoercion(input: TypeNode): (Tokens, Token, Token, Token, UInt64) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
        let currMagical = Token(IDENTIFIER, "magic${index}")
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")

        let nextMagicalExpr = quote($magicCallexprId<$input>())
        let accessForward  = quote($coerceForwardId($currMagical, $nextMagicalExpr))
        let accessBackward = quote($coerceBackwardId($currMagical, $nextMagicalExpr))

        let newExpect = Token(IDENTIFIER, "__expect${index}")
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $currMagical = $currMagicalExpr
                let $opticsId = $downcastMethodCoerceId($currMagical, $nextMagicalExpr)
                let $newExpect = $opticsUpcastCallexprId($expectOptics, $opticsId)
                let $opticsIdImplForward  = $composeForwardCallexprId($expectOptics, $opticsId)($forward, $opticsId.$accessForward, $backward, $opticsId.$accessBackward)
                let $opticsIdImplBackward = $composeBackwardCallexprId($expectOptics, $opticsId)($forward, $opticsId.$accessForward, $backward, $opticsId.$accessBackward)
                $(cont(nextMagicalExpr, newExpect, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}

private func unwrapUserDefinedStart(name: Token, targs: ArrayList<TypeNode>, args: ArrayList<Argument>): (Tokens) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens =>
        let index: UInt64 = 0
        let currMagical = Token(IDENTIFIER, "magic${index}")
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")

        let accessForward  = Token(IDENTIFIER, "__method_${name.value}_impl_forward")
        let accessBackward = Token(IDENTIFIER, "__method_${name.value}_impl_backward")
        let accessMagic = Token(IDENTIFIER, "__method_${name.value}_optics")
        let downcastName = Token(IDENTIFIER, "__downcast_method_${name.value}")
        let nextMagicalExpr = quote($currMagical.$accessMagic$(generics(targs))($currMagical))
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $currMagical = $currMagicalExpr
                let $opticsId = $currMagical.$downcastName$(generics(targs))($currMagical)
                let $opticsIdImplForward = $opticsId.$accessForward$(generics(targs))($currMagical, $(commaSeparated(args)))
                let $opticsIdImplBackward = $opticsId.$accessBackward$(generics(targs))($currMagical, $(commaSeparated(args)))
                $(cont(nextMagicalExpr, opticsId, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}


private func unwrapUserDefined(name: Token, targs: ArrayList<TypeNode>, args: ArrayList<Argument>): (Tokens, Token, Token, Token, UInt64) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
        let currMagical = Token(IDENTIFIER, "magic${index}")
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")

        let accessForward  = Token(IDENTIFIER, "__method_${name.value}_impl_forward")
        let accessBackward = Token(IDENTIFIER, "__method_${name.value}_impl_backward")
        let accessMagic = Token(IDENTIFIER, "__method_${name.value}_optics")
        let downcastName = Token(IDENTIFIER, "__downcast_method_${name.value}")
        let nextMagicalExpr = quote($currMagical.$accessMagic$(generics(targs))($currMagical))

        let newExpect = Token(IDENTIFIER, "__expect${index}")
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $currMagical = $currMagicalExpr
                let $opticsId = $currMagical.$downcastName$(generics(targs))($currMagical)
                let $newExpect = $opticsUpcastCallexprId($expectOptics, $opticsId)
                let $opticsIdImplForward  = $composeForwardCallexprId($expectOptics, $opticsId)($forward, $opticsId.$accessForward$(generics(targs))($currMagical, $(commaSeparated(args))), $backward, $opticsId.$accessBackward$(generics(targs))($currMagical, $(commaSeparated(args))))
                let $opticsIdImplBackward = $composeBackwardCallexprId($expectOptics, $opticsId)($forward, $opticsId.$accessForward$(generics(targs))($currMagical, $(commaSeparated(args))), $backward, $opticsId.$accessBackward$(generics(targs))($currMagical, $(commaSeparated(args))))
                $(cont(nextMagicalExpr, newExpect, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}