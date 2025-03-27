package optics_experiments.bench.compose

import std.unittest.*
import std.unittest.testmacro.*

import std.deriving.*

import lucida.*

public var test: Option<A> = None
public let bow = A(Cons("Brave", Cons("Old", Nil)), "World") 

@Derive[ToString]
public enum EnumList<T> {
    | Nil
    | Cons(T, EnumList<T>)
}

@Derive[ToString]
public struct A {
    public A(
        public var x: EnumList<String>,
        public var y: String
    ) { }
}

sealed interface __A_optics_impl {
    // view
    @Frozen
    func __x_impl_forward(source: A): EnumList<String>
    // update
    @Frozen
    func __x_impl_backward(source: A, focus: EnumList<String>): A
    // view
    @Frozen
    func __y_impl_forward(source: A): String
    // update
    @Frozen
    func __y_impl_backward(source: A, focus: String): A
}
extend Lenses<A> <: __A_optics_impl {
    // view
    @Frozen
    public func __x_impl_forward(source: A): EnumList<String> {
        source.x
    }
    // update
    @Frozen
    public func __x_impl_backward(source: A, focus: EnumList<String>): A {
        A(focus, source.y)
    }
    // view
    @Frozen
    public func __y_impl_forward(source: A): String {
        source.y
    }
    // update
    @Frozen
    public func __y_impl_backward(source: A, focus: String): A {
        A(source.x, focus)
    }
}


sealed interface __A_suboptics_accessors {
    @Frozen
    func __x_optics(_: Magical<A>): Magical<EnumList<String>>
    @Frozen
    func __y_optics(_: Magical<A>): Magical<String>
}
extend Magical<A> <: __A_suboptics_accessors {
    @Frozen
    public func __x_optics(_: Magical<A>): Magical<EnumList<String>> { Magical() }
    @Frozen
    public func __y_optics(_: Magical<A>): Magical<String> { Magical() }
}

sealed interface __A_downcast {
    @Frozen
    func __downcast(_: Magical<A>): Lenses<A>
}
extend Magical<A> <: __A_downcast {
    @Frozen
    public func __downcast(_: Magical<A>): Lenses<A> { Lenses() }
}


sealed interface __EnumList_T_optics_impl<T> {
    @Frozen
    func __nil_impl_forward(source: EnumList<T>): Either<EnumList<T>, Unit>
    @Frozen
    func __nil_impl_backward(from: Unit): EnumList<T>
    @Frozen
    func __cons_impl_forward(source: EnumList<T>): Either<EnumList<T>, (T, EnumList<T>)>
    @Frozen
    func __cons_impl_backward(from: (T, EnumList<T>)): EnumList<T>
}

extend <T> Prisms<EnumList<T>> <: __EnumList_T_optics_impl<T> {
    @Frozen
    public func __nil_impl_forward(source: EnumList<T>): Either<EnumList<T>, Unit> {
        if (let Nil <- source) { Right<EnumList<T>, Unit>(()) } else { Left<EnumList<T>, Unit>(source) }
    }
    @Frozen
    public func __nil_impl_backward(_: Unit): EnumList<T> {
        EnumList<T>.Nil
    }
    @Frozen
    public func __cons_impl_forward(source: EnumList<T>): Either<EnumList<T>, (T, EnumList<T>)> {
        if (let Cons(v, n) <- source) { Right<EnumList<T>, (T, EnumList<T>)>((v, n)) } else { Left<EnumList<T>, (T, EnumList<T>)>(source) }
    }
    @Frozen
    public func __cons_impl_backward(froom: (T, EnumList<T>)): EnumList<T> {
        let (v, n) = froom
        EnumList<T>.Cons(v, n)
    }
}

// ONLY IF SUCCESS....
sealed interface __EnumList_T_suboptics_accessors<T> {
    @Frozen
    func __nil_optics(_: Magical<EnumList<T>>): Magical<Unit>
    @Frozen
    func __cons_optics(_: Magical<EnumList<T>>): Magical<(T, EnumList<T>)>
}
extend <T> Magical<EnumList<T>> <: __EnumList_T_suboptics_accessors<T> {
    @Frozen
    public func __nil_optics(_: Magical<EnumList<T>>): Magical<Unit> { Magical() }
    @Frozen
    public func __cons_optics(_: Magical<EnumList<T>>): Magical<(T, EnumList<T>)> { Magical() }
}

sealed interface __EnumList_T_downcast<T> {
    @Frozen
    func __downcast(_: Magical<EnumList<T>>): Prisms<EnumList<T>>
}
extend <T> Magical<EnumList<T>> <: __EnumList_T_downcast<T> {
    @Frozen
    public func __downcast(_: Magical<EnumList<T>>): Prisms<EnumList<T>> {
        Prisms()
    }
}

// sealed interface __Tuple2_T_G_optics_impl<T, G> {
//     @Frozen
//     func __fst_impl_forward(source: (T, G)): T
//     @Frozen
//     func __fst_impl_backward(source: (T, G), focus: T): (T, G)
//     @Frozen
//     func __snd_impl_forward(source: (T, G)): G
//     @Frozen
//     func __snd_impl_backward(source: (T, G), focus: G): (T, G)
// }
extend <T, G> Lenses<(T, G)> /* <: __Tuple2_T_G_optics_impl<T, G> */ {
    @Frozen
    public func __fst_impl_forward(source: (T, G)): T { let (t, _) = source; t }
    @Frozen
    public func __fst_impl_backward(source: (T, G), focus: T): (T, G) { let (_, g) = source; (focus, g) }
    @Frozen
    public func __snd_impl_forward(source: (T, G)): G { let (_, g) = source; g }
    @Frozen
    public func __snd_impl_backward(source: (T, G), focus: G): (T, G) { let (t, _) = source; (t, focus) }
}

