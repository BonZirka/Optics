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
        // Right(()) when the source IS the case — a match check.
        let e0 = Slot.Empty
        var ok = false
        match (@Lucida(e0?.Empty)) {
            case Right(_) => ok = true
            case _ => ()
        }
        @Assert(ok)

        // A Held value misses: Left carries the original source.
        let h0 = Slot.Held(3)
        var missed = false
        match (@Lucida(h0?.Empty)) {
            case Left(src) => match (src) {
                case Held(v) => missed = (v == 3)
                case _ => ()
            }
            case _ => ()
        }
        @Assert(missed)
    }

    @TestCase
    func payloadlessCaseUpdate(): Unit {
        let m = Slot.Empty
        let updated = @Lucida(m?.Empty <- ())
        var stillEmpty = false
        match (updated) {
            case Empty => stillEmpty = true
            case _ => ()
        }
        @Assert(stillEmpty)

        // Set through a non-matching prism is identity (the §1.1 law).
        let h1 = Slot.Held(3)
        let untouched = @Lucida(h1?.Empty <- ())
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
        match (@Lucida(l?.Cons)) {
            case Right(pair) => match (pair) {
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
        match (@Lucida(n0?.Cons)) {
            case Left(src) => match (src) {
                case Nil => missed = true
                case _ => ()
            }
            case _ => ()
        }
        @Assert(missed)
    }

    @TestCase
    func multiPayloadTupleUpdate(): Unit {
        let l = IntList.Cons(1, IntList.Nil)
        let updated = @Lucida(l?.Cons <- (9, IntList.Cons(2, IntList.Nil)))
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
        let untouched = @Lucida(n1?.Cons <- (9, IntList.Nil))
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
        match (@Lucida(a?.Active)) {
            case Right(v) => activeOk = (v == 2)
            case _ => ()
        }
        @Assert(activeOk)

        let f = Status.Failed("boom", 7)
        var failedOk = false
        match (@Lucida(f?.Failed)) {
            case Right(pair) => match (pair) {
                case (msg, code) => failedOk = (msg == "boom" && code == 7)
                case _ => ()
            }
            case _ => ()
        }
        @Assert(failedOk)

        let p = Status.Pending
        var pendingOk = false
        match (@Lucida(p?.Pending)) {
            case Right(_) => pendingOk = true
            case _ => ()
        }
        @Assert(pendingOk)

        let updated = @Lucida(f?.Failed <- ("ok", 0))
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
        match (@Lucida(w?.Sealed)) {
            case Right(v) => ok = (v == 3)
            case _ => ()
        }
        @Assert(ok)

        let e = Envelope<Int64>.Vacant
        var emptyOk = false
        match (@Lucida(e?.Vacant)) {
            case Right(_) => emptyOk = true
            case _ => ()
        }
        @Assert(emptyOk)
    }
}

@Test
class EnumPrismLaws {
    // ===== forward =====
    // With a source present, @Lucida(src?.Case) evaluates the prism directly:
    // matching case -> Right(payload), mismatched -> Left(source).
    @TestCase
    func forwardMatchAndMismatch(): Unit {
        let c = Shape.Circle(Nested(3))
        let s = Shape.Square(2)
        @Assert(isRightCircle(@Lucida(c?.Circle), 3))
        @Assert(isLeftSquare(@Lucida(s?.Circle), 2))
        @Assert(isRightSquare(@Lucida(s?.Square), 2))
        @Assert(isLeftCircle(@Lucida(c?.Square)))
    }

    // ===== backward rebuilds the case with the new payload =====
    @TestCase
    func backwardRebuilds(): Unit {
        let circleVal = Shape.Circle(Nested(1))
        // Sourceless @TypeOf form constructs the first-class affine itself.
        let aff = @Lucida(@TypeOf(circleVal)?.Circle)
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
        let updated = @Lucida(sq?.Circle <- Nested(99))
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
        let updated = @Lucida(c?.Circle.n <- 7)
        var updatedOk = false
        match (updated) {
            case Circle(inner) => updatedOk = inner.n == 7
            case _ => ()
        }
        @Assert(updatedOk)

        // non-matching source stays untouched
        let sq = Shape.Square(4)
        let untouched = @Lucida(sq?.Circle.n <- 7)
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
        let fwdBack = @Lucida(c?.Circle)
        var agree = false
        match (fwdBack) {
            case Right(p) =>
                let back = @Lucida(@TypeOf(c)?.Circle)
                match (back.update(c, p)) {
                    case Circle(inner) => agree = inner.n == 3
                    case _ => ()
                }
            case _ => ()
        }
        @Assert(agree)
    }
}

func isRightCircle(e: Either<Shape, Nested>, expectedN: Int64): Bool {
    if (let Right(p) <- e) {
        return p.n == expectedN
    }
    return false
}

func isRightSquare(e: Either<Shape, Int64>, expectedV: Int64): Bool {
    if (let Right(v) <- e) {
        return v == expectedV
    }
    return false
}

// Mismatched-case forward returns Left carrying the ORIGINAL source.
func isLeftSquare(e: Either<Shape, Nested>, originalSquareValue: Int64): Bool {
    if (let Left(src) <- e) {
        match (src) {
            case Square(v) => return v == originalSquareValue
            case _ => return false
        }
    }
    return false
}

func isLeftCircle(e: Either<Shape, Int64>): Bool {
    if (let Left(src) <- e) {
        match (src) {
            case Circle(_) => return true
            case _ => return false
        }
    }
    return false
}
