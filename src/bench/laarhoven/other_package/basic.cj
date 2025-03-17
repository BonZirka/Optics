package optics_experiments.bench.laarhoven.other_package

import std.unittest.*
import std.unittest.testmacro.*

import optics_experiments.bench.laarhoven.other_package.a.*
import optics_experiments.bench.laarhoven.other_package.b.*
import optics_experiments.bench.laarhoven.other_package.lib.*


public var test: Option<A> = None;
public let bow = A(B("Brave", "Old"), "World")

@Test
@Configure[baseline: "reconstruction"]
class StructMutBenchmark {

    @Bench
    func nativeBaseline(): Unit {
        var bnw_ = bow
        bnw_.x.y = "New"
        let bnw = bnw_ 
        test = bnw
    }

    @Bench
    func highOrderComposition(): Unit {
        let lensA = createLensWriter(AOpticality().__lens_x_view, AOpticality().__lens_x_update)
        let lensB = createLensWriter(BOpticality().__lens_y_view, BOpticality().__lens_y_update)
        let composition = composeFunc(lensB, lensA)
        let bnw = update(composition, bow, "New")
        test = bnw
    }

    @Bench
    func reconstruction(): Unit {
        let bnw = A(B(bow.x.x, "New"), bow.y)
        test = bnw
    }

    @AfterAll
    func aa(): Unit {
        let _ = test
    }
}