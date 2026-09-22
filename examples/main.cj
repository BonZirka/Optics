package optics_experiments 

import std.deriving.*

import lucida.macrodsl.*
import lucida.*
import lucida_stdlib.*

@Derive[ToString]
@DeriveOptics
public struct A {
    A(
        public let x: String
    ) { }
}

main() {
    let x = A("Hello")
    let firstClass = @f(@typeof(x).coerce<String>())
    let setter = @f(@use(firstClass) <- "Bye")
    let evaled = @f(x.@use(setter))

    println(evaled)
    let y = [3, 4, 5]
    let updated = @f(y.at(2) <- 100)
    println(updated)
}