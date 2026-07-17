macro package lucida.macrodsl

import std.ast.*
import std.collection.*

/*
 * @GenerateCompositions
 *
 * Applied to an empty struct declaration; re-emits the struct filled with the
 * full composition/upcast table of __OpticsCompositions:
 *   - composeForward / composeBackward for every ordered optic-kind pair,
 *   - opticsUpcast for every unordered pair.
 *
 * Kinds: 0=Iso 1=Lens 2=Prism 3=Affine 4=Setter.
 * Each row mirrors the historically hand-written implementation 1:1; the law
 * test suite (src/test/composition_laws.cj et al.) is the behavioral parity gate.
 */

// Kind constants
const ISO : Int64 = 0
const LENS : Int64 = 1
const PRISM : Int64 = 2
const AFFINE : Int64 = 3
const SETTER : Int64 = 4

func kindName(k: Int64): String {
    if (k == ISO) { return "Iso" }
    if (k == LENS) { return "Lens" }
    if (k == PRISM) { return "Prism" }
    if (k == AFFINE) { return "Affine" }
    if (k == SETTER) { return "Setter" }
    throw Exception("bad kind")
}

func registryTok(k: Int64): Token {
    // Lenses is the one irregular plural
    if (k == LENS) { return Token(IDENTIFIER, "RegistryLenses") }
    return Token(IDENTIFIER, "Registry${kindName(k)}s")
}

func idTok(n: String): Token {
    Token(IDENTIFIER, n)
}

// ---- type builders (over identifier tokens S, A, B) ----

func fnT(i: Tokens, o: Tokens): Tokens {
    quote(($i) -> $o)
}

func eitherT(a: Tokens, b: Tokens): Tokens {
    quote(Either<$a, $b>)
}

/// Type of the forward member for `kind` reading iT -> oT.
func fwdParamType(kind: Int64, iTk: Token, oTk: Token): Tokens {
    let iT = quote($iTk)
    let oT = quote($oTk)
    if (isEitherKind(kind)) { return fnT(iT, eitherT(iT, oT)) }
    if (kind == SETTER) { return fnT(iT, iT) }
    return fnT(iT, oT)
}

/// Type of the backward member for `kind`.
func bwdParamType(kind: Int64, iTk: Token, oTk: Token): Tokens {
    let iT = quote($iTk)
    let oT = quote($oTk)
    if (kind == ISO || kind == PRISM) { return fnT(oT, iT) }              // (A) -> S
    if (kind == LENS || kind == AFFINE) { return quote(($iT, $oT) -> $iT) } // (S, A) -> S
    return quote(($iT, ($oT) -> $oT) -> $iT)                              // Setter
}

func isEitherKind(k: Int64): Bool {
    k == PRISM || k == AFFINE
}

// The 25 ordered pairs (5 kinds x 5 kinds), in historical case order.
func allPairs(): ArrayList<(Int64, Int64)> {
    let rows = ArrayList<(Int64, Int64)>()
    rows.add((ISO, ISO))          // 1
    rows.add((LENS, LENS))        // 2
    rows.add((PRISM, PRISM))      // 3
    rows.add((AFFINE, AFFINE))    // 4
    rows.add((SETTER, SETTER))    // 5 (unlabeled)
    rows.add((ISO, LENS))         // 6
    rows.add((LENS, ISO))         // 7
    rows.add((ISO, PRISM))        // 8
    rows.add((PRISM, ISO))        // 9
    rows.add((PRISM, LENS))       // 10
    rows.add((LENS, PRISM))       // 11
    rows.add((ISO, AFFINE))       // 12
    rows.add((AFFINE, ISO))       // 13
    rows.add((ISO, SETTER))       // 14
    rows.add((SETTER, ISO))       // 15
    rows.add((LENS, AFFINE))      // 16
    rows.add((PRISM, AFFINE))     // 17
    rows.add((AFFINE, LENS))      // 18
    rows.add((AFFINE, PRISM))     // 19
    rows.add((LENS, SETTER))      // 20
    rows.add((SETTER, LENS))      // 21
    rows.add((PRISM, SETTER))     // 22
    rows.add((SETTER, PRISM))     // 23
    rows.add((AFFINE, SETTER))    // 24
    rows.add((SETTER, AFFINE))    // 25
    rows
}

// ---- forward lambda emitter (a1/a2 forwards, b1/b2 backwards) ----

