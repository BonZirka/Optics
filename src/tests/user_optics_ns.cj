package lucida.tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.macrodsl.*

// Same-named optics over different source types, collected in one namespace.
@Optics({
    @Lens[source: String, focus: Int64, forward: { source.size }, backward: { focus.toString() }]
    struct slen {}

    @Lens[source: Array<Int64>, focus: Int64, forward: { source[0] }, backward: { let a = source.clone(); a[0] = focus; a }]
    struct slen {}

    @Prism[source: Array<Int64>, focus: Int64, forward: { source.get(0) }, backward: { [focus] }]
    struct spar {}
})

@Test
class OpticsNamespace {
    @TestCase
    func sameNameDifferentSources(): Unit {
        let s = "abc"
        let got = @f(s.slen())
        @Assert(got == 3)
        let written = @f(s.slen() <- 7)
        @Assert(written == "7")
        let arr = [1, 2, 3]
        let gotArr = @f(arr.slen())
        @Assert(gotArr == 1)
        let arrUpd = @f(arr.slen() <- 9)
        @Assert(arrUpd[0] == 9)
    }

    @TestCase
    func prismInNamespace(): Unit {
        let m = [9, 8]
        match (@f(m?.spar())) {
            case Some(v) => @Assert(v == 9)
            case None => @Assert(false)
        }
        let back = @f(m?.spar() <- 5)
        @Assert(back[0] == 5)
        let miss: Array<Int64> = []
        match (@f(miss?.spar())) {
            case Some(_) => @Assert(false)
            case None => @Assert(true)
        }
    }
}
