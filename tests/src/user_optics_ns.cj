package tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.macrodsl.*

// Same-named optics over different source types, collected in one namespace.
@Optics({
    @Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
    struct slen {}

    @Lens[source: Array<Int64>, focus: Int64, forward: { source[0] }, backward: { let a = source.clone(); a[0] = focus; a }]
    struct slen {}

    @Prism[source: Array<Int64>, focus: Int64, forward: { source.get(0) }, backward: { [focus] }]
    struct spar {}
})

@Test
class OpticsNamespace {
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
    func prismInNamespace(): Unit {
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
