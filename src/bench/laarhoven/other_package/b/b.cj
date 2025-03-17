package optics_experiments.bench.laarhoven.other_package.b

public struct B {
    @Frozen
    public B(
        public var x: String,
        public var y: String
    ) {}
}

public struct BOpticality {
    @Frozen
    public func __lens_x_view(source: B) { source.x }
    @Frozen
    public func __lens_x_update(source: B, focus: String) { B(focus, source.y) }
    @Frozen
    public func __lens_y_view(source: B) { source.y }
    @Frozen
    public func __lens_y_update(source: B, focus: String) { B(source.x, focus) }
}