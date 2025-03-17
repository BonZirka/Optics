package optics_experiments.bench.inlining.other_package

import std.unittest.*
import std.unittest.testmacro.*

import optics_experiments.bench.inlining.other_package.a.*
import optics_experiments.bench.inlining.other_package.b.*
import optics_experiments.bench.inlining.other_package.lib.*


public var test: Option<Ainl> = None;
public let bow = Ainl(Binl("Brave", "Old"), "World")

@Test
@Configure[baseline: "nativeBaseline"]
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
        let bnw = highOrderComposeLensesSetter(AinlOpticality().__lens_x_view, AinlOpticality().__lens_x_update, BinlOpticality().__lens_y_update)(bow, "New")
        test = bnw
    }

    @Bench
    func reconstruction(): Unit {
        let bnw = Ainl(Binl(bow.x.x, "New"), bow.y)
        test = bnw
    }

    @AfterAll
    func aa(): Unit {
        let _ = test
    }
}