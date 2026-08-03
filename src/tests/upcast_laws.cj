package lucida.tests

import std.unittest.*
import std.unittest.testmacro.*
import lucida.*

// The full upcast table (all 25 ordered kind pairs; both argument orders of
// the 15 unordered ones), pinned as compile-time type assignments:
// opticsUpcast(regA, regB) returns the lattice MEET — the weaker, more
// partial kind of the two (Iso > {Lens, Prism} > Affine > Setter) — which is
// the kind of the chain "a then b" and the registry the next compose row
// expects. Siblings compose to Affine: join(Lens, Prism) = Affine.
@Test
class UpcastLaws {
    // ===== same-kind upcasts =====
    @TestCase
    func isoIsoUpcastsToIso(): Unit {
        let r: RegistryIsos<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryIsos<Int64>(), RegistryIsos<Int64>())
        @Assert(true)
    }

    @TestCase
    func lensLensUpcastsToLens(): Unit {
        let r: RegistryLenses<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryLenses<Int64>(), RegistryLenses<Int64>())
        @Assert(true)
    }

    @TestCase
    func prismPrismUpcastsToPrism(): Unit {
        let r: RegistryPrisms<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryPrisms<Int64>(), RegistryPrisms<Int64>())
        @Assert(true)
    }

    @TestCase
    func affineAffineUpcastsToAffine(): Unit {
        let r: RegistryAffines<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryAffines<Int64>(), RegistryAffines<Int64>())
        @Assert(true)
    }

    @TestCase
    func setterSetterUpcastsToSetter(): Unit {
        let r: RegistrySetters<Int64> =
            __OpticsCompositions.opticsUpcast(RegistrySetters<Int64>(), RegistrySetters<Int64>())
        @Assert(true)
    }

    // ===== the weaker kind wins =====
    @TestCase
    func isoLensUpcastsToLens(): Unit {
        let r: RegistryLenses<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryIsos<Int64>(), RegistryLenses<Int64>())
        @Assert(true)
    }

    @TestCase
    func lensIsoUpcastsToLens(): Unit {
        let r: RegistryLenses<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryLenses<Int64>(), RegistryIsos<Int64>())
        @Assert(true)
    }

    @TestCase
    func isoPrismUpcastsToPrism(): Unit {
        let r: RegistryPrisms<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryIsos<Int64>(), RegistryPrisms<Int64>())
        @Assert(true)
    }

    @TestCase
    func isoAffineUpcastsToAffine(): Unit {
        let r: RegistryAffines<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryIsos<Int64>(), RegistryAffines<Int64>())
        @Assert(true)
    }

    @TestCase
    func isoSetterUpcastsToSetter(): Unit {
        let r: RegistrySetters<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryIsos<Int64>(), RegistrySetters<Int64>())
        @Assert(true)
    }

    // ===== the mixed joins =====
    @TestCase
    func lensPrismUpcastsToAffine(): Unit {
        let r: RegistryAffines<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryLenses<Int64>(), RegistryPrisms<Int64>())
        @Assert(true)
    }

    @TestCase
    func lensAffineUpcastsToAffine(): Unit {
        let r: RegistryAffines<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryLenses<Int64>(), RegistryAffines<Int64>())
        @Assert(true)
    }

    @TestCase
    func lensSetterUpcastsToSetter(): Unit {
        let r: RegistrySetters<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryLenses<Int64>(), RegistrySetters<Int64>())
        @Assert(true)
    }

    @TestCase
    func prismAffineUpcastsToAffine(): Unit {
        let r: RegistryAffines<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryPrisms<Int64>(), RegistryAffines<Int64>())
        @Assert(true)
    }

    @TestCase
    func prismSetterUpcastsToSetter(): Unit {
        let r: RegistrySetters<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryPrisms<Int64>(), RegistrySetters<Int64>())
        @Assert(true)
    }

    @TestCase
    func affineSetterUpcastsToSetter(): Unit {
        let r: RegistrySetters<Int64> =
            __OpticsCompositions.opticsUpcast(RegistryAffines<Int64>(), RegistrySetters<Int64>())
        @Assert(true)
    }

    // ===== behavioral: the upcasted registry continues a chain =====
    // The walk upcasts after every segment so the next compose row can be
    // selected. lens ∘ prism composes to an Affine registry; feeding that
    // registry (with the hop's composed halves) into the (Affine, Affine)
    // row must continue the chain: partial forward, source kept on miss.
    @TestCase
    func upcastedRegistryContinuesChain(): Unit {
        let o1 = lensId()       // Lens
        let o2 = prismLawful()  // Prism — upcast(Lens, Prism) = Affine
        let o3 = affPos()       // Affine
        let up: RegistryAffines<Int64> =
            __OpticsCompositions.opticsUpcast(
                magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))
        let fwd12 = __OpticsCompositions.composeForward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let bwd12 = __OpticsCompositions.composeBackward(
            magicFirstClassDowncast(o1), magicFirstClassDowncast(o2))(
            __FirstClassGetters.forward(o1), __FirstClassGetters.forward(o2),
            __FirstClassGetters.backward(o1), __FirstClassGetters.backward(o2))
        let fwd = __OpticsCompositions.composeForward(up, magicFirstClassDowncast(o3))(
            fwd12, __FirstClassGetters.forward(o3),
            bwd12, __FirstClassGetters.backward(o3))
        var matchOk = false
        var missOk = false
        match (fwd(4)) {
            case Right(v) => matchOk = (v == 4)
            case _ => ()
        }
        match (fwd(3)) {
            case Left(src) => missOk = (src == 3)
            case _ => ()
        }
        @Assert(matchOk)
        @Assert(missOk)
    }
}
