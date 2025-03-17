package optics_experiments.b

// import lucida_macro.Lucida
// import lucida_macro.DeriveLenses
// import lucida.*
// 
// import std.deriving.*
// 
// @Derive[ToString]
// @DeriveLenses
// public struct B {
//     public B(
//         public var x: String,
//         public var y: String
//     ) {}
// }

import lucida_macro.Lucida
import lucida_macro.DeriveLenses
import lucida.*

import std.deriving.*

@Derive[ToString]
@DeriveLenses
public struct B {
    public B(
        public var x: String,
        public var y: String
    ) { }
}