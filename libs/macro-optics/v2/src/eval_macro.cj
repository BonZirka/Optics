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

private func isFusableChain(nodes: Array<CompositionNode>): Bool {
    for (i in 1..nodes.size) {
        match (nodes[i]) {
            case Derived(_, _) => ()
            case UserDefined(_, _, _, Affine) => ()
            case Coerce(_) => ()
            case _ => return false
        }
    }
    return true
}

// Either-producing segments: prism (Derived) and affine (UserDefined) forwards
// both return Either<T_in, A>, so both occupy the pinned prism slots.
private func isEitherProducing(node: CompositionNode): Bool {
    match (node) {
        case Derived(_, Prism) => true
        case UserDefined(_, _, _, Affine) => true
        case _ => false
    }
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
            case UserDefined(name, targs, args, Affine) =>
                bindings.add(emitUserDefinedLeafBindings(idx, name, targs, args, prevMagical))
                fwdIds.add(Token(IDENTIFIER, "__fwd${idx}"))
                bwdIds.add(Token(IDENTIFIER, "__bwd${idx}"))
                prevMagical = userDefinedNextMagicalExpr(idx, name, targs)
            case Coerce(t) =>
                bindings.add(emitCoerceLeafBindings(idx, t, prevMagical))
                fwdIds.add(Token(IDENTIFIER, "__fwd${idx}"))
                bwdIds.add(Token(IDENTIFIER, "__bwd${idx}"))
                prevMagical = quote($magicCallexprId<$t>())
            case _ => throw DiagReportException(
                "${mainMacroName}: internal: unsupported segment in fused emission",
                quote()
            )
        }
    }
    var allBindings = quote()
    for (b in bindings) {
        allBindings = quote($allBindings $b)
    }
    (allBindings, fwdIds, bwdIds)
}

/// Emits `{ param => <direct lens calls over fwdIds[from..upto)> }`; an empty
/// range yields the identity lambda.
private func emitLensRunLambda(fwdIds: ArrayList<Token>, from: Int64, upto: Int64, paramTok: Token): Tokens {
    if (from >= upto) {
        return quote(
            { $paramTok => $paramTok }
        )
    }
    var body = quote()
    var prev = paramTok
    var i = from
    while (i < upto) {
        let tId = Token(IDENTIFIER, "__t${Int64(i)}")
        let binding = quote(let $tId = $(fwdIds[i])($prev))
        body = quote(
            $body
            $binding
        )
        prev = tId
        i = i + 1
    }
    return quote(
        { $paramTok =>
            $body
            $prev
        }
    )
}

/// Emits the fused forward for a Derived-only chain containing 1..4 prisms.
/// The whole walk lives inside pinPrismForwardK; the macro emits only
/// top-level sibling lambdas (lens runs between prisms) whose parameter and
/// return types are pinned by the pre-bound segment forward ids, so Cangjie
/// can infer them. Mirrors the library's composed semantics: any prism miss
/// short-circuits to Left(original source), a full match yields Right(focus).
private func emitPinnedPrismForward(nodes: Array<CompositionNode>, fwdIds: ArrayList<Token>, source: Expr): Tokens {
    let prismIdx = ArrayList<Int64>()
    for (i in 0..fwdIds.size) {
        if (isEitherProducing(nodes[i + 1])) {
            prismIdx.add(i)
        }
    }
    let k = prismIdx.size
    let pinFn = pinPrismForwardCallexprId(k)
    let src = idTok("src")

    var args = quote(
        { => $source }
    )
    for (pi in prismIdx) {
        args = quote(
            $args,
            $(fwdIds[pi])
        )
    }
    // lens runs: before the first prism, between consecutive prisms, after the last
    var prevSeg: Int64 = 0
    for (idx in 0..k) {
        let p = prismIdx[idx]
        let paramTok = if (idx == 0) {
            src
        } else {
            Token(IDENTIFIER, "__e${Int64(prismIdx[idx - 1])}")
        }
        let runLambda = emitLensRunLambda(fwdIds, prevSeg, p, paramTok)
        args = quote(
            $args,
            $runLambda
        )
        prevSeg = p + 1
    }
    let lastParam = Token(IDENTIFIER, "__e${Int64(prismIdx[k - 1])}")
    let finalRun = emitLensRunLambda(fwdIds, prismIdx[k - 1] + 1, fwdIds.size, lastParam)
    args = quote(
        $args,
        $finalRun
    )

    let forwardId = idTok("__fusedForward")
    return quote(
        let $forwardId = $pinFn($args)
        $forwardId($source)
    )
}

/// Builds the right-to-left backward fold over pre-bound entering values.
/// Derived and affine backwards are sourceful `(T_in, focus) -> T_in`; coerce
/// backwards are sourceless `(focus) -> T_in` and consume only the accumulated
/// value. Produces: __bwd0(src, __bwd1(t0, ... __bwdN(tN-1, fcs)...))
private func buildBackwardWalk(
    nodes: Array<CompositionNode>,
    intermediates: Array<Token>,
    bwdIds: ArrayList<Token>,
    fcs: Token
): Tokens {
    var backwardInner = quote($fcs)
    let n = bwdIds.size
    for (i in 0..n) {
        let bi = n - 1 - i
        let bwdId = bwdIds[bi]
        backwardInner = match (nodes[bi + 1]) {
            case Coerce(_) => quote($bwdId($backwardInner))
            case _ => quote($bwdId($(intermediates[bi]), $backwardInner))
        }
    }
    backwardInner
}

