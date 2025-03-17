package optics_experiments.bench.inlining.other_package.b

public struct Binl {
    @Frozen
    public Binl(
        public var x: String,
        public var y: String
    ) {}
}

public struct BinlOpticality {
    @Frozen
    public func __lens_x_view(source: Binl) { source.x }
    @Frozen
    public func __lens_x_update(source: Binl, focus: String) { Binl(focus, source.y) }
    @Frozen
    public func __lens_y_view(source: Binl) { source.y }
    @Frozen
    public func __lens_y_update(source: Binl, focus: String) { Binl(source.x, focus) }
}