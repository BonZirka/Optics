package optics_experiments.a

import lucida_macro.DeriveLenses
import lucida.*
import std.deriving.*

import optics_experiments.b.*

@Derive[ToString]
@DeriveLenses
public struct A {
    public A(
        public var x: B,
        public var y: String
    ) {}
}