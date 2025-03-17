package optics_experiments.bench.laarhoven.other_package.a

import optics_experiments.bench.laarhoven.other_package.b.*

public struct A {
    @Frozen
    public A(
        public var x: B,
        public var y: String
    ) {}
}

public struct AOpticality {
    @Frozen
    public func __lens_x_view(source: A) { source.x }
    @Frozen
    public func __lens_x_update(source: A, focus: B) { A(focus, source.y) }
    @Frozen
    public func __lens_y_view(source: A) { source.y }
    @Frozen
    public func __lens_y_update(source: A, focus: String) { A(source.x, focus) }
}