func emitForwardLambda(k1: Int64, k2: Int64): Tokens {
    let S = idTok("S")
    let A = idTok("A")
    let B = idTok("B")
    let src = idTok("src")
    let prv = idTok("prv")
    let rsv = idTok("rsv")
    // NOTE: S/A/B below are TYPE identifiers (uppercase)
    let a1 = idTok("a1")
    let a2 = idTok("a2")
    let b1 = idTok("b1")
    let rightSB = quote(Right<$S, $B>)
    let leftSB = quote(Left<$S, $B>)
    if (!isEitherKind(k1) && !isEitherKind(k2) && k2 != SETTER && k1 != SETTER) {
        // total -> total
        return quote({ $src: $S => $a2($a1($src)) })
    }
    if (k2 == SETTER && k1 == SETTER) {
        return quote({ $src: $S => $b1($src, $a2) })
    }
    if (k2 == SETTER) {
        // setter on the right: plumb modifyId through the first optic's backward
        if (k1 == ISO) { return quote({ $src: $S => $b1($a2($a1($src))) }) }
        if (k1 == LENS) { return quote({ $src: $S => $b1($src, $a2($a1($src))) }) }
        if (k1 == PRISM) {
            return quote(
                { $src: $S =>
                    if (let Right($prv) <- $a1($src)) {
                        $b1($a2($prv))
                    } else {
                        $src
                    }
                })
        }
        // AFFINE
        return quote(
            { $src: $S =>
                if (let Right($prv) <- $a1($src)) {
                    $b1($src, $a2($prv))
                } else {
                    $src
                }
            })
    }
    if (k1 == SETTER) {
        // setter on the left: forward is just the first setter's modifyId
        return quote($a1)
    }
    if (!isEitherKind(k1) && isEitherKind(k2)) {
        return quote(
            { $src: $S =>
                if (let Right($rsv) <- $a2($a1($src))) {
                    $rightSB($rsv)
                } else {
                    $leftSB($src)
                }
            })
    }
    if (isEitherKind(k1) && !isEitherKind(k2)) {
        return quote(
            { $src: $S =>
                if (let Right($prv) <- $a1($src)) {
                    $rightSB($a2($prv))
                } else {
                    $leftSB($src)
                }
            })
    }
    // both either-shaped: chained guards
    return quote(
        { $src: $S =>
            if (let Right($prv) <- $a1($src) && let Right($rsv) <- $a2($prv)) {
                $rightSB($rsv)
            } else {
                $leftSB($src)
            }
        })
}

