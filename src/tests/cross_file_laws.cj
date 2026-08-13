package lucida.tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.macrodsl.*

@DeriveOptics
public struct ProbeVal {
    public ProbeVal(public let f: Int64) { }
}
public let probeInstance = ProbeVal(1)

@Test
class CrossFileLaws {
    @TestCase
    func crossFileBackward(): Unit {
        let updated = @f(probeInstance.f <- 2)
        @Assert(updated.f == 2)
    }

    @TestCase
    func crossFileForward(): Unit {
        let got = @f(probeInstance.f)
        @Assert(got == 1)
    }

    @TestCase
    func crossFileTypeOf(): Unit {
        let lens = @f(@typeof(probeInstance).f)
        @Assert(lens.view(probeInstance) == 1)
    }
}
