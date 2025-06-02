package optics_experiments.bench.depth

import std.deriving.*

import std.unittest.*
import std.unittest.testmacro.*

import lucida.*
import lucida_macro.*
import macro_test_utils.*

@GenerateNestedStruct(10)

public var test: Option<Struct_1> = None;
public let bow = @GenerateInit(10)

@Test
@Configure[baseline: "reconstruction"]
class StructMutBenchmark {

    @Bench
    func nativeBaseline(): Unit {
        var _bnw = bow
        @GenerateStructSetting(_bnw, 10)
        let bnw = _bnw
        test = bnw
    }

    @Bench
    func opticsBaseline(): Unit {
        let bnw = @GenerateLucidaCall(bow, 10)
        test = bnw
    }

    @Bench
    func reconstruction(): Unit {
        let bnw = @GenerateReconstruct(bow, 10)
        test = bnw
    }

    @AfterAll
    func aa(): Unit {
        let _ = test
    }
}
