macro package lucida.macrodsl

import std.ast.*
import std.collection.*

public macro f(input: Tokens): Tokens {
    lucidaDispatch(false, input)
}

public macro f(attr: Tokens, input: Tokens): Tokens {
    lucidaDispatch(parseModifier(attr), input)
}

private func lucidaDispatch(unfuse: Bool, input: Tokens): Tokens {
    try {
        expansionMain { =>
            evalOptics(parseOpticalExpression(input), unfuse)
        }
    } catch (e: DiagReportException) {
        println("@FDIAG: ${e.message}")
        reportCaughtDiag(e.tokens, e.message, e.hint)
        quote($input)
    } catch (e: Exception) {
        reportCaughtDiag(input, "evaluation failed: ${e.message}", "an uncaught non-diagnostic exception; see docs/fix-plans/02")
        println("@STACK: ${e.getStackTrace()}")
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
            case Derived(_, _) => ()
            case UserDefined(_, _, _, _) => ()
            case Coerce(_) => ()
            // A first-class optic is allowed anywhere: emitFusedBackwardWalk
            // and emitFusedForwardWalk split the chain at it and re-anchor
            // the rest on its focus (its own tail handling remains for the
            // last segment).
            case Optic(_) => ()
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
                composeOptics(nodes, true, false)({ forward: Token, _ : Token =>
                    quote($forward($source))
                })
            }
        case OpticsBackward(source, _, target) =>
            if (!unfuse && isFusible(nodes)) {
                emitFusedBackwardWalk(nodes, source, target)
            } else {
                composeOptics(nodes, false, true)({ _ : Token, backward: Token =>
                    quote($evalBackwardCallexprId($backward, $source, $target))
                })
            }
        case SiblingBackward(source, anchorNodes, chains, targets) =>
            if (anchorNodes.size > 1 && !isFusible(anchorNodes)) {
                throw DiagReportException(
                    "${mainMacroName}: update blocks require a fusible anchor chain",
                    source.toTokens(),
                    hint: "Anchor the block on a value: s.{ .a .b } <- (x, y)")
            }
            try {
                emitBlockBackwardWalk(source, anchorNodes, chains, targets)
            } catch (e: Exception) {
                println("@BLK-ERR: ${e.toString()}")
                throw e
            }
        case SiblingForward(source, anchorNodes, chains) =>
            if (anchorNodes.size > 1 && !isFusible(anchorNodes)) {
                throw DiagReportException(
                    "${mainMacroName}: blocks require a fusible anchor chain",
                    source.toTokens(),
                    hint: "Anchor the block on a value: s.{ .a .b }")
            }
            emitBlockForwardWalk(source, anchorNodes, chains)
        case FirstClassOptics(_) =>
            composeOptics(nodes, true, true)({ forward: Token, backward: Token =>
                quote($constructFirstClassCallexprId($forward, $backward))
            })
        case FirstClassSetter(_, target) =>
            composeOptics(nodes, false, true)({ _ : Token, backward: Token =>
                quote(
                    let $finalSetterForwardVarname = $finalizingSetterForwardCallexpr($backward, $target)
                    let $finalSetterBackwardVarname = $finalizingSetterBackwardCallexpr($backward, $target)
                    $constructFirstClassCallexprId($finalSetterForwardVarname, $finalSetterBackwardVarname)
                )
            })
    }
}

