macro package lucida.macrodsl

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
            case Derived(_, _) => ()
            case UserDefined(_, _, _, _) => ()
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
            case Optic(input)       =>
                // Identity magic-cont: Optic is the only start node whose
                // emitter ignores the incoming magical expression (a
                // first-class optic anchors itself), so quote() is safe here.
                // Reaching this branch is normal: @Lucida(@Optic(o)) and
                // @Lucida(@Optic(o) <- v) both start a chain with Optic.
                { x => x(quote()) }
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
                compositionCont = wireSegment(first, magicCont, currentCont,
                    derivedSplices(input, 0), { i: UInt64 => derivedSplices(input, i) })
            case Type(input)        => throw DiagReportException(
                "${mainMacroName}: @Type is only allowed at the start of a chain",
                input.toTokens()
            )
            case TypeOf(input)      => throw DiagReportException(
                "${mainMacroName}: @TypeOf is only allowed at the start of a chain",
                input.toTokens()
            )
            case Optic(input)       =>
                compositionCont = wireSegment(first, magicCont, currentCont,
                    opticSplices(input, 0), { i: UInt64 => opticSplices(input, i) })
            case Coerce(input)      =>
                compositionCont = wireSegment(first, magicCont, currentCont,
                    coercionSplices(input, 0), { i: UInt64 => coercionSplices(input, i) })
            case UserDefined(name, targs, args, _) =>
                compositionCont = wireSegment(first, magicCont, currentCont,
                    userDefinedSplices(name, targs, args, 0),
                    { i: UInt64 => userDefinedSplices(name, targs, args, i) })
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
            case UserDefined(_, _, _, _) => ()
            case Coerce(_) => ()
            case _ => return false
        }
    }
    return true
}

// Either-producing segments: derived prisms and partially-marked user optics
// ('?.') return Either<T_in, A> and occupy the pinned prism slots; totally-marked
// ('.') user optics walk like derived lenses.
private func isEitherProducing(node: CompositionNode): Bool {
    match (node) {
        case Derived(_, Prism) => true
        case UserDefined(_, _, _, total) => !total
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
            case UserDefined(name, targs, args, _) =>
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
    if (countEitherSegments(nodes) == 0) {
        // All-plain chain (pure lens, or lens/iso mixes): direct nested calls.
        // The READ walk runs through gated copies of the segment forwards so
        // the operator mark is checked against each segment's kind registry
        // (writes keep the ungated forwards: a '.'-write through an affine is
        // legal — its backward is sourceful).
        let (allBindings, fwdIds, _) = emitLeafBindingsAndIds(nodes)
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
        if (!isFusableChain(nodes) || countEitherSegments(nodes) > 16) {
            // Non-fusable chains, or more pinned slots than the generated
            // walkers support (see @GeneratePrismForward) — library composition
            return composeOptics(nodes)({ forward: Token, backward: Token =>
                quote($forward($source))
            })
        }
        let (allBindings, fwdIds, _) = emitLeafBindingsAndIds(nodes)
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
        let gate = if (isEitherProducing(nodes[i])) { fwdApplyPartialCallexprId } else { fwdApplyTotalCallexprId }
        let gid = Token(IDENTIFIER, "__gfwd${idx}")
        bindings = quote(
            $bindings
            let $gid = $gate($opticsId, $fwdId)
        )
        gatedIds.add(gid)
    }
    return (bindings, gatedIds)
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
    // Optic segments anchor themselves: no incoming magical binding is emitted.
    let bindsCurrMagical: Bool
    let downcastExpr: Tokens
    let fwdAccess: Tokens
    let bwdAccess: Tokens
    let nextMagicalExpr: Tokens

    init(currMagical: Token, opticsId: Token, fwdId: Token, bwdId: Token,
         bindsCurrMagical: Bool, downcastExpr: Tokens, fwdAccess: Tokens,
         bwdAccess: Tokens, nextMagicalExpr: Tokens) {
        this.currMagical = currMagical
        this.opticsId = opticsId
        this.fwdId = fwdId
        this.bwdId = bwdId
        this.bindsCurrMagical = bindsCurrMagical
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
    SegmentSplices(currMagical, opticsId, fwdId, bwdId, true,
        quote($currMagical.__downcast($currMagical)),
        quote($opticsId.$accessForward),
        quote($opticsId.$accessBackward),
        quote($currMagical.$accessMagic($currMagical)))
}

// START: plain registry + ungated forward/backward bindings.
private func unwrapStart(splices: SegmentSplices): (Tokens) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens =>
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            let prelude = if (splices.bindsCurrMagical) {
                quote(let $(splices.currMagical) = $currMagicalExpr)
            } else {
                quote()
            }
            quote(
                $prelude
                let $(splices.opticsId) = $(splices.downcastExpr)
                let $(splices.fwdId) = $(splices.fwdAccess)
                let $(splices.bwdId) = $(splices.bwdAccess)
                $(cont(splices.nextMagicalExpr, splices.opticsId, splices.fwdId, splices.bwdId, 1))
            )
        }
    }
}

