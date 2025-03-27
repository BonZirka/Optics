package optics_experiments 

// import lucida.*
// import std.deriving.*
// 
// @Derive[ToString]
// public enum EnumList<T> {
//     | Nil
//     | Cons(T, EnumList<T>)
// }
// 
// @Derive[ToString]
// public struct A {
//     public A(
//         public var x: EnumList<String>,
//         public var y: String
//     ) { }
// }
// 
// sealed interface __A_optics_impl {
//     // view
//     func __x_impl_forward(source: A): EnumList<String>
//     // update
//     func __x_impl_backward(source: A, focus: EnumList<String>): A
//     // view
//     func __y_impl_forward(source: A): String
//     // update
//     func __y_impl_backward(source: A, focus: String): A
// }
// extend Lenses<A> <: __A_optics_impl {
//     // view
//     public func __x_impl_forward(source: A): EnumList<String> {
//         source.x
//     }
//     // update
//     public func __x_impl_backward(source: A, focus: EnumList<String>): A {
//         A(focus, source.y)
//     }
//     // view
//     public func __y_impl_forward(source: A): String {
//         source.y
//     }
//     // update
//     public func __y_impl_backward(source: A, focus: String): A {
//         A(source.x, focus)
//     }
// }
// 
// 
// sealed interface __A_suboptics_accessors {
//     func __x_optics(_: Magical<A>): Magical<EnumList<String>>
//     func __y_optics(_: Magical<A>): Magical<String>
// }
// extend Magical<A> <: __A_suboptics_accessors {
//     public func __x_optics(_: Magical<A>): Magical<EnumList<String>> { Magical() }
//     public func __y_optics(_: Magical<A>): Magical<String> { Magical() }
// }
// 
// sealed interface __A_downcast {
//     func __downcast(_: Magical<A>): Lenses<A>
// }
// extend Magical<A> <: __A_downcast {
//     public func __downcast(_: Magical<A>): Lenses<A> { Lenses() }
// }
// 
// 
// sealed interface __EnumList_T_optics_impl<T> {
//     func __nil_impl_forward(source: EnumList<T>): Either<EnumList<T>, Unit>
//     func __nil_impl_backward(from: Unit): EnumList<T>
//     func __cons_impl_forward(source: EnumList<T>): Either<EnumList<T>, (T, EnumList<T>)>
//     func __cons_impl_backward(from: (T, EnumList<T>)): EnumList<T>
// }
// 
// extend <T> Prisms<EnumList<T>> <: __EnumList_T_optics_impl<T> {
//     public func __nil_impl_forward(source: EnumList<T>): Either<EnumList<T>, Unit> {
//         if (let Nil <- source) { Right<EnumList<T>, Unit>(()) } else { Left<EnumList<T>, Unit>(source) }
//     }
//     public func __nil_impl_backward(_: Unit): EnumList<T> {
//         EnumList<T>.Nil
//     }
//     public func __cons_impl_forward(source: EnumList<T>): Either<EnumList<T>, (T, EnumList<T>)> {
//         if (let Cons(v, n) <- source) { Right<EnumList<T>, (T, EnumList<T>)>((v, n)) } else { Left<EnumList<T>, (T, EnumList<T>)>(source) }
//     }
//     public func __cons_impl_backward(froom: (T, EnumList<T>)): EnumList<T> {
//         let (v, n) = froom
//         EnumList<T>.Cons(v, n)
//     }
// }
// 
// // ONLY IF SUCCESS....
// sealed interface __EnumList_T_suboptics_accessors<T> {
//     func __nil_optics(_: Magical<EnumList<T>>): Magical<Unit>
//     func __cons_optics(_: Magical<EnumList<T>>): Magical<(T, EnumList<T>)>
// }
// extend <T> Magical<EnumList<T>> <: __EnumList_T_suboptics_accessors<T> {
//     public func __nil_optics(_: Magical<EnumList<T>>): Magical<Unit> { Magical() }
//     public func __cons_optics(_: Magical<EnumList<T>>): Magical<(T, EnumList<T>)> { Magical() }
// }
// 
// sealed interface __EnumList_T_downcast<T> {
//     func __downcast(_: Magical<EnumList<T>>): Prisms<EnumList<T>>
// }
// extend <T> Magical<EnumList<T>> <: __EnumList_T_downcast<T> {
//     public func __downcast(_: Magical<EnumList<T>>): Prisms<EnumList<T>> {
//         Prisms()
//     }
// }
// 
// // sealed interface __Tuple2_T_G_optics_impl<T, G> {
// //     func __fst_impl_forward(source: (T, G)): T
// //     func __fst_impl_backward(source: (T, G), focus: T): (T, G)
// //     func __snd_impl_forward(source: (T, G)): G
// //     func __snd_impl_backward(source: (T, G), focus: G): (T, G)
// // }
// extend <T, G> Lenses<(T, G)> /* <: __Tuple2_T_G_optics_impl<T, G> */ {
//     public func __fst_impl_forward(source: (T, G)): T { let (t, _) = source; t }
//     public func __fst_impl_backward(source: (T, G), focus: T): (T, G) { let (_, g) = source; (focus, g) }
//     public func __snd_impl_forward(source: (T, G)): G { let (_, g) = source; g }
//     public func __snd_impl_backward(source: (T, G), focus: G): (T, G) { let (t, _) = source; (t, focus) }
// }
// 
// // sealed interface __Tuple2_T_G_suboptics_accessors<T, G> {
// //     func __fst_optics(_: Magical<(T, G)>): Magical<T>
// //     func __snd_optics(_: Magical<(T, G)>): Magical<G>
// // }
// extend <T, G> Magical<(T, G)> /* <: __Tuple2_T_G_suboptics_accessors<T, G> */ {
//     public func __fst_optics(_: Magical<(T, G)>): Magical<T> { Magical() }
//     public func __snd_optics(_: Magical<(T, G)>): Magical<G> { Magical() }
// }
// 
// // sealed interface __Tuple2_T_G_downcast<T, G> {
// //     func __downcast(_: Magical<(T, G)>): Lenses<(T, G)>
// // }
// extend <T, G> Magical<(T, G)> /* <: __Tuple2_T_G_downcast<T, G> */ {
//     public func __downcast(_: Magical<(T, G)>): Lenses<(T, G)> { Lenses() }
// }
// 
// main() {
//     // let bow = A(B("Brave", "Old"), "World")
//     // let bnw = @Lucida(bow.x.y = "New")
//     // let bnwxyLens = @Lucida(bnw.x.y)
//     // let bnstw = bnwxyLens(bnw, "Newest")
// 
//     let bow = A(Cons("Brave", Cons("Old", Nil)), "World") 
//     // let bnw = @Lucida(bow.x &> @Type(EnumList<String>).Cons &> nth(2) &> @Type(EnumList<String>).Cons &> nth(1) = "New")
//     // Strictly speacking, nth(Int64) is Optionals<T>, but I'm working with pairs now, so it will be Lenses<T>
//     let bnw = { =>
//         let magic0 = magic(bow)
//         let optics0 = magic0.__downcast(magic0)
//         let optics0ImplForward = optics0.__x_impl_forward // Getter A.x
//         let optics0ImplBackward = optics0.__x_impl_backward // Setter A.x
// 
//         let magic1 = magic0.__x_optics(magic0)  // Magical<EnumList<String>>
//         let optics1 = magic1.__downcast(magic1) // Prism<EnumList<String>>
//         let optics1ImplForward = optics1.__cons_impl_forward // Match Cons
//         let optics1ImplBackward = optics1.__cons_impl_backward // Build Cons
// 
//         let magic2 = magic1.__cons_optics(magic1) // Magical<(String, EnumList<String>)>
//         let expect1 = whatExpect(optics0, optics1, magic2)
//         let composedForward1 = composeForward(optics0, optics1, magic2)(optics0ImplForward, optics1ImplForward, optics0ImplBackward, optics1ImplBackward)
//         let composedBackward1 = composeBackward(optics0, optics1, magic2)(optics0ImplForward, optics1ImplForward, optics0ImplBackward, optics1ImplBackward)
// 
//         let optics2 = magic2.__downcast(magic2) // Lenses<(String, EnumList<String>)>
//         let optics2ImplForward = optics2.__snd_impl_forward // Get 2nd argument
//         let optics2ImplBackward = optics2.__snd_impl_backward // Rebuild pair via replacing 2nd
// 
//         let magic3 = magic2.__snd_optics(magic2) // Magical<EnumList<String>>
//         let expect2 = whatExpect(expect1, optics2, magic3) // Optionals<A>
//         let composedForward2 = composeForward(expect1, optics2, magic3)(composedForward1, optics2ImplForward, composedBackward1, optics2ImplBackward)
//         let composedBackward2 = composeBackward(expect1, optics2, magic3)(composedForward1, optics2ImplForward, composedBackward1, optics2ImplBackward)
// 
//         let optics3 = magic3.__downcast(magic3) // Prisms<EnumList<String>>
//         let optics3ImplForward = optics3.__cons_impl_forward // Match Cons
//         let optics3ImplBackward = optics3.__cons_impl_backward // Build Cons
// 
//         let magic4 = magic3.__cons_optics(magic3) // Magical<(String, EnumList<String>)>
//         let expect3 = whatExpect(expect2, optics3, magic4) // Optionals<A>
//         let composedForward3 = composeForward(expect2, optics3, magic4)(composedForward2, optics3ImplForward, composedBackward2, optics3ImplBackward)
//         let composedBackward3 = composeBackward(expect2, optics3, magic4)(composedForward2, optics3ImplForward, composedBackward2, optics3ImplBackward)
// 
//         let optics4 = magic4.__downcast(magic4) // Lenses<(String, EnumList<String>)>
//         let optics4ImplForward = optics4.__fst_impl_forward // Get first argument
//         let optics4ImplBackward = optics4.__fst_impl_backward // Rebuild pair via replacing 1st
// 
//         let magic5 = magic4.__fst_optics(magic4) // Magical<String>
//         let expect4 = whatExpect(expect3, optics4, magic5) // Optionals<A>
//         let composedForward4 = composeForward(expect3, optics4, magic5)(composedForward3, optics4ImplForward, composedBackward3, optics4ImplBackward)
//         let composedBackward4 = composeBackward(expect3, optics4, magic5)(composedForward3, optics4ImplForward, composedBackward3, optics4ImplBackward)
//         composedBackward4(bow, "New")
//     }()
//     println("Old value: ")
//     println(bow)
//     println("New value: ")
//     println(bnw)
//     // println("Newest value: ")
//     // println(bnstw)
// }
// 

