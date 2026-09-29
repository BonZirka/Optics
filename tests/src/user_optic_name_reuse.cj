package tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.macrodsl.*
import lucida_stdlib.*

// Same-named optics over different source types. Each declaration's generated
// interfaces are mangled from its own signature, so reusing `slen` needs no
// namespace to keep them apart.
@Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
struct slen {}

@Lens[source: Array<Int64>, focus: Int64, forward: { source[0] }, backward: { let a = source.clone(); a[0] = focus; a }]
struct slen {}

@Prism[source: Array<Int64>, focus: Int64, forward: { source.get(0) }, backward: { [focus] }]
struct spar {}

// A third source type reusing the name `slen`, including a tuple source so the
// mangle has to escape `(`, `)`, `,` and the whitespace around them.
@Lens[source: (Int64, Int64), focus: Int64,
    forward: { let (a, _) = source; a },
    backward: { let (_, b) = source; (focus, b) }]
struct slen {}

@Test
class UserOpticSameName {
    @TestCase
    func tupleSourceSharesName(): Unit {
        let t = (5, 6)
        @Assert(@f(t.slen()) == 5)
        @Assert(@f(t.slen() <- 7) == (7, 6))
        // and the earlier `slen` declarations still dispatch by source type
        let s = "abc"
        @Assert(@f(s.slen()) == 3)
        let arr = [1, 2, 3]
        @Assert(@f(arr.slen()) == 1)
    }
    @TestCase
    func sameNameDifferentSources(): Unit {
        let s = "abc"
        let got = @f(s.slen())
        @Assert(got == 3)
        let written = @f(s.slen() <- 7)
        @Assert(written == "7")
        let arr = [1, 2, 3]
        let gotArr = @f(arr.slen())
        @Assert(gotArr == 1)
        let arrUpd = @f(arr.slen() <- 9)
        @Assert(arrUpd[0] == 9)
    }

    @TestCase
    func prismAlias(): Unit {
        let m = [9, 8]
        match (@f(m?.spar())) {
            case Some(v) => @Assert(v == 9)
            case None => @Assert(false)
        }
        let back = @f(m?.spar() <- 5)
        @Assert(back[0] == 5)
        let miss: Array<Int64> = []
        match (@f(miss?.spar())) {
            case Some(_) => @Assert(false)
            case None => @Assert(true)
        }
    }
}

@DeriveOptics
public struct BlkWithArray {
    public BlkWithArray(public let items: Array<BlkInner>, public let n: Int64) { }
}

// The single-traversal requirement: an effect in a block's target must
// appear exactly once, whatever the block shape.
var effectCount = 0

func effectPair(): (Int64, Int64) {
    effectCount += 1
    return (42, 43)
}

var fwdRuns = 0

func effectN(): Int64 {
    effectCount += 1
    return effectCount
}

// a user optic whose forward carries an effect (counted) — the shared
// prefix of a nested block must traverse it exactly once
@Optic[source: BlkInner, focus: BlkInner, kind: Lens, forward: { fwdRuns += 1; source }, backward: { _, f => f }]
public struct selfLens {}

@DeriveOptics
public struct TupleBox {
    public TupleBox(public let tb: (Int64, Int64), public let n: Int64) { }
}

@DeriveOptics
public struct BlkInner {
    public BlkInner(public let a: Int64, public let b: Int64) { }
}

@DeriveOptics
public struct BlkOuter {
    public BlkOuter(public let i: BlkInner, public let n: Int64) { }
}

@Test
class BlockUpdate {
    @TestCase
    func tupleSpreadOnAnchor(): Unit {
        let o = BlkOuter(BlkInner(1, 2), 3)
        let updated = @f(o.{ .i; .n } <- (BlkInner(10, 20), 30))
        @Assert(updated.i.a == 10)
        @Assert(updated.i.b == 20)
        @Assert(updated.n == 30)
        @Assert(o.n == 3)
    }

    @TestCase
    func fusedAnchorChainWithBlock(): Unit {
        let o = BlkOuter(BlkInner(1, 2), 3)
        let updated = @f(o.i.{ .a; .b } <- (5, 6))
        @Assert(updated.i.a == 5)
        @Assert(updated.i.b == 6)
        @Assert(updated.n == 3)
    }

    @TestCase
    func singleFieldNoTuple(): Unit {
        let o = BlkOuter(BlkInner(1, 2), 3)
        let updated = @f(o.{ .n } <- 9)
        @Assert(updated.n == 9)
    }
}

