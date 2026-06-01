package optics_experiments.test

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida_macro.*

@DeriveOptics
public struct ProbeVal {
    public ProbeVal(public let f: Int64) { }
}
public let probeInstance = ProbeVal(1)

@Test
class CrossFileLaws {
    @TestCase
    func crossFileBackward(): Unit {
        let updated = @Lucida(probeInstance.f <- 2)
        @Assert(updated.f == 2)
    }

    @TestCase
    func crossFileForward(): Unit {
        @Assert(@Lucida(probeInstance.f) == 1)
    }

    @TestCase
    func crossFileTypeOf(): Unit {
        let lens = @Lucida(@TypeOf(probeInstance).f)
        @Assert(lens.view(probeInstance) == 1)
    }
}