// Builds the backward closure tokens. `takesSource`: false for the four
// sourceless rebuild rows; setter rows take a modifier instead of a focus.
func emitBackwardClosure(k1: Int64, k2: Int64): Tokens {
    let S = idTok("S")
    let A = idTok("A")
    let B = idTok("B")
    let src = idTok("src")
    let fcs = idTok("fcs")
    let mod = idTok("mod")
    let v1 = idTok("v1")
    let v2 = idTok("v2")
    let comp = idTok("comp")
    let a1 = idTok("a1")
    let a2 = idTok("a2")
    let b1 = idTok("b1")
    let b2 = idTok("b2")

    // Sourceless rebuild chains: both kinds have rebuild-arity backwards
    // (Iso/Prism), e.g. cases 1 <Iso,Iso>, 3 <Prism,Prism>, 8 <Iso,Prism>, 9 <Prism,Iso>.
    if ((k1 == ISO || k1 == PRISM) && (k2 == ISO || k2 == PRISM)) {
        return quote({ $fcs: $B => $b1($b2($fcs)) })
    }

    // setter rows take (source, modifier)
    if (k2 == SETTER) {
        if (k1 == ISO) { return quote({ $src: $S, $mod: ($B) -> $B => $b1($b2($a1($src), $mod)) }) }
        if (k1 == LENS) { return quote({ $src: $S, $mod: ($B) -> $B => $b1($src, $b2($a1($src), $mod)) }) }
        if (k1 == PRISM) {
            return quote(
                { $src: $S, $mod: ($B) -> $B =>
                    if (let Right($v1) <- $a1($src)) {
                        $b1($b2($v1, $mod))
                    } else {
                        $src
                    }
                })
        }
        if (k1 == AFFINE) {
            return quote(
                { $src: $S, $mod: ($B) -> $B =>
                    if (let Right($v1) <- $a1($src)) {
                        $b1($src, $b2($v1, $mod))
                    } else {
                        $src
                    }
                })
        }
        // SETTER x SETTER
        return quote(
            { $src: $S, $mod: ($B) -> $B =>
                let comp: ($A) -> $A = { inner: $A => $b2(inner, $mod) }
                $b1($src, $comp)
            })
    }
    if (k1 == SETTER) {
        // modifier composed with the second optic per element
        if (k2 == ISO) {
            return quote(
                { $src: $S, $mod: ($B) -> $B =>
                    let comp: ($A) -> $A = { inner: $A => $b2($mod($a2(inner))) }
                    $b1($src, $comp)
                })
        }
        if (k2 == LENS) {
            return quote(
                { $src: $S, $mod: ($B) -> $B =>
                    let comp: ($A) -> $A = { inner: $A => $b2(inner, $mod($a2(inner))) }
                    $b1($src, $comp)
                })
        }
        if (k2 == PRISM) {
            return quote(
                { $src: $S, $mod: ($B) -> $B =>
                    let comp: ($A) -> $A = { inner: $A =>
                        if (let Right($v2) <- $a2(inner)) {
                            $b2($mod($v2))
                        } else {
                            inner
                        }
                    }
                    $b1($src, $comp)
                })
        }
        // AFFINE
        return quote(
            { $src: $S, $mod: ($B) -> $B =>
                let comp: ($A) -> $A = { inner: $A =>
                    if (let Right($v2) <- $a2(inner)) {
                        $b2(inner, $mod($v2))
                    } else {
                        inner
                    }
                }
                $b1($src, $comp)
            })
    }

    // plain (source, focus) rows
    let pairKey = k1 * 10 + k2
    if (pairKey == LENS * 10 + LENS) { return quote({ $src: $S, $fcs: $B => $b1($src, $b2($a1($src), $fcs)) }) }
    if (pairKey == ISO * 10 + LENS) { return quote({ $src: $S, $fcs: $B => $b1($b2($a1($src), $fcs)) }) }
    if (pairKey == LENS * 10 + ISO) { return quote({ $src: $S, $fcs: $B => $b1($src, $b2($fcs)) }) }
    if (pairKey == PRISM * 10 + LENS) {
        return quote(
            { $src: $S, $fcs: $B =>
                if (let Right($v1) <- $a1($src)) {
                    $b1($b2($v1, $fcs))
                } else {
                    $src
                }
            })
    }
    if (pairKey == LENS * 10 + PRISM) {
        return quote(
            { $src: $S, $fcs: $B =>
                if (let Right(_) <- $a2($a1($src))) {
                    $b1($src, $b2($fcs))
                } else {
                    $src
                }
            })
    }
    if (pairKey == ISO * 10 + AFFINE) {
        return quote(
            { $src: $S, $fcs: $B =>
                let t = $a1($src)
                if (let Right(_) <- $a2(t)) {
                    $b1($b2(t, $fcs))
                } else {
                    $src
                }
            })
    }
    if (pairKey == AFFINE * 10 + ISO) {
        return quote(
            { $src: $S, $fcs: $B =>
                if (let Right(_) <- $a1($src)) {
                    $b1($src, $b2($fcs))
                } else {
                    $src
                }
            })
    }
    if (pairKey == LENS * 10 + AFFINE) {
        return quote(
            { $src: $S, $fcs: $B =>
                let t = $a1($src)
                if (let Right(_) <- $a2(t)) {
                    $b1($src, $b2(t, $fcs))
                } else {
                    $src
                }
            })
    }
    if (pairKey == AFFINE * 10 + LENS) {
        return quote(
            { $src: $S, $fcs: $B =>
                if (let Right($v1) <- $a1($src)) {
                    $b1($src, $b2($v1, $fcs))
                } else {
                    $src
                }
            })
    }
    if (pairKey == AFFINE * 10 + AFFINE) {
        return quote(
            { $src: $S, $fcs: $B =>
                if (let Right($v1) <- $a1($src) && let Right(_) <- $a2($v1)) {
                    $b1($src, $b2($v1, $fcs))
                } else {
                    $src
                }
            })
    }
    if (pairKey == AFFINE * 10 + PRISM) {
        return quote(
            { $src: $S, $fcs: $B =>
                if (let Right($v1) <- $a1($src) && let Right(_) <- $a2($v1)) {
                    $b1($src, $b2($fcs))
                } else {
                    $src
                }
            })
    }
    if (pairKey == PRISM * 10 + AFFINE) {
        return quote(
            { $src: $S, $fcs: $B =>
                if (let Right($v1) <- $a1($src) && let Right(_) <- $a2($v1)) {
                    $b1($b2($v1, $fcs))
                } else {
                    $src
                }
            })
    }
    throw Exception("unreachable backward row k1=${k1} k2=${k2}")
}