// interface ExAny {
//     static func check<T>(e: Exception): Bool where T <: ExAny {
//         e is T
//     }
// }
// 
// extend Exception <: ExAny {
// }
// 
// interface ConsExcept<E, Tail> <: ExAny where Tail <: ExAny, E <: Exception {
//     static func check<T>(e: Exception): Bool where T <: ExAny {
//         e is E || Tail.check<Tail>(e)
//     }
// }
// 
// main(): Unit {
//     println(ConsExcept<OverflowException, ConsExcept<IndexOutOfBoundsException, SpawnException>>.check(SpawnException()))
// }

// struct Magical<T> { }
// public struct Phantom<T> { }
// 
// interface HList { 
//     static func nth<T>(n: UInt64): Option<Magical<T>>
// }
// 
// extend <X0, X1> Magical<(X0, X1)> {
//     public func __downcast(_: Magical<(X0, X1)>): Optionals<ConsHList<X0, NilHList<X1>>> { Optionals }
// }
// 
// extend <A, Tail> Optionals<ConsHList<A, Tail>> where Tail <: HList, A <: Object {
//     @Frozen
//     public func __nth_optics<T>(_: Magical<ConsHList<A, Tail>>, n: UInt64): Magical<T> {
//         ConsHList.nth<T>(n) ?? throw Exception("Illegal __nth_optics")
//     }
// 
//     @Frozen
//     func __x_impl_forward(source: B): String
//     // update
//     @Frozen
//     func __x_impl_backward(source: B, focus: String): B
// }
// 
// interface NilHList<A> <: HList where A <: Object {
//     static func nth<T>(n: UInt64): Option<Magical<T>> {
//         func finalize<T>(): Option<Magical<T>> {
//             if (Magical<T>() is Magical<A>) { Magical() } else { None }
//         }
//         if (n == 1) { finalize<T>() } else { None }
//     }
// }
// 
// interface ConsHList<A, Tail> <: HList where Tail <: HList, A <: Object {
//     static func nth<T>(n: UInt64): Option<Magical<T>> {
//         func finalize<T>(): Option<Magical<T>> {
//             if (Magical<T>() is Magical<A>) { Magical() } else { None }
//         }
//         if (n == 1) { finalize<T>() } else { Tail.nth<T>(n - 1) }
//     }
// }
// 
// main(): Unit {
//     println(ConsHList<OverflowException, NilHList<SpawnException>>.nth<OverflowException>(1).isSome())
// }

