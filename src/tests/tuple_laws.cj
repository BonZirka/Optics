package lucida.tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.macrodsl.*

// Tuple-type support through the DSL. Tuple elements are addressed as `._0`,
// `._1`, ... — total segments riding the generated tuple-lens plumbing
// (`RegistryLenses<(X0, X1, ...)>`, arities 2..3).

@DeriveOptics
public struct PairBox {
    public PairBox(public let pair: (Int64, String)) { }
}

@DeriveOptics
public struct TripleBox {
    public TripleBox(public let t: (Int64, String, Bool)) { }
}

@DeriveOptics
public struct NestedPairBox {
    public NestedPairBox(public let pair: ((Int64, Int64), String)) { }
}

@DeriveOptics
public struct Inner {
    public Inner(public let v: Int64) { }
}

@DeriveOptics
public struct DeepPairBox {
    public DeepPairBox(public let pair: (Int64, Inner)) { }
}

@DeriveOptics
public struct GPairBox {
    public GPairBox(public let pair: (GBox<Int64>, String)) { }
}

// ===== whole-tuple reads and writes =====

@Test
class TupleWholeLaws {
    @TestCase
    func wholeTupleRead(): Unit {
        let p = PairBox((1, "a"))
        let r = @Lucida(p.pair)
        @Assert(r[0] == 1 && r[1] == "a")
    }

    @TestCase
    func wholeTupleWrite(): Unit {
        let p = PairBox((1, "a"))
        let updated = @Lucida(p.pair <- (2, "b"))
        @Assert(updated.pair[0] == 2 && updated.pair[1] == "b")
        // the original is never mutated
        @Assert(p.pair[0] == 1 && p.pair[1] == "a")
    }

    @TestCase
    func wholeTupleRoundTrip(): Unit {
        let p = PairBox((1, "a"))
        let r = @Lucida(p.pair)
        let back = @Lucida(p.pair <- r)
        @Assert(back.pair[0] == 1 && back.pair[1] == "a")
    }

    @TestCase
    func tripleWrite(): Unit {
        let t = TripleBox((1, "x", true))
        let updated = @Lucida(t.t <- (2, "y", false))
        @Assert(updated.t[0] == 2 && updated.t[1] == "y" && !updated.t[2])
        @Assert(t.t[2])
    }
}

// ===== element access (`._0`, `._1`, ...) =====

@Test
class TupleElementLaws {
    @TestCase
    func elementReads(): Unit {
        let p = PairBox((1, "a"))
        @Assert(@Lucida(p.pair._0) == 1)
        @Assert(@Lucida(p.pair._1) == "a")
    }

    @TestCase
    func elementWrites(): Unit {
        let p = PairBox((1, "a"))
        let onlyInt = @Lucida(p.pair._0 <- 9)
        @Assert(onlyInt.pair[0] == 9 && onlyInt.pair[1] == "a")
        @Assert(p.pair[0] == 1)

        let onlyStr = @Lucida(p.pair._1 <- "z")
        @Assert(onlyStr.pair[0] == 1 && onlyStr.pair[1] == "z")
        @Assert(p.pair[1] == "a")
    }

    @TestCase
    func elementRoundTrip(): Unit {
        let p = PairBox((1, "a"))
        let v = @Lucida(p.pair._0)
        let back = @Lucida(p.pair._0 <- v)
        @Assert(back.pair[0] == 1 && back.pair[1] == "a")
    }

    @TestCase
    func tripleElementWrites(): Unit {
        let t = TripleBox((1, "x", true))
        let a = @Lucida(t.t._0 <- 7)
        @Assert(a.t[0] == 7 && a.t[1] == "x" && a.t[2])
        let b = @Lucida(t.t._1 <- "q")
        @Assert(b.t[0] == 1 && b.t[1] == "q" && b.t[2])
        let c = @Lucida(t.t._2 <- false)
        @Assert(c.t[0] == 1 && c.t[1] == "x" && !c.t[2])
        // original untouched by all three
        @Assert(t.t[0] == 1 && t.t[1] == "x" && t.t[2])
    }