// `needF`/`needB`: which halves the terminal continuation consumes — the
// last segment emits only those (plus the expect upcast, which no terminal
// consumes).
private func composeOptics(nodes: Array<CompositionNode>, needF: Bool, needB: Bool): ((Token, Token) -> Tokens) -> Tokens {
    let iter = nodes.iterator()

    var currentNode: ?CompositionNode = iter.next()
    let magicCont: ((Tokens) -> Tokens) -> Tokens = if (let Some(node) <- currentNode) {
        match (node) {
            case Derived(input, _)     => throw DiagReportException(
                "${mainMacroName}: a derived field optic cannot start a chain here",
                input.toTokens(),
                hint: "Start the chain with the owning value, @ty, @typeof or @use"
            )
            case Type(input)        =>
                currentNode = iter.next()
                unwrapType(input)
            case TypeOf(input)      =>
                currentNode = iter.next()
                unwrapTypeOf(input)
            case Optic(input)       =>
                // Identity magic-cont: Optic is the only start node whose
                // emitter ignores the incoming magical expression (a
                // first-class optic anchors itself), so quote() is safe here.
                // Reaching this branch is normal: @f(@use(o)) and
                // @f(@use(o) <- v) both start a chain with Optic.
                { x => x(quote()) }
            case Coerce(input)      => throw DiagReportException(
                "${mainMacroName}: '${coercionFakeCallexprId.value}<Type>()' cannot start a chain",
                input.toTokens()
            )
            case UserDefined(name, _, _, _) => throw DiagReportException(
                "${mainMacroName}: user-defined method optics cannot start a chain",
                name.toTokens(),
                hint: "Start the chain with the owning value, @ty, @typeof or @use"
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
    // The pre-loop match consumes a Type/TypeOf anchor (the loop then starts
    // at node 1); an Optic-first chain is wired by the loop itself (starts at
    // node 0). Derived-first chains throw before either.
    var pos: Int64 = match (nodes[0]) {
        case Type(_) | TypeOf(_) => 1
        case _ => 0
    }
    while (let Some(node) <- currentNode) {
        let currentCont = compositionCont
        let tail: Bool = (pos == nodes.size - 1)
        match (node) {
            case Derived(input, _) =>
                compositionCont = wireSegment(first, tail, needF, needB, magicCont, currentCont,
                    derivedSplices(input, 0), { i: UInt64 => derivedSplices(input, i) })
            case Type(input)        => throw DiagReportException(
                "${mainMacroName}: @ty is only allowed at the start of a chain",
                input.toTokens()
            )
            case TypeOf(input)      => throw DiagReportException(
                "${mainMacroName}: @typeof is only allowed at the start of a chain",
                input.toTokens()
            )
            case Optic(input)       =>
                compositionCont = wireSegment(first, tail, needF, needB, magicCont, currentCont,
                    opticSplices(input, 0), { i: UInt64 => opticSplices(input, i) })
            case Coerce(input)      =>
                compositionCont = wireSegment(first, tail, needF, needB, magicCont, currentCont,
                    coercionSplices(input, 0), { i: UInt64 => coercionSplices(input, i) })
            case UserDefined(name, targs, args, _) =>
                compositionCont = wireSegment(first, tail, needF, needB, magicCont, currentCont,
                    userDefinedSplices(name, targs, args, 0),
                    { i: UInt64 => userDefinedSplices(name, targs, args, i) })
        }
        first = false
        pos = pos + 1
        currentNode = iter.next()
    }
    let currentCont = compositionCont
    { cont: (Token, Token) -> Tokens =>
        currentCont { _: Tokens, _: Token, forward: Token, backward: Token, _: UInt64 =>
            cont(forward, backward)
        }
    }
}

private func isFusableChain(nodes: Array<CompositionNode>): Bool {
    for (i in 1..nodes.size) {
        match (nodes[i]) {
            case Derived(_, _) => ()
            case UserDefined(_, _, _, _) => ()
            case Coerce(_) => ()
            // A first-class optic is allowed anywhere: emitFusedBackwardWalk
            // and emitFusedForwardWalk split the chain at it and re-anchor
            // the rest on its focus (its own tail handling remains for the
            // last segment).
            case Optic(_) => ()
            case _ => return false
        }
    }
    return true
}

// Partial (Option-producing) segments: derived prisms and partially-marked
// user optics ('?.') return Option<A> and occupy the pinned prism slots; totally-marked
// ('.') user optics walk like derived lenses.
private func isPartialProducing(node: CompositionNode): Bool {
    match (node) {
        case Derived(_, Prism) => true
        case UserDefined(_, _, _, total) => !total
        case _ => false
    }
}

// Which halves the walk consumes — the leaf bindings are demand-driven:
// reads never bind backward halves, writes never bind what their fold does
// not consume, and the deepest segment binds no next-hop magical.
enum LeafWalk {
    | Forward
    | Backward
}

private func emitLeafBindingsAndIds(nodes: Array<CompositionNode>, walk: LeafWalk, forceForwardAll!: Bool = false): (Tokens, ArrayList<Token>, ArrayList<Token>) {
    let startNode = nodes[0]
    let startMagicalExpr: Tokens = match (startNode) {
        case TypeOf(input) => quote($magicCallexprId({ => $input }))
        case Type(input) => quote($magicCallexprId<$input>())
        case Optic(input) => throw DiagReportException(
            "internal: an @use optic cannot start a fused chain", input.toTokens())
        case Coerce(t) => throw DiagReportException(
            "internal: a coerce cannot start a fused chain", t.toTokens())
        case UserDefined(name, _, _, _) => throw DiagReportException(
            "internal: a user optic cannot start a fused chain", name.toTokens())
        case Derived(input, _) => throw DiagReportException(
            "internal: a derived field cannot start a fused chain", input.toTokens())
    }
    let bindings = ArrayList<Tokens>()
    let fwdIds = ArrayList<Token>()
    let bwdIds = ArrayList<Token>()
    var prevMagical = startMagicalExpr
    let n = nodes.size
    for (i in 1..n) {
        let idx: Int64 = Int64(i - 1)
        // Forward walks consume every forward; backward walks consume the
        // forward of segment j only through its partial guard or a consumed
        // probe binding (see backwardProbeMask) — anything else is dead.
        let bindFwd: Bool = match (walk) {
            case Forward => true
            // A sibling-block tail consumes the owner probe, so every anchor
            // segment's forward probe is live (forceForwardAll).
            case Backward => forceForwardAll || isPartialProducing(nodes[i]) || backwardProbeMask(nodes)[idx]
        }
        let bindBwd: Bool = match (walk) {
            case Backward => true
            case Forward => false
        }
        match (nodes[i]) {
            case Derived(fieldTok, _) =>
                bindings.add(emitDerivedLeafBindings(idx, fieldTok, prevMagical,
                    bindForward: bindFwd, bindBackward: bindBwd))
                fwdIds.add(Token(IDENTIFIER, "__fwd${idx}"))
                bwdIds.add(Token(IDENTIFIER, "__bwd${idx}"))
                prevMagical = derivedNextMagicalExpr(idx, fieldTok)
            case UserDefined(name, targs, args, _) =>
                bindings.add(emitUserDefinedLeafBindings(idx, name, targs, args, prevMagical,
                    bindForward: bindFwd, bindBackward: bindBwd))
                fwdIds.add(Token(IDENTIFIER, "__fwd${idx}"))
                bwdIds.add(Token(IDENTIFIER, "__bwd${idx}"))
                prevMagical = userDefinedNextMagicalExpr(idx, name, targs)
            case Coerce(t) =>
                bindings.add(emitCoerceLeafBindings(idx, t, prevMagical,
                    bindForward: bindFwd, bindBackward: bindBwd))
                fwdIds.add(Token(IDENTIFIER, "__fwd${idx}"))
                bwdIds.add(Token(IDENTIFIER, "__bwd${idx}"))
                prevMagical = quote($magicCallexprId<$t>())
            case Optic(optTok) =>
                // Tail-only: the first-class optic's forward/backward are
                // pinned straight from the optic object — no registry, no
                // magical threading. Its backward is a total (S, F) -> S
                // call on the value entering the segment.
                let fwdId = Token(IDENTIFIER, "__fwd${idx}")
                let bwdId = Token(IDENTIFIER, "__bwd${idx}")
                if (i != n - 1) {
                    throw DiagReportException(
                        "${mainMacroName}: a first-class optic can only end a chain",
                        optTok.toTokens())
                }
                let fcGetters = Token(IDENTIFIER, "__FirstClassGetters")
                let fwdGetter = Token(IDENTIFIER, "forward")
                let bwdGetter = Token(IDENTIFIER, "backward")
                let fwdB = if (bindFwd) {
                    quote(let $fwdId = $fcGetters.$fwdGetter($optTok))
                } else {
                    quote()
                }
                let bwdB = if (bindBwd) {
                    quote(let $bwdId = $fcGetters.$bwdGetter($optTok))
                } else {
                    quote()
                }
                bindings.add(quote($fwdB $bwdB))
                fwdIds.add(Token(IDENTIFIER, "__fwd${idx}"))
                bwdIds.add(Token(IDENTIFIER, "__bwd${idx}"))
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
        // Identity run: `let _ = param; param` — a bare `{ p => p }` trips a
        // cjc unused-parameter false positive in generic curried positions
        // (see docs/compiler-issues.md).
        return quote(
            { $paramTok =>
                let _ = $paramTok
                $paramTok
            }
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
    // The same self-reference as the identity case: in generic curried
    // positions cjc cannot infer the parameter type of a lambda whose body
    // merely consumes it (3+ affine chains hit this at the inter-prism
    // runs), but re-binding the parameter gives it the context it needs.
    return quote(
        { $paramTok =>
            let _ = $paramTok
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
/// short-circuits to None (source preserved), a full match yields Some(focus).
private func emitPinnedPrismForward(nodes: Array<CompositionNode>, fwdIds: ArrayList<Token>, source: Expr): Tokens {
    let prismIdx = ArrayList<Int64>()
    for (i in 0..fwdIds.size) {
        if (isPartialProducing(nodes[i + 1])) {
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
            case UserDefined(_, _, _, total) =>
                // Total-marked segments go through the registry-gated apply so a
                // '.'-marked PRISM write (unconditional rebuild on miss) fails to
                // compile; partial-marked segments accept either backward arity.
                if (total) {
                    let opticsId = Token(IDENTIFIER, "__optics${Int64(bi)}")
                    quote($bwdApplyTotalCallexprId($opticsId, $bwdId, $(intermediates[bi]), $backwardInner))
                } else {
                    quote($bwdApplyCallexprId($bwdId, $(intermediates[bi]), $backwardInner))
                }
            case _ => quote($bwdId($(intermediates[bi]), $backwardInner))
        }
    }
    backwardInner
}

private func emitFusedForwardWalk(nodes: Array<CompositionNode>, source: Expr): Tokens {
    // Split at the first mid-chain first-class optic: the optic's forward
    // output becomes a plain value the rest of the chain re-anchors on
    // (recursively), and — on writes — the optic's backward rebuilds the
    // head's owner from the rest's result. The head itself is optic-free
    // and fuses as usual.
    var opticPos = -1
    var opticTokOpt: ?Token = None
    for (i in 1..nodes.size) {
        match (nodes[i]) {
            case Optic(t) => if (opticPos < 0) { opticPos = i; opticTokOpt = t }
            case _ => ()
        }
    }
    if (opticPos >= 0 && opticPos < nodes.size - 1) {
        let opticTok: Token = opticTokOpt ?? Token(IDENTIFIER, "__unknown_optic")
        let head = ArrayList<CompositionNode>()
        for (i in 0..opticPos) { head.add(nodes[i]) }
        let rest = ArrayList<CompositionNode>()
        for (i in opticPos + 1..nodes.size) { rest.add(nodes[i]) }
        let getters = Token(IDENTIFIER, "__FirstClassGetters")
        let fwdG = Token(IDENTIFIER, "forward")
        let focusTok = Token(IDENTIFIER, "__focus")
        let ownerTok = idTok("__opticOwner")
        let restNodes = ArrayList<CompositionNode>()
        restNodes.add(TypeOf(quote($focusTok)))
        for (nd in rest) { restNodes.add(nd) }
        let headSrc: Expr = source
        return quote(
            { =>
                let $ownerTok = $(if (head.size > 1) {
                    quote({ => $(emitFusedForwardWalk(head.toArray(), headSrc)) }())
                } else {
                    quote($source)
                })
                let __fwdOptic = $getters.$fwdG($opticTok)
                let $focusTok = __fwdOptic($ownerTok)
                $(emitFusedForwardWalk(restNodes.toArray(), RefExpr(quote($focusTok))))
            }()
        )
    }
    if (countPartialSegments(nodes) == 0) {
        // All-plain chain (pure lens, or lens/iso mixes): direct nested calls.
        // The READ walk runs through gated copies of the segment forwards so
        // the operator mark is checked against each segment's kind registry
        // (writes keep the ungated forwards: a '.'-write through an affine is
        // legal — its backward is sourceful).
        let (allBindings, fwdIds, _) = emitLeafBindingsAndIds(nodes, LeafWalk.Forward)
        let (gateBindings, gatedIds) = emitFwdGateBindings(nodes, fwdIds)
        let src = idTok("src")
        var walk = quote($src)
        for (i in 0..gatedIds.size) {
            walk = quote($(gatedIds[i])($walk))
        }
        let forwardId = idTok("__fusedForward")
        let forwardBinding = quote(
            $gateBindings
            let $forwardId = $pinForwardCallexprId({ => $source }, { $src => $walk })
        )
        quote(
            $allBindings
            $forwardBinding
            $forwardId($source)
        )
    } else {
        // Prism, affine, or non-lens chain
        if (!isFusableChain(nodes) || countPartialSegments(nodes) > 16) {
            // Non-fusable chains, or more pinned slots than the generated
            // walkers support (see @GeneratePrismForward) — library composition
            return composeOptics(nodes, true, false)({ forward: Token, _ : Token =>
                quote($forward($source))
            })
        }
        let (allBindings, fwdIds, _) = emitLeafBindingsAndIds(nodes, LeafWalk.Forward)
        let (gateBindings, gatedIds) = emitFwdGateBindings(nodes, fwdIds)
        let forwardEmission = emitPinnedPrismForward(nodes, gatedIds, source)
        quote(
            $allBindings
            $gateBindings
            $forwardEmission
        )
    }
}

// Emits `let __gfwdI = __fwdApplyTotal|Partial(__opticsI, __fwdI)` for every
// segment: a registry-checked identity for READ walks. Total-marked segments
// gate through Lenses/Isos (a Prisms/Affines registry is a '.'-on-partial
// mis-mark); partial-marked segments gate through Prisms/Affines (a
// Lenses/Isos registry is a '?.'-on-total mis-mark). Strict-deprecated
// overloads turn mis-marks into bespoke errors mid-chain or at the tail.
private func emitFwdGateBindings(nodes: Array<CompositionNode>, fwdIds: ArrayList<Token>): (Tokens, ArrayList<Token>) {
    var bindings = quote()
    let gatedIds = ArrayList<Token>()
    for (i in 1..nodes.size) {
        let idx: Int64 = Int64(i - 1)
        let opticsId = Token(IDENTIFIER, "__optics${idx}")
        let fwdId = fwdIds[idx]
        let gid = Token(IDENTIFIER, "__gfwd${idx}")
        // A first-class tail has no registry — its forward is already a
        // plain function, so it passes ungated.
        let binding: Tokens = match (nodes[i]) {
            case Optic(_) => quote(let $gid = $fwdId)
            case _ =>
                let gate = if (isPartialProducing(nodes[i])) { fwdApplyPartialCallexprId } else { fwdApplyTotalCallexprId }
                quote(let $gid = $gate($opticsId, $fwdId))
        }
        bindings = quote(
            $bindings
            $binding
        )
        gatedIds.add(gid)
    }
    return (bindings, gatedIds)
}

private func countPartialSegments(nodes: Array<CompositionNode>): Int64 {
    var count: Int64 = 0
    for (i in 1..nodes.size) {
        if (isPartialProducing(nodes[i])) {
            count = count + 1
        }
    }
    return count
}

private func emitBlockForwardWalk(source: Expr, anchorNodes: Array<CompositionNode>, spec: BlockSpec): Tokens {
    let ownerId = idTok("__blockOwner")
    let anchorCount = anchorNodes.size - 1
    let partialTail = isPartialProducing(anchorNodes[anchorCount])
    let ownerBinding: Tokens = if (partialTail) {
        if (anchorCount >= 1) {
            quote(let __anchorOpt = { => $(emitFusedForwardWalk(anchorNodes, source)) }())
        } else {
            quote(let __anchorOpt = Some($source))
        }
    } else if (anchorCount >= 1) {
        quote(let $ownerId = { => $(emitFusedForwardWalk(anchorNodes, source)) }())
    } else {
        quote(let $ownerId = $source)
    }
    // The entries: leaf chains read from the owner; nested entries traverse
    // their shared prefix ONCE and read the inner block at the prefix's
    // focus (the read result nests accordingly).
    var readStmts = quote()
    let tup = ArrayList<Token>()
    tup.add(Token(TokenKind.LPAREN, "("))
    for (j in 0..spec.entries.size) {
        let e = spec.entries[j]
        if (j > 0) { tup.add(Token(TokenKind.COMMA, ",")) }
        let valId = Token(IDENTIFIER, "__val${j}")
        tup.add(valId)
        match (e.inner) {
            case Some(inner) =>
                let focusTok = Token(IDENTIFIER, "__pf${j}")
                var pArr = ArrayList<CompositionNode>()
                pArr.add(TypeOf(quote($ownerId)))
                for (nd in e.prefix) { pArr.add(nd) }
                readStmts = quote(
                    $readStmts
                    let $focusTok = { =>
                        $(emitFusedForwardWalk(pArr.toArray(), RefExpr(quote($ownerId))))
                    }()
                    let $valId = $(emitBlockForwardWalk(RefExpr(quote($focusTok)), [TypeOf(quote($focusTok))], inner))
                )
            case None =>
                var arr = ArrayList<CompositionNode>()
                arr.add(TypeOf(quote($ownerId)))
                for (nd in e.prefix) { arr.add(nd) }
                readStmts = quote(
                    $readStmts
                    let $valId = { =>
                        $(emitFusedForwardWalk(arr.toArray(), RefExpr(quote($ownerId))))
                    }()
                )
        }
    }
    tup.add(Token(TokenKind.RPAREN, ")"))
    let result: Tokens = if (spec.entries.size == 1) {
        quote($(Token(IDENTIFIER, "__val0")))
    } else {
        quote($(Tokens(tup)))
    }
    if (partialTail) {
        // The anchor's focus exists only on a hit: the reads apply inside
        // the Some-guard and the whole read is an Option of the tuple.
        // Option.map handles the miss without a None literal (whose type
        // argument is not knowable at macro time).
        return quote(
            { =>
                $ownerBinding
                __anchorOpt.map({ $ownerId =>
                    $readStmts
                    $result
                })
            }()
        )
    }
    return quote(
        { =>
            $ownerBinding
            $readStmts
            $result
        }()
    )
}

private func emitBlockBackwardWalk(
    source: Expr,
    anchorNodes: Array<CompositionNode>,
    spec: BlockSpec,
    targets: Array<Expr>
): Tokens {
    let (anchorBindings, fwdIds, bwdIds) = emitLeafBindingsAndIds(anchorNodes, LeafWalk.Backward, forceForwardAll: true)
    let src = idTok("src")
    let anchorCount = anchorNodes.size - 1
    // A partial anchor tail (an affine or prism segment) makes the owner
    // exist only on a forward hit: the last probe becomes a Some-guard, the
    // block applies on the hit and the write is an identity on the miss.
    let partialTail = isPartialProducing(anchorNodes[anchorCount])
    // Owner value inside the shell: the last anchor probe, or the source
    // itself when the block sits directly on the anchor. For a partial tail
    // the owner is the guard's unwrapped probe.
    let ownerTok: Token = if (partialTail) {
        Token(IDENTIFIER, "__owner")
    } else if (anchorCount >= 1) {
        Token(IDENTIFIER, "__t${anchorCount - 1}")
    } else {
        src
    }
    // Values entering anchor segments: [src, t0, ..., t_{anchorCount-2}].
    let intermediates = ArrayList<Token>()
    intermediates.add(src)
    for (j in 0..anchorCount - 1) {
        intermediates.add(Token(IDENTIFIER, "__t${j}"))
    }
    // Anchor-chain forward probes, bound inside the shell. For a partial
    // tail the last segment's probe IS the guard.
    var probeStmts = quote()
    var probePrev = src
    let probeCount = if (partialTail) { anchorCount - 1 } else { anchorCount }
    for (j in 0..probeCount) {
        let tId = Token(IDENTIFIER, "__t${j}")
        probeStmts = quote(
            $probeStmts
            let $tId = $(fwdIds[j])($probePrev)
        )
        probePrev = tId
    }
    // Threaded entries: a leaf applies its chain's fused backward to the
    // threaded value; a nested entry traverses its shared prefix ONCE
    // (bindings, probes and focus inside this shell), emits the inner block
    // on the prefix's focus, and folds the prefix's backwards over the
    // inner block's combined result — one traversal per prefix, so target
    // effects appear exactly once.
    var stepStmts = quote()
    var prevTok = ownerTok
    for (j in 0..spec.entries.size) {
        let e = spec.entries[j]
        let stepId = Token(IDENTIFIER, "__step${j}")
        match (e.inner) {
            case Some(inner) =>
                let prefix = e.prefix
                for (nd in prefix) {
                    if (isPartialProducing(nd)) {
                        throw DiagReportException(
                            "${mainMacroName}: the shared prefix of a nested block must be total (no '?.')",
                            source.toTokens())
                    }
                }
                // The prefix continues from the threaded value: a synthetic
                // TypeOf anchor lets its bindings use the fused machinery.
                var pNodes = ArrayList<CompositionNode>()
                pNodes.add(TypeOf(quote($prevTok)))
                for (nd in prefix) { pNodes.add(nd) }
                let (pBind, pFwd, pBwd) = emitLeafBindingsAndIds(pNodes.toArray(), LeafWalk.Backward, forceForwardAll: true)
                let pCount = prefix.size
                var pProbes = quote()
                var pPrev = prevTok
                for (q in 0..pCount) {
                    let tId = Token(IDENTIFIER, "__p${j}_${q}")
                    pProbes = quote(
                        $pProbes
                        let $tId = $(pFwd[q])($pPrev)
                    )
                    pPrev = tId
                }
                // The prefix's focus is its last probe; the inner block
                // operates on it. The parent's target element is bound once
                // and destructured across the inner entries.
                let innerTok = Token(IDENTIFIER, "__inner${j}")
                let subTok = Token(IDENTIFIER, "__sub${j}")
                let childTargets = ArrayList<Expr>()
                var destructure = quote()
                if (inner.entries.size == 1) {
                    let bId = Token(IDENTIFIER, "__s${j}_0")
                    childTargets.add(RefExpr(quote($bId)))
                    destructure = quote(let $bId = $subTok)
                } else {
                    let pat = ArrayList<Token>()
                    pat.add(Token(TokenKind.LPAREN, "("))
                    for (q in 0..inner.entries.size) {
                        if (q > 0) { pat.add(Token(TokenKind.COMMA, ",")) }
                        let bId = Token(IDENTIFIER, "__s${j}_${q}")
                        pat.add(bId)
                        childTargets.add(RefExpr(quote($bId)))
                    }
                    pat.add(Token(TokenKind.RPAREN, ")"))
                    let patToks = Tokens(pat)
                    destructure = quote(let $patToks = $subTok)
                }
                let childSrc = RefExpr(quote($pPrev))
                let childAnchor = [TypeOf(quote($pPrev))]
                let innerWalk = emitBlockBackwardWalk(childSrc, childAnchor, inner, childTargets.toArray())
                let pInter = ArrayList<Token>()
                pInter.add(prevTok)
                for (q in 0..pCount - 1) {
                    pInter.add(Token(IDENTIFIER, "__p${j}_${q}"))
                }
                let prefixFold = buildBackwardWalk(pNodes.toArray(), pInter.toArray(), pBwd, innerTok)
                // IIFE-wrapped: the prefix's and the inner block's bindings
                // must not collide with the sibling steps' ids in this shell.
                stepStmts = quote(
                    $stepStmts
                    let $stepId = { =>
                        let $subTok = $(targets[j])
                        $destructure
                        $pBind
                        $pProbes
                        let $innerTok = $innerWalk
                        $prefixFold
                    }()
                )
            case None =>
                let tExpr = targets[j]
                var arr = ArrayList<CompositionNode>()
                arr.add(TypeOf(quote($prevTok)))
                for (nd in e.prefix) { arr.add(nd) }
                stepStmts = quote(
                    $stepStmts
                    let $stepId = { =>
                        $(emitFusedBackwardWalk(arr.toArray(), RefExpr(quote($prevTok)), tExpr))
                    }()
                )
        }
        prevTok = stepId
    }
    let anchorFold = buildBackwardWalk(anchorNodes, intermediates.toArray(), bwdIds, prevTok)
    if (partialTail) {
        return quote(
            { =>
                $anchorBindings
                let $src = $source
                $probeStmts
                if (let Some(__owner) <- $(fwdIds[anchorCount - 1])($probePrev)) {
                    $stepStmts
                    $anchorFold
                } else {
                    $src
                }
            }()
        )
    }
    return quote(
        { =>
            $anchorBindings
            let $src = $source
            $probeStmts
            $stepStmts
            $anchorFold
        }()
    )
}

private func emitFusedBackwardWalk(nodes: Array<CompositionNode>, source: Expr, target: Expr): Tokens {
    // Split at the first mid-chain first-class optic (see the forward walk):
    // the rest re-anchors on the optic's focus, and the optic's backward
    // rebuilds the head's owner from the rest's result before the head fold.
    var opticPos = -1
    var opticTokOpt: ?Token = None
    for (i in 1..nodes.size) {
        match (nodes[i]) {
            case Optic(t) => if (opticPos < 0) { opticPos = i; opticTokOpt = t }
            case _ => ()
        }
    }
    if (opticPos >= 0 && opticPos < nodes.size - 1) {
        let opticTok: Token = opticTokOpt ?? Token(IDENTIFIER, "__unknown_optic")
        let head = ArrayList<CompositionNode>()
        for (i in 0..opticPos) { head.add(nodes[i]) }
        let rest = ArrayList<CompositionNode>()
        for (i in opticPos + 1..nodes.size) { rest.add(nodes[i]) }
        let (headBindings, headFwd, headBwd) = emitLeafBindingsAndIds(head.toArray(), LeafWalk.Backward, forceForwardAll: true)
        let src = idTok("src")
        let anchorCount = head.size - 1
        let ownerTok: Token = if (anchorCount >= 1) {
            Token(IDENTIFIER, "__t${anchorCount - 1}")
        } else {
            src
        }
        let intermediates = ArrayList<Token>()
        intermediates.add(src)
        for (j in 0..anchorCount - 1) {
            intermediates.add(Token(IDENTIFIER, "__t${j}"))
        }
        var probeStmts = quote()
        var probePrev = src
        for (j in 0..anchorCount) {
            let tId = Token(IDENTIFIER, "__t${j}")
            probeStmts = quote(
                $probeStmts
                let $tId = $(headFwd[j])($probePrev)
            )
            probePrev = tId
        }
        let focusTok = Token(IDENTIFIER, "__focus")
        let restTok = Token(IDENTIFIER, "__rest")
        let updTok = Token(IDENTIFIER, "__upd")
        let getters = Token(IDENTIFIER, "__FirstClassGetters")
        let fwdG = Token(IDENTIFIER, "forward")
        let bwdG = Token(IDENTIFIER, "backward")
        let restNodes = ArrayList<CompositionNode>()
        restNodes.add(TypeOf(quote($focusTok)))
        for (nd in rest) { restNodes.add(nd) }
        let restWalk = emitFusedBackwardWalk(restNodes.toArray(), RefExpr(quote($focusTok)), target)
        let headFold = buildBackwardWalk(head.toArray(), intermediates.toArray(), headBwd, updTok)
        return quote(
            { =>
                $headBindings
                let $src = $source
                $probeStmts
                let __bwdOptic = $getters.$bwdG($opticTok)
                let __fwdOptic = $getters.$fwdG($opticTok)
                let $focusTok = __fwdOptic($ownerTok)
                let $restTok = { =>
                    $restWalk
                }()
                let $updTok = __bwdOptic($ownerTok, $restTok)
                $headFold
            }()
        )
    }
    if (!isFusableChain(nodes)) {
        return composeOptics(nodes, false, true)({ _ : Token, backward: Token =>
            quote($evalBackwardCallexprId($backward, $source, $target))
        })
    }
    let (allBindings, fwdIds, bwdIds) = emitLeafBindingsAndIds(nodes, LeafWalk.Backward)
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

/// Which total segments' forward probes (`__tI`) have a consumer in the
/// fused backward walk: the next probe binding (`fwdI+1(__tI)`) or segment
/// I+1's fold row — every row reads the value entering it except Coerce,
/// whose backward is sourceless. The deepest segment never binds. Binding
/// an unconsumed probe is dead work and trips the unused-variable warning.
/// The mask is independent of the walk's `from` offset: entry J depends
/// only on entries J+1.., so both the leaf binder and the recursive body
/// builder can share it.
private func backwardProbeMask(nodes: Array<CompositionNode>): Array<Bool> {
    let n = nodes.size - 1
    var mask = Array<Bool>(Int64(n), {_ => false})
    var bindNext = false
    var j = n - 1
    while (j >= 0) {
        let foldReads = j + 2 < nodes.size && match (nodes[j + 2]) {
            case Coerce(_) => false
            case _ => true
        }
        mask[j] = bindNext || foldReads
        bindNext = mask[j]
        j = j - 1
    }
    return mask
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
    let bindProbe = backwardProbeMask(nodes)
    while (i < n) {
        // Partial segments (prisms and affines) need their forward
        // unwrapped in the backward walk too — a miss keeps the source as-is.
        if (isPartialProducing(nodes[i + 1])) { break }
        if (i + 1 < n && bindProbe[i]) {
            let tId = Token(IDENTIFIER, "__t${Int64(i)}")
            let binding = quote(let $tId = $(fwdIds[i])($prev))
            stmts = quote(
                $stmts
                $binding
            )
            intermediates.add(tId)
            prev = tId
        }
        i = i + 1
    }
    if (i >= n) {
        let fold = buildBackwardWalk(nodes, intermediates.toArray(), bwdIds, fcs)
        return quote(
            $stmts
            $fold
        )
    }
    // Segment i is partial: its payload binds t_i; a miss keeps the source
    // as-is. A TRAILING partial has no consumer for the payload (its
    // backward consumes the value entering it) — bind nothing.
    let tId = Token(IDENTIFIER, "__t${Int64(i)}")
    let trailing: Bool = (i + 1 >= n)
    if (!trailing) { intermediates.add(tId) }
    let pattern: Tokens = if (trailing) { quote(Some(_)) } else { quote(Some($tId)) }
    let inner = emitFusedBackwardBody(nodes, fwdIds, bwdIds, src, fcs, i + 1, tId, intermediates)
    return quote(
        $stmts
        if (let $pattern <- $(fwdIds[i])($prev)) {
            $inner
        } else {
            $src
        }
    )
}

// ===== Segment emission (unified start/mid chain walkers) =====
//
// Every non-anchor segment kind (Derived, Optic, Coerce, UserDefined) emits the
// same shape: bind the registry (downcast), bind the segment's forward/backward,
// and hand the next magical expression to the continuation. A START segment
// binds plain copies; a MID segment first upcasts the expected registry and
// composes with the accumulated forward/backward. All per-kind differences live
// entirely in the spliced expressions built by the *Splices functions below.

// Everything the two emission templates splice, for one (kind, index) pair.
private struct SegmentSplices {
    let currMagical: Token
    let opticsId: Token
    let fwdId: Token
    let bwdId: Token
    // Optic segments anchor themselves: no incoming magical binding is emitted,
    // and their downcast registry is consumed only by a FOLLOWING segment —
    // never by a tail.
    let bindsCurrMagical: Bool
    let opticsIdUsedAtTail: Bool
    let downcastExpr: Tokens
    let fwdAccess: Tokens
    let bwdAccess: Tokens
    let nextMagicalExpr: Tokens

    init(currMagical: Token, opticsId: Token, fwdId: Token, bwdId: Token,
         bindsCurrMagical: Bool, opticsIdUsedAtTail: Bool, downcastExpr: Tokens,
         fwdAccess: Tokens, bwdAccess: Tokens, nextMagicalExpr: Tokens) {
        this.currMagical = currMagical
        this.opticsId = opticsId
        this.fwdId = fwdId
        this.bwdId = bwdId
        this.bindsCurrMagical = bindsCurrMagical
        this.opticsIdUsedAtTail = opticsIdUsedAtTail
        this.downcastExpr = downcastExpr
        this.fwdAccess = fwdAccess
        this.bwdAccess = bwdAccess
        this.nextMagicalExpr = nextMagicalExpr
    }
}

private func segmentIds(index: UInt64): (Token, Token, Token, Token) {
    (Token(IDENTIFIER, "magic${index}"),
     Token(IDENTIFIER, "optics${index}"),
     Token(IDENTIFIER, "optics${index}ImplForward"),
     Token(IDENTIFIER, "optics${index}ImplBackward"))
}

private func derivedSplices(input: Token, index: UInt64): SegmentSplices {
    let (currMagical, opticsId, fwdId, bwdId) = segmentIds(index)
    let accessForward  = Token(IDENTIFIER, "__${input.value}_impl_forward")
    let accessBackward = Token(IDENTIFIER, "__${input.value}_impl_backward")
    let accessMagic = Token(IDENTIFIER, "__${input.value}_optics")
    SegmentSplices(currMagical, opticsId, fwdId, bwdId, true, true,
        quote($currMagical.__downcast($currMagical)),
        quote($opticsId.$accessForward),
        quote($opticsId.$accessBackward),
        quote($currMagical.$accessMagic($currMagical)))
}

// START: plain registry + ungated forward/backward bindings. At the tail the
// terminal continuation consumes only the halves it demands, and an Optic
// segment's downcast registry has no consumer at all.
private func unwrapStart(splices: SegmentSplices, tail: Bool, needF: Bool, needB: Bool): (Tokens) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens =>
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            let prelude = if (splices.bindsCurrMagical) {
                quote(let $(splices.currMagical) = $currMagicalExpr)
            } else {
                quote()
            }
            let opticsLet = if (tail && !splices.opticsIdUsedAtTail) {
                quote()
            } else {
                quote(let $(splices.opticsId) = $(splices.downcastExpr))
            }
            let fwdLet = if (tail && !needF) { quote() } else {
                quote(let $(splices.fwdId) = $(splices.fwdAccess))
            }
            let bwdLet = if (tail && !needB) { quote() } else {
                quote(let $(splices.bwdId) = $(splices.bwdAccess))
            }
            quote(
                $prelude
                $opticsLet
                $fwdLet
                $bwdLet
                $(cont(splices.nextMagicalExpr, splices.opticsId, splices.fwdId, splices.bwdId, 1))
            )
        }
    }
}

// MID: upcast the expected registry, compose with the accumulated halves.
// At the tail the upcast result and the half the terminal does not demand
// are not emitted.
private func unwrapMid(splices: SegmentSplices, currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64, tail: Bool, needF: Bool, needB: Bool): ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    let newExpect = Token(IDENTIFIER, "__expect${index}")
    { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
        let prelude = if (splices.bindsCurrMagical) {
            quote(let $(splices.currMagical) = $currMagicalExpr)
        } else {
            quote()
        }
        let expectLet = if (tail) {
            quote()
        } else {
            quote(let $newExpect = $opticsUpcastCallexprId($expectOptics, $(splices.opticsId)))
        }
        let fwdLet = if (tail && !needF) { quote() } else {
            quote(let $(splices.fwdId)  = $composeForwardCallexprId($expectOptics, $(splices.opticsId))($forward, $(splices.fwdAccess), $backward, $(splices.bwdAccess)))
        }
        let bwdLet = if (tail && !needB) { quote() } else {
            quote(let $(splices.bwdId) = $composeBackwardCallexprId($expectOptics, $(splices.opticsId))($forward, $(splices.fwdAccess), $backward, $(splices.bwdAccess)))
        }
        quote(
            $prelude
            let $(splices.opticsId) = $(splices.downcastExpr)
            $expectLet
            $fwdLet
            $bwdLet
            $(cont(splices.nextMagicalExpr, newExpect, splices.fwdId, splices.bwdId, index + 1))
        )
    }
}

// Wires one segment into the composition CPS: START segments anchor on the
// magicCont chain, MID segments thread the accumulated
// (magical, expected-registry, forward, backward, index) state.
private func wireSegment(
    first: Bool,
    tail: Bool,
    needF: Bool,
    needB: Bool,
    magicCont: ((Tokens) -> Tokens) -> Tokens,
    currentCont: ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens,
    startSplices: SegmentSplices,
    midSplices: (UInt64) -> SegmentSplices
): ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    if (first) {
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            magicCont { currMagicalExpr: Tokens =>
                unwrapStart(startSplices, tail, needF, needB)(currMagicalExpr)(cont)
            }
        }
    } else {
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            currentCont { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
                unwrapMid(midSplices(index), currMagicalExpr, expectOptics, forward, backward, index, tail, needF, needB)(cont)
            }
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
    { thisMagicCont: (Tokens) -> Tokens  =>
        let tokens = quote($magicCallexprId({ => $input}))
        quote(
            $(thisMagicCont(tokens))
        )
    }
}

private func opticSplices(input: Token, index: UInt64): SegmentSplices {
    let (currMagical, opticsId, fwdId, bwdId) = segmentIds(index)
    SegmentSplices(currMagical, opticsId, fwdId, bwdId, false, false,
        quote(magicFirstClassDowncast($input)),
        quote($forwardFieldId($input)),
        quote($backwardFieldId($input)),
        quote(magicFirstClass($input)))
}

private func coercionSplices(input: TypeNode, index: UInt64): SegmentSplices {
    let (currMagical, opticsId, fwdId, bwdId) = segmentIds(index)
    let nextMagicalExpr = quote($magicCallexprId<$input>())
    SegmentSplices(currMagical, opticsId, fwdId, bwdId, true, true,
        quote($downcastMethodCoerceId($currMagical, $nextMagicalExpr)),
        quote($opticsId.$coerceForwardId($currMagical, $nextMagicalExpr)),
        quote($opticsId.$coerceBackwardId($currMagical, $nextMagicalExpr)),
        nextMagicalExpr)
}

private func userDefinedSplices(name: Token, targs: ArrayList<TypeNode>, args: ArrayList<Argument>, index: UInt64): SegmentSplices {
    let (currMagical, opticsId, fwdId, bwdId) = segmentIds(index)
    let accessForward  = Token(IDENTIFIER, "__method_${name.value}_impl_forward")
    let accessBackward = Token(IDENTIFIER, "__method_${name.value}_impl_backward")
    let accessMagic = Token(IDENTIFIER, "__method_${name.value}_optics")
    let downcastName = Token(IDENTIFIER, "__downcast_method_${name.value}")
    let gen = generics(targs)
    SegmentSplices(currMagical, opticsId, fwdId, bwdId, true, true,
        quote($currMagical.$downcastName$gen($currMagical)),
        quote($opticsId.$accessForward$gen($currMagical, $(commaSeparated(args)))),
        quote($opticsId.$accessBackward$gen($currMagical, $(commaSeparated(args)))),
        quote($currMagical.$accessMagic$gen($currMagical)))
}