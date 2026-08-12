package lucida.tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.macrodsl.*

@DeriveOptics
public struct Nested {
    public Nested(public let n: Int64) { }
}

@DeriveOptics
public enum Shape {
    | Circle(Nested)
    | Square(Int64)
}

@DeriveOptics
public enum Slot {
    | Empty
    | Held(Int64)
}

@DeriveOptics
public enum IntList {
    | Nil
    | Cons(Int64, IntList)
}

@DeriveOptics
public enum Status {
    | Pending
    | Active(Int64)
    | Failed(String, Int64)
}

@DeriveOptics
public enum Envelope<T> {
    | Vacant
    | Sealed(T)
}

@Test
class DerivedEnumShapeLaws {
    // ===== payloadless cases derive Unit-focus prisms =====
    @TestCase
    func payloadlessCasePrism(): Unit {
        // Some(()) when the source IS the case — a match check.
        let e0 = Slot.Empty
        var ok = false
        match (@f(e0?.Empty)) {
            case Some(_) => ok = true
            case _ => ()
        }
        @Assert(ok)

        // A Held value misses: None — nothing handed back.
        let h0 = Slot.Held(3)
        var missed = false
        match (@f(h0?.Empty)) {
            case None => missed = true
            case _ => ()
        }
        @Assert(missed)
    }

    @TestCase
    func payloadlessCaseUpdate(): Unit {
        let m = Slot.Empty
        let updated = @f(m?.Empty <- ())
        var stillEmpty = false
        match (updated) {
            case Empty => stillEmpty = true
            case _ => ()
        }
        @Assert(stillEmpty)

        // Set through a non-matching prism is identity (the §1.1 law).
        let h1 = Slot.Held(3)
        let untouched = @f(h1?.Empty <- ())
        var identityKept = false
        match (untouched) {
            case Held(v) => identityKept = (v == 3)
            case _ => ()
        }
        @Assert(identityKept)
    }

    // ===== multi-payload cases derive tuple-focus prisms =====
    @TestCase
    func multiPayloadTupleFocus(): Unit {
        let l = IntList.Cons(1, IntList.Nil)
        var ok = false
        match (@f(l?.Cons)) {
            case Some(pair) => match (pair) {
                case (h, t) => match (t) {
                    case Nil => ok = (h == 1)
                    case _ => ()
                }
                case _ => ()
            }
            case _ => ()
        }
        @Assert(ok)

        let n0 = IntList.Nil
        var missed = false
        match (@f(n0?.Cons)) {
            case None => missed = true
            case _ => ()
        }
        @Assert(missed)
    }

    @TestCase
    func multiPayloadTupleUpdate(): Unit {
        let l = IntList.Cons(1, IntList.Nil)
        let updated = @f(l?.Cons <- (9, IntList.Cons(2, IntList.Nil)))
        var rebuilt = false
        match (updated) {
            case Cons(h, t) => match (t) {
                case Cons(h2, _) => rebuilt = (h == 9 && h2 == 2)
                case _ => ()
            }
            case _ => ()
        }
        @Assert(rebuilt)

        // mismatched source: identity
        let n1 = IntList.Nil
        let untouched = @f(n1?.Cons <- (9, IntList.Nil))
        var kept = false
        match (untouched) {
            case Nil => kept = true
            case _ => ()
        }
        @Assert(kept)
    }

    // ===== all three payload shapes in one enum =====
    // NOTE: the DSL reads `X.Failed(args)` as a user-optic method call, so
    // constructor calls must be bound to locals before use as chain anchors.
    @TestCase
    func mixedShapesDeriveTogether(): Unit {
        let a = Status.Active(2)
        var activeOk = false
        match (@f(a?.Active)) {
            case Some(v) => activeOk = (v == 2)
            case _ => ()
        }
        @Assert(activeOk)

        let f = Status.Failed("boom", 7)
        var failedOk = false
        match (@f(f?.Failed)) {
            case Some(pair) => match (pair) {
                case (msg, code) => failedOk = (msg == "boom" && code == 7)
                case _ => ()
            }
            case _ => ()
        }
        @Assert(failedOk)

        let p = Status.Pending
        var pendingOk = false
        match (@f(p?.Pending)) {
            case Some(_) => pendingOk = true
            case _ => ()
        }
        @Assert(pendingOk)

        let updated = @f(f?.Failed <- ("ok", 0))
        var writeOk = false
        match (updated) {
            case Failed(msg, code) => writeOk = (msg == "ok" && code == 0)
            case _ => ()
        }
        @Assert(writeOk)
    }

