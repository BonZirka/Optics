package optics_experiments.bench.inlining.other_package.a

import optics_experiments.bench.inlining.other_package.b.*

public struct Ainl {
    @Frozen
    public Ainl(
        public var x: Binl,
        public var y: String
    ) {}
}

public struct AinlOpticality {
    @Frozen
    public func __lens_x_view(source: Ainl) { source.x }
    @Frozen
    public func __lens_x_update(source: Ainl, focus: Binl) { Ainl(focus, source.y) }
    @Frozen
    public func __lens_y_view(source: Ainl) { source.y }
    @Frozen
    public func __lens_y_update(source: Ainl, focus: String) { Ainl(source.x, focus) }
}