    @TestCase
    func nestedTupleElements(): Unit {
        let p = NestedPairBox(((1, 2), "a"))
        @Assert(@Lucida(p.pair._0._0) == 1)
        @Assert(@Lucida(p.pair._0._1) == 2)
        @Assert(@Lucida(p.pair._1) == "a")
        let updated = @Lucida(p.pair._0._1 <- 42)
        @Assert(updated.pair[0][1] == 42 && updated.pair[0][0] == 1 && updated.pair[1] == "a")
        @Assert(p.pair[0][1] == 2)
    }

    // A chain continues INTO an element: the element's registry currency is
    // whatever the element type is, so a derived struct element walks on.
    @TestCase
    func chainContinuesIntoStructElement(): Unit {
        let d = DeepPairBox((1, Inner(5)))
        @Assert(@Lucida(d.pair._1.v) == 5)
        let updated = @Lucida(d.pair._1.v <- 6)
        @Assert(updated.pair[1].v == 6 && updated.pair[0] == 1)
        @Assert(d.pair[1].v == 5)
    }

    @TestCase
    func chainContinuesIntoGenericElement(): Unit {
        let g = GPairBox((GBox<Int64>(3), "s"))
        @Assert(@Lucida(g.pair._0.v) == 3)
        let updated = @Lucida(g.pair._0.v <- 4)
        @Assert(updated.pair[0].v == 4 && updated.pair[1] == "s")
    }
}

// ===== tuples behind enum cases (the multi-payload focus is a tuple) =====

@Test
class TupleEnumChainLaws {
    // Status.Failed focuses (String, Int64) — the case work composes with the
    // tuple element lenses. Chains containing `?.` are partial: their read is
    // an Option.
    @TestCase
    func enumCaseTupleElementRead(): Unit {
        let f = Status.Failed("boom", 7)
        var msgOk = false
        match (@Lucida(f?.Failed._0)) {
            case Some(v) => msgOk = (v == "boom")
            case _ => ()
        }
        @Assert(msgOk)

        var codeOk = false
        match (@Lucida(f?.Failed._1)) {
            case Some(v) => codeOk = (v == 7)
            case _ => ()
        }
        @Assert(codeOk)
    }

    @TestCase
    func enumCaseTupleElementWrite(): Unit {
        let f = Status.Failed("boom", 7)
        let fixed = @Lucida(f?.Failed._0 <- "fixed")
        var ok = false
        match (fixed) {
            case Failed(msg, code) => ok = (msg == "fixed" && code == 7)
            case _ => ()
        }
        @Assert(ok)
        // the original is untouched
        var originalKept = false
        match (f) {
            case Failed(msg, code) => originalKept = (msg == "boom" && code == 7)
            case _ => ()
        }
        @Assert(originalKept)
    }

    @TestCase
    func enumCaseMissCarriesSource(): Unit {
        let a = Status.Active(2)
        let untouched = @Lucida(a?.Failed._0 <- "x")
        var kept = false
        match (untouched) {
            case Active(v) => kept = (v == 2)
            case _ => ()
        }
        @Assert(kept)
    }

    // Nested list traversal: prism -> tuple element -> prism -> tuple element.
    // Mixed total/partial segments in one chain.
    @TestCase
    func nestedListThroughTupleElements(): Unit {
        let l = IntList.Cons(1, IntList.Cons(2, IntList.Nil))
        var headOk = false
        match (@Lucida(l?.Cons._0)) {
            case Some(v) => headOk = (v == 1)
            case _ => ()
        }
        @Assert(headOk)

        var secondOk = false
        match (@Lucida(l?.Cons._1?.Cons._0)) {
            case Some(v) => secondOk = (v == 2)
            case _ => ()
        }
        @Assert(secondOk)

        let updated = @Lucida(l?.Cons._1?.Cons._0 <- 42)
        var ok = false
        match (updated) {
            case Cons(h, t) => match (t) {
                case Cons(h2, _) => ok = (h == 1 && h2 == 42)
                case _ => ()
            }
            case _ => ()
        }
        @Assert(ok)
    }