    // ===== generic enums with payloadless cases derive too =====
    @TestCase
    func genericEnumWithPayloadlessCase(): Unit {
        let w = Envelope<Int64>.Sealed(3)
        var ok = false
        match (@f(w?.Sealed)) {
            case Some(v) => ok = (v == 3)
            case _ => ()
        }
        @Assert(ok)

        let e = Envelope<Int64>.Vacant
        var emptyOk = false
        match (@f(e?.Vacant)) {
            case Some(_) => emptyOk = true
            case _ => ()
        }
        @Assert(emptyOk)
    }
}

@Test
class EnumPrismLaws {
    // ===== forward =====
    // With a source present, @f(src?.Case) evaluates the prism directly:
    // matching case -> Some(payload), mismatched -> None.
    @TestCase
    func forwardMatchAndMismatch(): Unit {
        let c = Shape.Circle(Nested(3))
        let s = Shape.Square(2)
        @Assert(isSomeCircle(@f(c?.Circle), 3))
        @Assert(isNoneSquare(@f(s?.Circle)))
        @Assert(isSomeSquare(@f(s?.Square), 2))
        @Assert(isNoneCircle(@f(c?.Square)))
    }

    // ===== backward rebuilds the case with the new payload =====
    @TestCase
    func backwardRebuilds(): Unit {
        let circleVal = Shape.Circle(Nested(1))
        // Sourceless @typeof form constructs the first-class affine itself.
        let aff = @f(@typeof(circleVal)?.Circle)
        let rebuilt = aff.update(circleVal, Nested(9))
        var rebuiltOk = false
        match (rebuilt) {
            case Circle(nn) => rebuiltOk = nn.n == 9
            case _ => ()
        }
        @Assert(rebuiltOk)
    }

    // ===== THE §1.1 class: set through a non-matching prism = identity =====
    @TestCase
    func nonMatchSetIsIdentity(): Unit {
        let sq = Shape.Square(5)
        let updated = @f(sq?.Circle <- Nested(99))
        var identityKept = false
        match (updated) {
            case Square(v) => identityKept = v == 5
            case _ => ()
        }
        @Assert(identityKept)
    }

    // ===== chained through a struct-field lens after the prism =====
    @TestCase
    func chainedThroughPayloadField(): Unit {
        let c = Shape.Circle(Nested(3))
        let updated = @f(c?.Circle.n <- 7)
        var updatedOk = false
        match (updated) {
            case Circle(inner) => updatedOk = inner.n == 7
            case _ => ()
        }
        @Assert(updatedOk)

        // non-matching source stays untouched
        let sq = Shape.Square(4)
        let untouched = @f(sq?.Circle.n <- 7)
        var untouchedOk = false
        match (untouched) {
            case Square(v) => untouchedOk = v == 4
            case _ => ()
        }
        @Assert(untouchedOk)
    }

    // ===== forward/backward agreement on the matched path =====
    @TestCase
    func roundTripAgreement(): Unit {
        let c = Shape.Circle(Nested(3))
        let fwdBack = @f(c?.Circle)
        var agree = false
        match (fwdBack) {
            case Some(p) =>
                let back = @f(@typeof(c)?.Circle)
                match (back.update(c, p)) {
                    case Circle(inner) => agree = inner.n == 3
                    case _ => ()
                }
            case _ => ()
        }
        @Assert(agree)
    }
}

func isSomeCircle(e: Option<Nested>, expectedN: Int64): Bool {
    if (let Some(p) <- e) {
        return p.n == expectedN
    }
    return false
}

func isSomeSquare(e: Option<Int64>, expectedV: Int64): Bool {
    if (let Some(v) <- e) {
        return v == expectedV
    }
    return false
}

// Mismatched-case forward is a miss: None, no object handed back.
func isNoneCircle(e: Option<Int64>): Bool {
    match (e) {
        case None => return true
        case _ => return false
    }
}

func isNoneSquare(e: Option<Nested>): Bool {
    match (e) {
        case None => return true
        case _ => return false
    }
}
