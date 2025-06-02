package optics_experiments.test

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida_macro.*

@DeriveOptics
public struct Nested {
    public Nested(public let n: Int64) { }
}

@DeriveOptics
public enum Shape {
    | Circle(Nested)
    | Square(Int64)
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
        let updated = @Lucida(sq?.Circle, Nested(99))
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
        let updated = @Lucida(c?.Circle.n, 7)
        var updatedOk = false
        match (updated) {
            case Circle(inner) => updatedOk = inner.n == 7
            case _ => ()
        }
        @Assert(updatedOk)

        // non-matching source stays untouched
        let sq = Shape.Square(4)
        let untouched = @Lucida(sq?.Circle.n, 7)
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
