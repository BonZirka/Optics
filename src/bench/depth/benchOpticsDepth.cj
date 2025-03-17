package optics_experiments.bench.depth

import std.deriving.*
import std.unittest.*
import std.unittest.testmacro.*

public var test1: Option<A1> = None;
public var test2: Option<A2> = None;

public let bow1 = A1(B1(C1(D1("Brave", "Old"), "World"), "World"), "World")
public let bow2 = A2(B2("Brave", "Old"), "World")

@Derive[ToString]
public struct A1 {
    public A1(
        public var x: B1,
        public var y: String
    ) {}
}

@Derive[ToString]
public struct B1 {
    public B1(
        public var x: C1,
        public var y: String
    ) {}
}

@Derive[ToString]
public struct C1 {
    public C1(
        public var x: D1, 
        public var y: String
    ) {}
}

@Derive[ToString]
public struct D1 {
    public D1(
        public var x: String,
        public var y: String
    ) {}
}

@Derive[ToString]
public struct A2 {
    public A2(
        public var x: B2,
        public var y: String
    ) {}
}

@Derive[ToString]
public struct B2 {
    public B2(
        public var x: String,
        public var y: String
    ) {}
}


@Test
@Configure[baseline: "short"]
class NativeBaseline {
    @Bench
    func short(): Unit {
        var bnw2_ = bow2
        bnw2_.x.y = "New"
        let bnw2 = bnw2_ 
        test2 = bnw2
    }

    @Bench
    func long(): Unit {
        var bnw1_ = bow1
        bnw1_.x.x.x.y = "New"
        let bnw1 = bnw1_ 
        test1 = bnw1
    }

    @AfterEach
    func aa(): Unit {
        println(test1)
        println(test2)
    }
}

@Test
@Configure[baseline: "short"]
class Reconstruction {
    @Bench
    func short(): Unit {
        let result = A2(B2(bow2.x.x, "New"), bow2.y)
        test2 = result
    }

    @Bench
    func long(): Unit {
        let result = A1(B1(C1(D1(bow1.x.x.x.x, "New"), bow1.x.x.y), bow1.x.y), bow1.y)
        test1 = result
    }

    @AfterEach
    func aa(): Unit {
        println(test1)
        println(test2)
    }
}