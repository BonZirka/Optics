package optics_experiments.test

import std.unittest.testmacro.*
import std.unittest.*

import lucida_macro.Lucida
import lucida_macro.DeriveLenses
import lucida.*

@DeriveLenses
class ClassWithState {
    ClassWithState(
        public var state: Int32
    ) {}
}

@DeriveLenses
struct ClassRefs {
    ClassRefs(
        public var c: ClassWithState
    ) {}
}

@Test
@Tag[Lens]
func checkCloning() {
    let a = ClassWithState(32)
    let b = @Lucida(a.state = 64)

    @Assert[refNeqAssert](a, b)
    @Assert(a.state, 32)
    @Assert(b.state, 64)
}

@Test
@Tag[Lens]
func checkRef() {
    let a = ClassWithState(32)
    let b = ClassRefs(a)

    let res = @Lucida(b.c.state = 64)

    @Assert[refEqAssert](a, b.c)
    @Assert[refNeqAssert](a, res.c)
    @Assert[refNeqAssert](b.c, res.c)
    @Assert(b.c.state, 32)
    @Assert(res.c.state, 64)
}