// sealed interface __Tuple2_T_G_suboptics_accessors<T, G> {
//     @Frozen
//     func __fst_optics(_: Magical<(T, G)>): Magical<T>
//     @Frozen
//     func __snd_optics(_: Magical<(T, G)>): Magical<G>
// }
extend <T, G> Magical<(T, G)> /* <: __Tuple2_T_G_suboptics_accessors<T, G> */ {
    @Frozen
    public func __fst_optics(_: Magical<(T, G)>): Magical<T> { Magical() }
    @Frozen
    public func __snd_optics(_: Magical<(T, G)>): Magical<G> { Magical() }
}

// sealed interface __Tuple2_T_G_downcast<T, G> {
//     @Frozen
//     func __downcast(_: Magical<(T, G)>): Lenses<(T, G)>
// }
extend <T, G> Magical<(T, G)> /* <: __Tuple2_T_G_downcast<T, G> */ {
    @Frozen
    public func __downcast(_: Magical<(T, G)>): Lenses<(T, G)> { Lenses() }
}

@Test
@Configure[baseline: "reconstruction"]
class StructMutBenchmark {
    @Bench
    func reconstruction(): Unit {
        let bnw = if (let Cons(v1, Cons(_, t2)) <- bow.x) {
            A(Cons(v1, Cons("New", t2)), bow.y)
        } else {
            bow
        }
        test = bnw
    }

    @Bench
    func opticsBaseline(): Unit {
        // let bnw = @Lucida(bow.x &> @Type(EnumList<String>).Cons &> nth(2) &> @Type(EnumList<String>).Cons &> nth(1) = "New")
        let bnw = { =>
            let magic0 = magic(bow)
            let optics0 = magic0.__downcast(magic0)
            let optics0ImplForward = optics0.__x_impl_forward // Getter A.x
            let optics0ImplBackward = optics0.__x_impl_backward // Setter A.x

            let magic1 = magic0.__x_optics(magic0)  // Magical<EnumList<String>>
            let optics1 = magic1.__downcast(magic1) // Prism<EnumList<String>>
            let optics1ImplForward = optics1.__cons_impl_forward // Match Cons
            let optics1ImplBackward = optics1.__cons_impl_backward // Build Cons

            let magic2 = magic1.__cons_optics(magic1) // Magical<(String, EnumList<String>)>
            let expect1 = whatExpect(optics0, optics1, magic2)
            let composedForward1 = composeForward(optics0, optics1, magic2)(optics0ImplForward, optics1ImplForward, optics0ImplBackward, optics1ImplBackward)
            let composedBackward1 = composeBackward(optics0, optics1, magic2)(optics0ImplForward, optics1ImplForward, optics0ImplBackward, optics1ImplBackward)

            let optics2 = magic2.__downcast(magic2) // Lenses<(String, EnumList<String>)>
            let optics2ImplForward = optics2.__snd_impl_forward // Get 2nd argument
            let optics2ImplBackward = optics2.__snd_impl_backward // Rebuild pair via replacing 2nd

            let magic3 = magic2.__snd_optics(magic2) // Magical<EnumList<String>>
            let expect2 = whatExpect(expect1, optics2, magic3) // Optionals<A>
            let composedForward2 = composeForward(expect1, optics2, magic3)(composedForward1, optics2ImplForward, composedBackward1, optics2ImplBackward)
            let composedBackward2 = composeBackward(expect1, optics2, magic3)(composedForward1, optics2ImplForward, composedBackward1, optics2ImplBackward)

            let optics3 = magic3.__downcast(magic3) // Prisms<EnumList<String>>
            let optics3ImplForward = optics3.__cons_impl_forward // Match Cons
            let optics3ImplBackward = optics3.__cons_impl_backward // Build Cons

            let magic4 = magic3.__cons_optics(magic3) // Magical<(String, EnumList<String>)>
            let expect3 = whatExpect(expect2, optics3, magic4) // Optionals<A>
            let composedForward3 = composeForward(expect2, optics3, magic4)(composedForward2, optics3ImplForward, composedBackward2, optics3ImplBackward)
            let composedBackward3 = composeBackward(expect2, optics3, magic4)(composedForward2, optics3ImplForward, composedBackward2, optics3ImplBackward)

            let optics4 = magic4.__downcast(magic4) // Lenses<(String, EnumList<String>)>
            let optics4ImplForward = optics4.__fst_impl_forward // Get first argument
            let optics4ImplBackward = optics4.__fst_impl_backward // Rebuild pair via replacing 1st

            let magic5 = magic4.__fst_optics(magic4) // Magical<String>
            let expect4 = whatExpect(expect3, optics4, magic5) // Optionals<A>
            let composedForward4 = composeForward(expect3, optics4, magic5)(composedForward3, optics4ImplForward, composedBackward3, optics4ImplBackward)
            let composedBackward4 = composeBackward(expect3, optics4, magic5)(composedForward3, optics4ImplForward, composedBackward3, optics4ImplBackward)
            composedBackward4(bow, "New")
        }()

        test = bnw
    }


    @AfterAll
    func aa(): Unit {
        let _ = test
    }
}