// ---- member emitters ----

func emitComposeForward(k1: Int64, k2: Int64): Decl {
    let gS = idTok("S")
    let gA = idTok("A")
    let gB = idTok("B")
    let a1 = idTok("a1")
    let a2 = idTok("a2")
    let b1 = idTok("b1")
    let b2 = idTok("b2")
    let r1 = registryTok(k1)
    let r2 = registryTok(k2)
    let p1t = quote(_ : $r1<$gS>)
    let p2t = quote(_ : $r2<$gA>)
    let lam = emitForwardLambda(k1, k2)
    FuncDecl(quote(
        @Frozen
        public static func composeForward<$gS, $gA, $gB>($p1t, $p2t) {
            { $a1: $(fwdParamType(k1, gS, gA)), $a2: $(fwdParamType(k2, gA, gB)), $b1: $(bwdParamType(k1, gS, gA)), $b2: $(bwdParamType(k2, gA, gB)) =>
                $lam
            }
        }
    ))
}

func emitComposeBackward(k1: Int64, k2: Int64): Decl {
    let gS = idTok("S")
    let gA = idTok("A")
    let gB = idTok("B")
    let a1 = idTok("a1")
    let a2 = idTok("a2")
    let b1 = idTok("b1")
    let b2 = idTok("b2")
    let r1 = registryTok(k1)
    let r2 = registryTok(k2)
    let p1t = quote(_ : $r1<$gS>)
    let p2t = quote(_ : $r2<$gA>)
    let lam = emitBackwardClosure(k1, k2)
    FuncDecl(quote(
        @Frozen
        public static func composeBackward<$gS, $gA, $gB>($p1t, $p2t) {
            { $a1: $(fwdParamType(k1, gS, gA)), $a2: $(fwdParamType(k2, gA, gB)), $b1: $(bwdParamType(k1, gS, gA)), $b2: $(bwdParamType(k2, gA, gB)) =>
                $lam
            }
        }
    ))
}

// Upcast lattice: Setter < Affine < {Lens, Prism} < Iso; join(Lens, Prism) = Affine.
// Strength ranks (weakest = 0): Setter < Affine < {Lens, Prism} < Iso.
func strengthRank(k: Int64): Int64 {
    if (k == SETTER) { return 0 }
    if (k == AFFINE) { return 1 }
    if (k == LENS || k == PRISM) { return 2 }
    return 3 // ISO
}

func upcastJoin(k1: Int64, k2: Int64): Int64 {
    if (k1 == k2) { return k1 }
    if (k1 == ISO) { return k2 }
    if (k2 == ISO) { return k1 }
    let r1 = strengthRank(k1)
    let r2 = strengthRank(k2)
    if (r1 == r2) { return AFFINE } // Lens x Prism joins to Affine
    return if (r1 < r2) { k1 } else { k2 }
}

func emitUpcasts(): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    let kinds = [ISO, LENS, PRISM, AFFINE, SETTER]
    // Both argument orders are emitted (the eval macro calls opticsUpcast with
    // the existing-chain registry first), matching the historical 25 overloads.
    for (i in 0..kinds.size) {
        for (j in 0..kinds.size) {
            let k1 = kinds[i]
            let k2 = kinds[j]
            let res = upcastJoin(k1, k2)
            let gS = idTok("S")
            let gA = idTok("A")
            let r1 = registryTok(k1)
            let r2 = registryTok(k2)
            let rr = registryTok(res)
            out.addContra(FuncDecl(quote(
                @Frozen
                public static func opticsUpcast<$gS, $gA>(_ : $r1<$gS>, _ : $r2<$gA>): $rr<$gS> { $rr() }
            )))
        }
    }
    out
}

func generateCompositionMembers(): ArrayList<Decl> {
    let members = ArrayList<Decl>()
    for (pair in allPairs()) {
        members.addContra(emitComposeForward(pair[0], pair[1]))
        members.addContra(emitComposeBackward(pair[0], pair[1]))
    }
    for (d in emitUpcasts()) {
        members.addContra(d)
    }
    members
}

public macro GenerateCompositions(input: Tokens): Tokens {
    let currentDecl = parseDecl(input)
    let id = currentDecl.identifier
    let members = generateCompositionMembers()
    quote(
        public struct $id {
            $(members)
        }
    )
}
