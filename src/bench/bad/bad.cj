package optics_experiments.bench.bad

import std.deriving.*

import std.unittest.*
import std.unittest.testmacro.*

@Derive[ToString]
public struct A {
    public A(
        public var x: B,
        public var y: String
    ) { }
}

public let lensAx = Lens(
    { source: A => source.x },
    { source: A, focus: B => A(focus, source.y) }
)
public let lensAy = Lens(
    { source: A => source.y },
    { source: A, focus: String => A(source.x, focus) }
)

@Derive[ToString]
public struct B {
    public B(
        public var x: String,
        public var y: String
    ) { }
}

public let lensBx = Lens(
    { source: B => source.x },
    { source: B, focus: String => B(focus, source.y) }
)
public let lensBy = Lens(
    { source: B => source.y },
    { source: B, focus: String => B(source.x, focus) }
)

public struct Lens<S, A> {
    Lens(
        public let view: (S) -> A,
        public let update: (S, A) -> S
    ) { }
}

public let best = Lens(
    { source: A => source.x.y },
    { source: A, focus: String =>
        var tmp = source
        tmp.x.y = focus
        tmp
    }
)

public let composed = Lens(
    { source: A => source.x.y },
    { source: A, focus: String => 
        let x0 = idLens(source)
        let x1 = compose(x0, lensAx)
        let x2 = compose(x1, lensBy)
        x2.update(source, focus)
    }
)

public func compose<S, A, B>(a: Lens<S, A>, b: Lens<A, B>): Lens<S, B> {
    Lens({ source: S =>
        b.view(a.view(source))
    },
    { source: S, focus: B =>
        a.update(source, b.update(a.view(source), focus))
    })
}

public func idLens<T>(a: T): Lens<T, T> {
    Lens(
        { source: T => source },
        { _: T, focus: T => focus }
    )
}

public var test: Option<A> = None;
public let bow = A(B("Brave", "Old"), "World")

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
        let bnw = composed.update(bow, "New")
        test = bnw
    }

    @Bench
    func bestOptics(): Unit {
        let bnw = best.update(bow, "New")
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