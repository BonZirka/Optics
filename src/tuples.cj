package lucida

import lucida.macrodsl.*

@GenerateTupleExtendsLenses(3)


extend < X0, X1 > RegistryMagical <(X0, X1) > {
    @Frozen
    public func ___0_optics(_: RegistryMagical<(X0, X1)>): RegistryMagical<X0> {
        RegistryMagical()
    }
    @Frozen
    public func ___1_optics(_: RegistryMagical<(X0, X1)>): RegistryMagical<X1> {
        RegistryMagical()
    }
    @Frozen
    public func __downcast(_: RegistryMagical<(X0, X1)>): RegistryLenses<(X0, X1)> {
        RegistryLenses()
    }
}
extend < X0, X1, X2 > RegistryMagical <(X0, X1, X2) > {
    @Frozen
    public func ___0_optics(_: RegistryMagical<(X0, X1, X2)>): RegistryMagical<X0> {
        RegistryMagical()
    }
    @Frozen
    public func ___1_optics(_: RegistryMagical<(X0, X1, X2)>): RegistryMagical<X1> {
        RegistryMagical()
    }
    @Frozen
    public func ___2_optics(_: RegistryMagical<(X0, X1, X2)>): RegistryMagical<X2> {
        RegistryMagical()
    }
    @Frozen
    public func __downcast(_: RegistryMagical<(X0, X1, X2)>): RegistryLenses<(X0, X1, X2)> {
        RegistryLenses()
    }
}