    @TestCase
    func nestedListMissIsIdentity(): Unit {
        let l = IntList.Cons(1, IntList.Nil)
        // the inner Cons misses; the whole chain keeps the source
        let updated = @Lucida(l?.Cons._1?.Cons._0 <- 42)
        var kept = false
        match (updated) {
            case Cons(h, t) => match (t) {
                case Nil => kept = (h == 1)
                case _ => ()
            }
            case _ => ()
        }
        @Assert(kept)
    }
}

// ===== arities above 3 (the raised generator bound is 16) =====

@DeriveOptics
public struct QuintBox {
    public QuintBox(public let t: (Int64, Int64, Int64, Int64, Int64)) { }
}

@DeriveOptics
public struct OctoBox {
    public OctoBox(public let t: (Int64, Int64, Int64, Int64, Int64, Int64, Int64, Int64)) { }
}

@Test
class TupleArityLaws {
    @TestCase
    func quintElements(): Unit {
        let q = QuintBox((1, 2, 3, 4, 5))
        @Assert(@Lucida(q.t._0) == 1)
        @Assert(@Lucida(q.t._4) == 5)
        let updated = @Lucida(q.t._2 <- 30)
        @Assert(updated.t[2] == 30 && updated.t[0] == 1 && updated.t[4] == 5)
        @Assert(q.t[2] == 3)
    }

    @TestCase
    func octoElements(): Unit {
        let o = OctoBox((1, 2, 3, 4, 5, 6, 7, 8))
        @Assert(@Lucida(o.t._0) == 1)
        @Assert(@Lucida(o.t._7) == 8)
        let updated = @Lucida(o.t <- (8, 7, 6, 5, 4, 3, 2, 1))
        @Assert(updated.t[0] == 8 && updated.t[7] == 1)
        @Assert(o.t[0] == 1)
    }
}

// ===== first-class optics over tuples =====

@Test
class TupleFirstClassLaws {
    @TestCase
    func firstClassWholeTuple(): Unit {
        let p = PairBox((1, "a"))
        let lens = @Lucida(@TypeOf(p).pair)
        let r = lens.view(p)
        @Assert(r[0] == 1 && r[1] == "a")
        let updated = lens.update(p, (2, "b"))
        @Assert(updated.pair[0] == 2)
    }

    @TestCase
    func firstClassElement(): Unit {
        let p = PairBox((1, "a"))
        let lens = @Lucida(@TypeOf(p).pair._0)
        @Assert(lens.view(p) == 1)
        let updated = lens.update(p, 9)
        @Assert(updated.pair[0] == 9 && updated.pair[1] == "a")
    }
}

// ===== user-declared optic with a tuple focus =====

@LucidaOptic[
    source: Point
    focus: (Int64, Int64)
    kind: Iso
    forward: { (src.x, src.y) }
    backward: { Point(focus[0], focus[1]) }
]
struct pointCoords {}

public struct Point {
    public Point(public let x: Int64, public let y: Int64) { }
}

@Test
class TupleUserOpticLaws {
    @TestCase
    func userIsoTupleFocusRead(): Unit {
        let pt = Point(3, 4)
        let coords = @Lucida(pt.pointCoords())
        @Assert(coords[0] == 3 && coords[1] == 4)
        // the iso is total, so the chain continues into the tuple elements
        @Assert(@Lucida(pt.pointCoords()._0) == 3)
        @Assert(@Lucida(pt.pointCoords()._1) == 4)
    }

    @TestCase
    func userIsoTupleFocusWrite(): Unit {
        let pt = Point(3, 4)
        let moved = @Lucida(pt.pointCoords()._0 <- 10)
        @Assert(moved.x == 10 && moved.y == 4)
        @Assert(pt.x == 3)
    }
}
