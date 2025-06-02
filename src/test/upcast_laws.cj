package optics_experiments.test

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*

@Test
class UpcastLaws {
    // §1.2 regression: composing two setters must upcast to a SETTER registry.
    // Assigned type RegistrySetters makes this a compile-time assertion.
    @TestCase
    func settersComposeToSetters(): Unit {
        let r: RegistrySetters<Int64> =
            __OpticsCompositions.opticsUpcast(RegistrySetters<Int64>(), RegistrySetters<Int64>())
        @Assert(true)
    }
}