// struct Phantom<T> { }
// 
// sealed interface HList {}
// struct NilHList <: HList { }
// struct ConsHList<A, Tail> <: HList where Tail <: HList { }
// 
// sealed interface Num<N> {}
// struct Zero <: Num<Zero> {}
// struct Succ<N> <: Num<Succ<N>> where N <: Num<N> {}
// 
// struct Get<N, Tail> where Tail <: HList {}
// extend <A, Tail> Get<Zero, ConsHList<A, Tail>> where Tail <: HList {
//     public func getType(_: Phantom<Zero>): Phantom<A> {
//         Phantom()
//     }
// }
// 
// extend <N, A, Tail> Get<Succ<N>, ConsHList<A, Tail>> where Tail <: HList, N <: Num {
//     public func getType(_: Phantom<Succ<N>>): Get<N, Tail> { Get() } 
// }
// 
// func getType<T, N>(n: Num<N>, hlist: HList): Phantom<T> {
//     func getter<N, Tail>(n: N, hlist: Tail): Get<N, Tail> where N <: Num<N>, Tail <: HList {
//         Get<N, Tail>()
//     }
//     func getHelper<T, N, Tail>(g: Get<N, Tail>): Phantom<T> where N <: Num<N>, Tail <: HList {
//         let typeval = g.getType(Phantom<N>())
//         if (typeval is Phantom<T>) { typeval } else {
//             getHelper(typeval)
//         }
//     }
// 
//     getHelper(getter(n, hlist))
// }
// 
// 
// main() {
//     let hlist = ConsHList<String, ConsHList<Int64, ConsHList<Unit, NilHList>>>()
//     let n = Succ<Zero>()
//     let getVal = getType<Int64>(n, hlist)
//     println(getVal)
// }