@Test
class BlockRead {
    @TestCase
    func readReturnsTuple(): Unit {
        let o = BlkOuter(BlkInner(1, 2), 3)
        let got = @f(o.{ .i; .n })
        @Assert(got[0].a == 1)
        @Assert(got[0].b == 2)
        @Assert(got[1] == 3)
    }

    @TestCase
    func readSingleField(): Unit {
        let o = BlkOuter(BlkInner(1, 2), 3)
        let got = @f(o.{ .n })
        @Assert(got == 3)
    }
}

@Test
class TupleBlock {
    @TestCase
    func tupleSplitRead(): Unit {
        let big = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
        let got = @f(big.{ ._0; ._4; ._9 })
        @Assert(got[0] == 0)
        @Assert(got[1] == 4)
        @Assert(got[2] == 9)
    }

    @TestCase
    func tupleSplitWrite(): Unit {
        let big = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
        let updated = @f(big.{ ._2; ._7 } <- (20, 70))
        @Assert(updated[2] == 20)
        @Assert(updated[7] == 70)
        @Assert(updated[0] == 0)
    }
}

@Optic[source: BlkInner, focus: Int64, kind: Lens, forward: { source.b }, backward: { BlkInner(source.a, focus) }]
struct bLens {}

@Test
class BlockChains {
    @TestCase
    func firstClassMidChain(): Unit {
        let o = BlkOuter(BlkInner(1, 2), 3)
        let lens = @f(@typeof(o.i).bLens())
        let updated = @f(o.{ .i.@use(lens); .n } <- (9, 8))
        @Assert(updated.i.b == 9)
        @Assert(updated.n == 8)
        let got = @f(o.{ .i.@use(lens); .n })
        @Assert(got[0] == 2)
        @Assert(got[1] == 3)
    }

    @TestCase
    func userOpticMidChain(): Unit {
        let o = BlkOuter(BlkInner(1, 2), 3)
        let updated = @f(o.{ .i.bLens() } <- 9)
        @Assert(updated.i.b == 9)
        @Assert(updated.i.a == 1)
    }

    @TestCase
    func nestedBlocks(): Unit {
        let box = TupleBox((1, 2), 3)
        let upd = @f(box.{ .tb.{ ._0; ._1 }; .n } <- ((20, 21), 22))
        @Assert(upd.tb[0] == 20)
        @Assert(upd.tb[1] == 21)
        @Assert(upd.n == 22)
        let read = @f(box.{ .tb.{ ._0; ._1 }; .n })
        @Assert(read[0][0] == 1)
        @Assert(read[0][1] == 2)
        @Assert(read[1] == 3)
    }

    @TestCase
    func blockTargetEffectsRunOnce(): Unit {
        effectCount = 0
        let box = TupleBox((1, 2), 3)
        let upd = @f(box.{ .tb.{ ._0; ._1 }; .n } <- (effectPair(), 7))
        @Assert(upd.tb[0] == 42)
        @Assert(upd.tb[1] == 43)
        @Assert(upd.n == 7)
        @Assert(effectCount == 1)
    }

    @TestCase
    func nestedBlockEffectsEachOnce(): Unit {
        effectCount = 0
        let box = TupleBox((1, 2), 3)
        let upd = @f(box.{ .tb.{ ._0; ._1 }; .n } <- ((effectN(), effectN()), 9))
        @Assert(upd.tb[0] == 1)
        @Assert(upd.tb[1] == 2)
        @Assert(upd.n == 9)
        @Assert(effectCount == 2)
    }

    @TestCase
    func flatBlockEffectsEachOnce(): Unit {
        effectCount = 0
        let box = TupleBox((1, 2), 3)
        let upd = @f(box.{ .tb._0; .n } <- (effectN(), effectN()))
        @Assert(upd.tb[0] == 1)
        @Assert(upd.n == 2)
        @Assert(effectCount == 2)
    }

    @TestCase
    func nestedSharedPrefixTraversalOnce(): Unit {
        fwdRuns = 0
        let o = BlkOuter(BlkInner(1, 2), 3)
        let upd = @f(o.i.selfLens().{ .a; .b } <- (5, 6))
        @Assert(upd.i.a == 5)
        @Assert(upd.i.b == 6)
        @Assert(fwdRuns == 1)
        let read = @f(upd.i.selfLens().{ .a; .b })
        @Assert(read[0] == 5)
        @Assert(read[1] == 6)
        @Assert(fwdRuns == 2)
    }

