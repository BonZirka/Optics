package optics_experiments.test

import std.unittest.testmacro.*
import std.unittest.*

@CustomAssertion
func refNeqAssert<T>(ctx: AssertionCtx, a: T, b: T) {
    let obj_a = a as Object ?? throw Exception("a")
    let obj_b = b as Object ?? throw Exception("b")
    if (refEq(obj_a, obj_b)) {
        ctx.fail("${ctx.arg("a")} and ${ctx.arg("b")} are referencing the same object")
    }
}

@CustomAssertion
func refEqAssert<T>(ctx: AssertionCtx, a: T, b: T) {
    let obj_a = a as Object ?? throw Exception("a")
    let obj_b = b as Object ?? throw Exception("b")
    if (!refEq(obj_a, obj_b)) {
        ctx.fail("${ctx.arg("a")} and ${ctx.arg("b")} are referencing the different object")
    }
}

/**
 * Idea is that if multiple asserions occur inside custom assertin then all of then should pass.
 * Thus we can batch our assertions, verify invariants and after that proceed further 
 */
@CustomAssertion
func allPassed<T>(ctx: AssertionCtx, checks: Array<(T, T)>) where T <: Equatable<T> {
    let iterator = checks.iterator()
    var nextval = iterator.next()
    while (let Some(pair) <- nextval) {
        let (v1, v2) = pair
        @Expect(v1, v2)
        nextval = iterator.next()
    }
}