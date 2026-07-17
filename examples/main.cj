package optics_experiments 

import std.deriving.*

import lucida.macrodsl.*
import lucida.*
import lucida.stdlib.*

@Derive[ToString]
@DeriveOptics
public struct A {
    A(
        public let x: String
    ) { }
}

main() {
    let x = A("Hello")
    let firstClass = @Lucida(@TypeOf(x).coerce<String>())
    let setter = @Lucida(@Optic(firstClass) <- "Bye")
    let evaled = @Lucida(x.@Optic(setter))

    println(evaled)
    let y = [3, 4, 5]
    let updated = @Lucida(y.at(2) <- 100)
    println(updated)
}