    @TestCase
    func flatAndNestedSharedPrefixCompose(): Unit {
        let o = BlkOuter(BlkInner(1, 2), 3)
        let upd = @f(o.{ .i.a; .i.{ .b } } <- (7, 8))
        @Assert(upd.i.a == 7)
        @Assert(upd.i.b == 8)
        let got = @f(o.{ .i.a; .i.{ .b } })
        @Assert(got[0] == 1)
        @Assert(got[1] == 2)
    }


    @TestCase
    func nestedTupleTargets(): Unit {
        // a tuple focus is an ordinary focus: the target element can be a
        // tuple literal — ((1, 2), 3) spreads across the entries
        let box = TupleBox((1, 2), 3)
        let upd = @f(box.{ .tb; .n } <- ((5, 6), 7))
        @Assert(upd.tb[0] == 5)
        @Assert(upd.tb[1] == 6)
        @Assert(upd.n == 7)
        // and the block can anchor ON the tuple to spread across its parts
        let parts = @f(box.tb.{ ._0; ._1 } <- (8, 9))
        @Assert(parts.tb[0] == 8)
        @Assert(parts.tb[1] == 9)
        // 06C: disjoint sub-paths from one start field in ONE block
        let spread = @f(box.{ .tb._0; .tb._1; .n } <- (10, 11, 12))
        @Assert(spread.tb[0] == 10)
        @Assert(spread.tb[1] == 11)
        @Assert(spread.n == 12)
    }

    @TestCase
    func partialAnchorBlock(): Unit {
        let w = BlkWithArray([BlkInner(1, 2), BlkInner(3, 4)], 9)
        let upd = @f(w.items?.at(1).{ .a; .b } <- (7, 8))
        @Assert(upd.items[1].a == 7)
        @Assert(upd.items[1].b == 8)
        @Assert(upd.items[0].a == 1)
        let miss = @f(w.items?.at(9).{ .a; .b } <- (7, 8))
        @Assert(miss.items[1].a == 3)
        let read = @f(w.items?.at(0).{ .a; .b })
        if (let Some(t) <- read) {
            @Assert(t[0] == 1)
            @Assert(t[1] == 2)
        } else {
            @Assert(false)
        }
        let missRead = @f(w.items?.at(9).{ .a; .b })
        @Assert(missRead.isNone())
    }

    @TestCase
    func midChainFirstClass(): Unit {
        let o = BlkOuter(BlkInner(1, 2), 3)
        let iLens: Lens<BlkOuter, BlkInner> = @f(@typeof(o).i)
        let got = @f(o.@use(iLens).a)
        @Assert(got == 1)
        let upd = @f(o.@use(iLens).a <- 7)
        @Assert(upd.i.a == 7)
        @Assert(upd.n == 3)
        let aLens: Lens<BlkInner, Int64> = @f(@typeof(o.i).a)
        let got2 = @f(o.{ .i.@use(aLens); .n })
        @Assert(got2[0] == 1)
        @Assert(got2[1] == 3)
    }

    @TestCase
    func unfusedAndMintedOpticChains(): Unit {
        let o = BlkOuter(BlkInner(1, 2), 3)
        let iLens: Lens<BlkOuter, BlkInner> = @f(@typeof(o).i)
        let got = @f[unfuse](o.@use(iLens).a)
        @Assert(got == 1)
        let upd = @f[unfuse](o.@use(iLens).a <- 7)
        @Assert(upd.i.a == 7)
        // a sourceless chain MINTS a composed optic value, not a read
        let minted: Lens<BlkOuter, Int64> = @f(@use(iLens).a)
        @Assert(@f(o.@use(minted)) == 1)
        let mintedUpd: Setter<BlkOuter, Int64> = @f(@use(iLens).a <- 9)
        @Assert(mintedUpd.modifyId(o).i.a == 9)
    }

    @TestCase
    func chainWriteAndRead(): Unit {
        let o = BlkOuter(BlkInner(1, 2), 3)
        let updated = @f(o.{ .i.a; .n } <- (7, 8))
        @Assert(updated.i.a == 7)
        @Assert(updated.i.b == 2)
        @Assert(updated.n == 8)
        let got = @f(o.{ .i.a; .n })
        @Assert(got[0] == 1)
        @Assert(got[1] == 3)
    }
}