// 
// public interface Num<N> {
//     // required constructor would be amazing
//     static func initialize(_: Phantom<N>): Num<N>
//     static func toUInt64(_: Phantom<N>): UInt64
// }
// 
// struct Zero <: Num<Zero> {
//     public static func initialize(_: Phantom<Zero>): Num<Zero> { Zero() }
//     public static func toUInt64(_: Phantom<Zero>): UInt64 { 0 }
// }
// struct Succ<N> <: Num<Succ<N>> where N <: Num<N> {
//     public static func initialize(_: Phantom<Succ<N>>): Num<Succ<N>> { Succ<N>() }
//     public static func toUInt64(_: Phantom<Succ<N>>): UInt64 {
//         1 + N.toUInt64(Phantom<N>())
//     }
// }
// 
// struct Pred<N> where N <: Num<N> { }
// extend <N> Pred<Succ<N>> <: Num<N> where N <: Num<N> {
//     public static func initialize(_: Phantom<N>): Num<N> { N.initialize(Phantom<N>()) }
//     public static func toUInt64(_: Phantom<N>): UInt64 {
//         N.toUInt64(Phantom<N>())
//     }
// }
// extend Pred<Zero> <: Num<Zero> {
//     public static func initialize(_: Phantom<Zero>): Num<Zero> { Zero() }
//     public static func toUInt64(_: Phantom<Zero>): UInt64 { 0 }
// }
// 
// public func eval<T, N>(_: T): N where T <: Num<N>, N <: Num<N> {
//     N.initialize(Phantom<N>())
// }
// 
// main(): Unit {
//     let obj = Pred<Succ<Zero>>()
//     println(Succ<Pred<Succ<Zero>>>.toUInt64(Phantom<Succ<Zero>>()))
// }
// 