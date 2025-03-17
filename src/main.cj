package optics_experiments 
// 
// import lucida_macro.Lucida
// import lucida_macro.DeriveLenses
// import lucida.*
// import std.deriving.*
// 
// 
// import optics_experiments.other.B
// 
// @Derive[ToString]
// @DeriveLenses
// struct A {
//     A(
//         public var x: B,
//         public var y: String
//     ) {}
// }
// 
// 
// main() {
//     let bow = A(B("Brave", "Old"), "World")
// 
//     let bnw = @Lucida(bow.x.y = "New")
// 
//     println("Old value: ")
//     println(bow)
//     println("New value: ")
//     println(bnw)
// }

import lucida_macro.Lucida
import lucida_macro.DeriveLenses
import lucida.*
import std.deriving.*

import optics_experiments.a.*
import optics_experiments.b.*

main() {
    let bow = A(B("Brave", "Old"), "World")
    let bnw = @Lucida(bow.x.y = "New")
    let bnwxyLens = @Lucida(bnw.x.y)
    let bnstw = bnwxyLens.update(bnw, "Newest")

    println("Old value: ")
    println(bow)
    println("New value: ")
    println(bnw)
    println("Newest value: ")
    println(bnstw)
}