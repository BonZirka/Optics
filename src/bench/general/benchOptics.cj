package optics_experiments.bench.general

import optics_experiments.a.*
import optics_experiments.b.*

import lucida_macro.Lucida
import lucida_macro.DeriveLenses
import lucida.*

import std.deriving.*

import std.unittest.*
import std.unittest.testmacro.*

public var test: Option<A> = None;
public let bow = A(B("Brave", "Old"), "World")

// <-- LENS NO MAGIC -->
public let lensNoMagic = createLens(
    { source: A => source.x.y },
    { source: A, focus: String => 
        let x0 = identityLens(bow)
        let x1 = compose(x0, A.__lens_x)
        let x2 = compose(x1, B.__lens_y)
        x2.update(source, focus)
    }
)
// \<-- LENS NO MAGIC -->

// <-- LENS INLINED COMPOSITION -->
public let lensInlinedComposition = createLens(
    { source: A => source.x.y },
    { source: A, focus: String => 
        let v1: (A) -> B = { source: A => source.x }
        let u1: (A, B) -> A = { source: A, focus: B => A(focus, source.y) }
        let u2: (B, String) -> B = { source: B, focus: String => B(source.x, focus) }
        u1(source, u2(v1(source), focus))
    }
)
// \<-- LENS INLINED COMPOSITION -->

// <-- BEST LENS* -->
public let bestLensWithAsterisk = createLens(
    { source: A => source.x.y },
    { source: A, focus: String => A(B(source.x.x, focus), source.y) }
)
// \<-- BEST LENS* -->

struct SupportA {
    public let __lens_x_view = { source: A => source.x }
    public let __lens_x_update = { source: A, focus: B => A(focus, source.y) }
    public let __lens_y_view = { source: A => source.y }
    public let __lens_y_update = { source: A, focus: String => A(source.x, focus) }
}

struct SupportB {
    public let __lens_x_view = { source: B => source.x }
    public let __lens_x_update = { source: B, focus: String => B(focus, source.y) }
    public let __lens_y_view = { source: B => source.y }
    public let __lens_y_update = { source: B, focus: String => B(source.x, focus) }
}

public struct TestStruct<A, B> {
    public TestStruct(
        public let getter: (A) -> B,
        public let setter: (A, B) -> A
    ) {}
}

public let lensInlinedCompositionDirectAccess = TestStruct(
    { source: A => source.x.y },
    { source: A, focus: String =>
        SupportA().__lens_x_update(source, SupportB().__lens_y_update(SupportA().__lens_x_view(source), focus))    
    }                                                                                                        
)

struct SupportC {
    public static let lensInlinedCompositionLambda = { source: A, focus: String => 
        SupportA().__lens_x_update(source, SupportB().__lens_y_update(SupportA().__lens_x_view(source), focus))
    }
}

public func hoc<S, A, B>(v1: (S) -> A, u1: (S, A) -> S, u2: (A, B) -> A): (S, B) -> S {
    { source: S, focus: B => u1(source, u2(v1(source), focus)) }
}

public func lensInlinedCompositionLambda(source: A, focus: String): A { 
    SupportA().__lens_x_update(source, SupportB().__lens_y_update(SupportA().__lens_x_view(source), focus))
}

struct SupportD {
    public static let bestOpticalAsLambda = { source: A, focus: String =>
        A(B(source.x.x, focus), source.y)
    }

    public static func bestOpticalAsFunction(source: A, focus: String) { 
        A(B(source.x.x, focus), source.y)
    }
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
        let bnw = @Lucida(bow.x.y = "New")
        test = bnw
    }

    @Bench
    func withoutMagic(): Unit {
        let bnw = lensNoMagic.update(bow, "New")
        test = bnw
    }

    @Bench
    func bestOptical(): Unit {
        let bnw = bestLensWithAsterisk.update(bow, "New")
        test = bnw
    }

    @Bench
    func inlinedComposition(): Unit {
        let bnw = lensInlinedComposition.update(bow, "New")
        test = bnw
    }

    @Bench
    func inlinedCompositionDirectAccess(): Unit {
        let bnw = lensInlinedCompositionDirectAccess.setter(bow, "New")
        test = bnw
    }

    @Bench
    func inlinedCompositionLambdaIndirect(): Unit {
        let bnw = SupportC.lensInlinedCompositionLambda(bow, "New")
        test = bnw
    }

    @Bench
    func inlinedCompositionLambda(): Unit {
        let bnw = lensInlinedCompositionLambda(bow, "New")
        test = bnw
    }

    @Bench
    func highOrderComposition(): Unit {
        let bnw = hoc(SupportA().__lens_x_view, SupportA().__lens_x_update, SupportB().__lens_y_update)(bow, "New")
        test = bnw
    }

    @Bench
    func bestOpticalAsLambda(): Unit {
        let bnw = SupportD.bestOpticalAsLambda(bow, "New")
        test = bnw
    }

    @Bench
    func bestOpticalAsFunction(): Unit {
        let bnw = SupportD.bestOpticalAsFunction(bow, "New")
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