package optics_experiments.test

import std.unittest.*
import std.unittest.testmacro.*

@Test
class SmokeTest {
    @TestCase
    func assertsWork(): Unit {
        @Assert(1 + 1 == 2)
        @Assert(3 > 2)
    }
}
