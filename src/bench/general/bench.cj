package optics_experiments.bench.general

import std.deriving.*

import std.unittest.*
import std.unittest.testmacro.*

import lucida.*

@Derive[ToString]
public struct A {
    public A(
        public var x: B,
        public var y: String
    ) { }
}

@Derive[ToString]
public struct B {
    public B(
        public var x: String,
        public var y: String
    ) { }
}

public var test: Option<A> = None;
public let bow = A(B("Brave", "Old"), "World")

sealed interface __A_optics_impl {
    // view
    @Frozen
    func __x_impl_forward(source: A): B
    // update
    @Frozen
    func __x_impl_backward(source: A, focus: B): A
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
    public func __x_impl_forward(source: A): B {
        source.x
    }
    // update
    @Frozen
    public func __x_impl_backward(source: A, focus: B): A {
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
    func __x_optics(_: Magical<A>): Magical<B>
    @Frozen
    func __y_optics(_: Magical<A>): Magical<String>
}
extend Magical<A> <: __A_suboptics_accessors {
    @Frozen
    public func __x_optics(_: Magical<A>): Magical<B> { Magical() }
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


sealed interface __B_optics_impl {
    // view
    @Frozen
    func __x_impl_forward(source: B): String
    // update
    @Frozen
    func __x_impl_backward(source: B, focus: String): B
    // view
    @Frozen
    func __y_impl_forward(source: B): String
    // update
    @Frozen
    func __y_impl_backward(source: B, focus: String): B
}

extend Lenses<B> <: __B_optics_impl {
    // view
    @Frozen
    public func __x_impl_forward(source: B): String {
        source.x
    }
    // update
    @Frozen
    public func __x_impl_backward(source: B, focus: String): B {
        B(focus, source.y)
    }
    // view
    @Frozen
    public func __y_impl_forward(source: B): String {
        source.y
    }
    // update
    @Frozen
    public func __y_impl_backward(source: B, focus: String): B {
        B(source.x, focus)
    }
}


sealed interface __B_suboptics_accessors {
    @Frozen
    func __x_optics(_: Magical<B>): Magical<String>
    @Frozen
    func __y_optics(_: Magical<B>): Magical<String>
}
extend Magical<B> <: __B_suboptics_accessors {
    @Frozen
    public func __x_optics(_: Magical<B>): Magical<String> { Magical() }
    @Frozen
    public func __y_optics(_: Magical<B>): Magical<String> { Magical() }
}

sealed interface __B_downcast {
    @Frozen
    func __downcast(_: Magical<B>): Lenses<B>
}
extend Magical<B> <: __B_downcast {
    @Frozen
    public func __downcast(_: Magical<B>): Lenses<B> { Lenses() }
}


@Test
@Configure[baseline: "nativeBaseline"]
class StructMutBenchmark {

    @Bench
    func nativeBaseline(): Unit {
        var bnw_ = bow
        bnw_.x.y = "New"
        let bnw = bnw_ 
        test = bnw
    }

    @Bench
    func opticsBaseline(): Unit {
        // @Lucida(bow.x.y = "New")
        let bnw = { => 
            let magic0 = magic(bow)
            let optics0 = magic0.__downcast(magic0)
            let optics0ImplForward = optics0.__x_impl_forward // Getter A.x
            let optics0ImplBackward = optics0.__x_impl_backward // Setter A.x

            let magic1 = magic0.__x_optics(magic0)  // Magical<B>
            let optics1 = magic1.__downcast(magic1) // Lenses<B>
            let optics1ImplForward = optics1.__y_impl_forward // Getter B.y
            let optics1ImplBackward = optics1.__y_impl_backward // Setter B.y

            let magic2 = magic1.__y_optics(magic1) // Magical<String>
            let expect1 = whatExpect(optics0, optics1, magic2) // Lenses<A>
            let composedForward1 = composeForward(optics0, optics1, magic2)(optics0ImplForward, optics1ImplForward, optics0ImplBackward, optics1ImplBackward)
            let composedBackward1 = composeBackward(optics0, optics1, magic2)(optics0ImplForward, optics1ImplForward, optics0ImplBackward, optics1ImplBackward)

            composedBackward1(bow, "New")
        }()

        test = bnw
    }

    @Bench
    func reconstruction(): Unit {
        let bnw = A(B(bow.x.x, "New"), bow.y)
        test = bnw
    }

    @AfterAll
    func aa(): Unit {
        let _ = test
    }
}

// @Derive[ToString]
// public enum EnumList {
//     | Cons(String, EnumList)
//     | Head 
// }
// 
// extend EnumList {
//     public static prop __prism_cons: Prism<EnumList, (String, EnumList)> {
//         get() {
//             createPrism(
//                 { source: EnumList => if (let Cons(s, next) <- source) { Right((s, next)) } else { Left(source) }},
//                 { focus: (String, EnumList) => 
//                     let (s, e) = focus
//                     Cons(s, e)
//                 }
//             )
//         }
//     }
// 
//     public static prop __prism_head: Prism<EnumList, Unit> {
//         get() {
//             createPrism(
//                 { source: EnumList => if (let Head <- source) { Right(()) } else { Left(source) }},
//                 { _ => Head }
//             )
//         }
//     }
// }
// 
// public interface EnumListPrisms {
//     public func consImpl<T>(p1: Optional<T, EnumList>): Optional<T, (String, EnumList)>
// 
//     public func headImpl<T>(p1: Optional<T, EnumList>): Optional<T, Unit> 
// }
// 
// extend Magical<EnumList> <: EnumListPrisms {
//     public func consImpl<T>(p1: Optional<T, EnumList>): Optional<T, (String, EnumList)> {
//         compose(p1, EnumList.__prism_cons)
//     }
// 
// 
//     public func headImpl<T>(p1: Optional<T, EnumList>): Optional<T, Unit> {
//         compose(p1, EnumList.__prism_head)
//     }
// }
// 
// struct Pair<F, G> {}
// 
// extend<F, G> Pair<F, G> {
//     public prop __first_lens: Lens<(F, G), F> {
//         get() {
//             createLens(
//                 { source: (F, G) => 
//                     let (f, _) = source
//                     f
//                 },
//                 { source: (F, G), focus: F => 
//                     let (_, g) = source
//                     (focus, g)
//                 },
//             )
//         }
//     }
//     public prop __second_lens: Lens<(F, G), G> {
//         get() {
//             createLens(
//                 { source: (F, G) => 
//                     let (_, g) = source
//                     g
//                 },
//                 { source: (F, G), focus: G => 
//                     let (f, _) = source
//                     (f, focus)
//                 },
//             )
//         }
//     }
// 
// }
// extend<F, G> Magical<(F, G)> {
//     public func fisrtImpl<T>(p1: Optional<T, (F, G)>): Optional<T, F> {
//         compose(
//             p1,
//             Pair<F, G>().__first_lens   
//         )
//     }
// 
//     public func secondImpl<T>(p1: Optional<T, (F, G)>): Optional<T, G> {
//         compose(
//             p1,
//             Pair<F, G>().__second_lens
//         )
//     }
// }
// 
// let enumBow = Cons("Brave", Cons("Old", Cons("World", Head)))
// 
// public var enumTest: Option<EnumList> = None
// 
// public let optionalNoMagic: Optional<EnumList, String> = createOptional(
//     { _: EnumList => Either<EnumList, String>.Right("don't care") },
//     { source: EnumList, focus: String =>
//         let x0 = identityLens(source)
//         let x1 = compose(x0, EnumList.__prism_cons)
//         let x2 = compose(x1, Pair<String, EnumList>().__second_lens)
//         let x3 = compose(x2, EnumList.__prism_cons)
//         let x4 = compose(x3, Pair<String, EnumList>().__first_lens)
//         x4.update(enumBow, focus)
//     })
// 
// public let optionalInlinedComposition: Optional<EnumList, String> = createOptional(
//     { _: EnumList => Either<EnumList, String>.Right("don't care") },
//     { source: EnumList, focus: String =>
//         let x0 = identityLens(source)
//         let x1 = compose(x0, EnumList.__prism_cons)
//         let x2 = compose(x1, Pair<String, EnumList>().__second_lens)
//         let x3 = compose(x2, EnumList.__prism_cons)
//         let x4 = compose(x3, Pair<String, EnumList>().__first_lens)
//         x4.update(enumBow, focus)
//     }
// )

// @Test
// @Configure[baseline: "nativeBaseline"]
// class EnumMutBenchmark {
// 
//     @Bench
//     func nativeBaseline(): Unit {
//         let enumBnw = if (let Cons(v1, Cons(_, t2)) <- enumBow) { // preview
//             Cons(v1, Cons("New", t2)) // update
//         } else {
//             enumBow
//         }
//         enumTest = enumBnw
//     }
// 
//     @Bench
//     func opticsBaseline(): Unit {
//         let enumBnw = { => 
//             let x0 = identityLens(enumBow)
//             let x1 = magic(x0).consImpl(x0)
//             let x2 = magic(x1).secondImpl(x1)
//             let x3 = magic(x2).consImpl(x2)
//             let x4 = magic(x3).fisrtImpl(x3)
//             x4.update(enumBow, "New")
//         }()
//         enumTest = enumBnw
//     }
// 
//     @Bench
//     func withoutMagic(): Unit {
//         let enumBnw = optionalNoMagic.update(enumBow, "New")
//         enumTest = enumBnw
//     }
// 
//     @AfterAll
//     func aa(): Unit {
//         let _ = enumTest
//     }
// 
//     // @Bench
//     // func inlinedComposition(): Unit {
//     //     let bnw = lensInlinedComposition.update(bow, "New")
//     //     test = bnw
//     // }
// 
//     // @Bench
//     // func reducedComposition(): Unit {
//     //     let bnw = lensReduced.update(bow, "New")
//     //     test = bnw
//     // }
// 
//     // @Bench
//     // func inlinedReducedComposition(): Unit {
//     //     let bnw = A(B(bow.x.x, "New"), bow.y)
//     //     test = bnw
//     // }
// 
//     // @AfterAll
//     // func aa(): Unit {
//     //     println(enumTest)
//     // }
// }