// MID: upcast the expected registry, compose with the accumulated halves.
private func unwrapMid(splices: SegmentSplices, currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64): ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    let newExpect = Token(IDENTIFIER, "__expect${index}")
    { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
        let prelude = if (splices.bindsCurrMagical) {
            quote(let $(splices.currMagical) = $currMagicalExpr)
        } else {
            quote()
        }
        quote(
            $prelude
            let $(splices.opticsId) = $(splices.downcastExpr)
            let $newExpect = $opticsUpcastCallexprId($expectOptics, $(splices.opticsId))
            let $(splices.fwdId)  = $composeForwardCallexprId($expectOptics, $(splices.opticsId))($forward, $(splices.fwdAccess), $backward, $(splices.bwdAccess))
            let $(splices.bwdId) = $composeBackwardCallexprId($expectOptics, $(splices.opticsId))($forward, $(splices.fwdAccess), $backward, $(splices.bwdAccess))
            $(cont(splices.nextMagicalExpr, newExpect, splices.fwdId, splices.bwdId, index + 1))
        )
    }
}

// Wires one segment into the composition CPS: START segments anchor on the
// magicCont chain, MID segments thread the accumulated
// (magical, expected-registry, forward, backward, index) state.
private func wireSegment(
    first: Bool,
    magicCont: ((Tokens) -> Tokens) -> Tokens,
    currentCont: ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens,
    startSplices: SegmentSplices,
    midSplices: (UInt64) -> SegmentSplices
): ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    if (first) {
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            magicCont { currMagicalExpr: Tokens =>
                unwrapStart(startSplices)(currMagicalExpr)(cont)
            }
        }
    } else {
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            currentCont { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
                unwrapMid(midSplices(index), currMagicalExpr, expectOptics, forward, backward, index)(cont)
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
    let magicId = Token(IDENTIFIER, "magicStart")
    { thisMagicCont: (Tokens) -> Tokens  =>
        let tokens = quote($magicCallexprId({ => $input}))
        quote(
            $(thisMagicCont(tokens))
        )
    }
}

private func opticSplices(input: Token, index: UInt64): SegmentSplices {
    let (currMagical, opticsId, fwdId, bwdId) = segmentIds(index)
    SegmentSplices(currMagical, opticsId, fwdId, bwdId, false,
        quote(magicFirstClassDowncast($input)),
        quote($forwardFieldId($input)),
        quote($backwardFieldId($input)),
        quote(magicFirstClass($input)))
}

private func coercionSplices(input: TypeNode, index: UInt64): SegmentSplices {
    let (currMagical, opticsId, fwdId, bwdId) = segmentIds(index)
    let nextMagicalExpr = quote($magicCallexprId<$input>())
    SegmentSplices(currMagical, opticsId, fwdId, bwdId, true,
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
    SegmentSplices(currMagical, opticsId, fwdId, bwdId, true,
        quote($currMagical.$downcastName$gen($currMagical)),
        quote($opticsId.$accessForward$gen($currMagical, $(commaSeparated(args)))),
        quote($opticsId.$accessBackward$gen($currMagical, $(commaSeparated(args)))),
        quote($currMagical.$accessMagic$gen($currMagical)))
}