private func emitFusedForwardWalk(nodes: Array<CompositionNode>, source: Expr): Tokens {
    if (countEitherSegments(nodes) == 0) {
        // All-plain chain (pure lens, or lens/iso mixes): direct nested calls
        let (allBindings, fwdIds, _) = emitLeafBindingsAndIds(nodes)
        let src = idTok("src")
        var walk = quote($src)
        for (i in 0..fwdIds.size) {
            walk = quote($(fwdIds[i])($walk))
        }
        let forwardId = idTok("__fusedForward")
        let forwardBinding = quote(
            let $forwardId = $pinForwardCallexprId({ => $source }, { $src => $walk })
        )
        quote(
            $allBindings
            $forwardBinding
            $forwardId($source)
        )
    } else {
        // Prism, affine, or non-lens chain
        if (!isFusableChain(nodes) || countEitherSegments(nodes) > 8) {
            // Chains with unsupported segments (e.g. Coerce) or more pinned
            // slots than the helpers support — library composition
            return composeOptics(nodes)({ forward: Token, backward: Token =>
                quote($forward($source))
            })
        }
        let (allBindings, fwdIds, _) = emitLeafBindingsAndIds(nodes)
        let forwardEmission = emitPinnedPrismForward(nodes, fwdIds, source)
        quote(
            $allBindings
            $forwardEmission
        )
    }
}

private func countEitherSegments(nodes: Array<CompositionNode>): Int64 {
    var count: Int64 = 0
    for (i in 1..nodes.size) {
        if (isEitherProducing(nodes[i])) {
            count = count + 1
        }
    }
    return count
}

private func emitFusedBackwardWalk(nodes: Array<CompositionNode>, source: Expr, target: Expr): Tokens {
    if (!isFusableChain(nodes)) {
        return composeOptics(nodes)({ forward: Token, backward: Token =>
            quote($evalBackwardCallexprId($backward, $source, $target))
        })
    }
    let (allBindings, fwdIds, bwdIds) = emitLeafBindingsAndIds(nodes)
    let src = idTok("src")
    let fcs = idTok("fcs")

    // Values entering each segment: [src, t0, ..., t_{n-1}]; the backward fold
    // consumes them right-to-left. Prism payloads bind t_i in the guard pattern.
    let intermediates = ArrayList<Token>()
    intermediates.add(src)
    let body = emitFusedBackwardBody(nodes, fwdIds, bwdIds, src, fcs, 0, src, intermediates)

    let backwardId = idTok("__fusedBackward")
    let backwardBinding = quote(
        let $backwardId = $pinBackwardCallexprId({ => $source }, { => $target }, { $src, $fcs =>
            $body
        })
    )
    quote(
        $allBindings
        $backwardBinding
        $evalBackwardCallexprId($backwardId, $source, $target)
    )
}

/// Emits the guarded forward walk plus right-to-left backward fold for segments
/// `from..n-1`, consuming the value named `enterTok`. Derived backwards are all
/// `(T_in, focus) -> T_in` with prism guards baked in, so a prism miss simply
/// yields the original source; every emitted type is concrete. For pure lens
/// chains no guards appear and the output matches the historical O(N) walk.
private func emitFusedBackwardBody(
    nodes: Array<CompositionNode>,
    fwdIds: ArrayList<Token>,
    bwdIds: ArrayList<Token>,
    src: Token,
    fcs: Token,
    from: Int64,
    enterTok: Token,
    intermediates: ArrayList<Token>
): Tokens {
    let n = fwdIds.size
    var stmts = quote()
    var prev = enterTok
    var i = from
    while (i < n) {
        // Either-producing segments (prisms and affines) need their forward
        // unwrapped in the backward walk too — a miss keeps the source as-is.
        if (isEitherProducing(nodes[i + 1])) { break }
        let tId = Token(IDENTIFIER, "__t${Int64(i)}")
        let binding = quote(let $tId = $(fwdIds[i])($prev))
        stmts = quote(
            $stmts
            $binding
        )
        intermediates.add(tId)
        prev = tId
        i = i + 1
    }
    if (i >= n) {
        let fold = buildBackwardWalk(nodes, intermediates.toArray(), bwdIds, fcs)
        return quote(
            $stmts
            $fold
        )
    }
    // Segment i is either-producing: its payload binds t_i; a miss keeps the
    // source as-is.
    let tId = Token(IDENTIFIER, "__t${Int64(i)}")
    intermediates.add(tId)
    let inner = emitFusedBackwardBody(nodes, fwdIds, bwdIds, src, fcs, i + 1, tId, intermediates)
    return quote(
        $stmts
        if (let Right($tId) <- $(fwdIds[i])($prev)) {
            $inner
        } else {
            $src
        }
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