package optics_experiments.test

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import lucida.*
import lucida.stdlib.*
import lucida_macro.*

// ===== Fixtures: a realistic nested aggregate =====

@DeriveOptics
public struct City {
    public City(public let name: String, public let zip: Int64) { }
}

@DeriveOptics
public struct Address {
    public Address(public let city: City) { }
}

@DeriveOptics
public struct Customer {
    public Customer(public let name: String, public let address: Address) { }
}

@DeriveOptics
public struct Order {
    public Order(public let id: Int64, public let customer: Customer) { }
}

// Single-field types for coerce chains
@DeriveOptics
public struct Meters {
    public Meters(public let v: Int64) { }
}

@DeriveOptics
public struct Feet {
    public Feet(public let v: Int64) { }
}

@DeriveOptics
public struct Employee2 {
    public Employee2(public let name: String, public let salary: Int64) { }
}

func sampleOrder(): Order {
    Order(1, Customer("Ada", Address(City("Atlanta", 30301))))
}

func ordersEqualLeafwise(a: Order, b: Order): Bool {
    a.id == b.id && a.customer.name == b.customer.name
        && a.customer.address.city.name == b.customer.address.city.name
        && a.customer.address.city.zip == b.customer.address.city.zip
}

@Test
class DslLaws {
    // ===== deep chain: read =====
    @TestCase
    func deepChainForward(): Unit {
        let o = sampleOrder()
        @Assert(@Lucida(o.customer.address.city.name) == "Atlanta")
        @Assert(@Lucida(o.customer.address.city.zip) == 30301)
        @Assert(@Lucida(o.id) == 1)
    }

    // ===== deep chain: write returns updated copy; original untouched =====
    @TestCase
    func deepChainBackwardIsImmutable(): Unit {
        let o = sampleOrder()
        let updated = @Lucida(o.customer.address.city.name <- "Denver")
        @Assert(updated.customer.address.city.name == "Denver")
        // original immutable
        @Assert(o.customer.address.city.name == "Atlanta")
        // unrelated fields preserved
        @Assert(updated.id == 1)
        @Assert(updated.customer.name == "Ada")
        @Assert(updated.customer.address.city.zip == 30301)
    }

    // ===== set-after-get round trip through the deep chain =====
    @TestCase
    func deepChainRoundTrip(): Unit {
        let o = sampleOrder()
        let current = @Lucida(o.customer.address.city.zip)
        let rewritten = @Lucida(o.customer.address.city.zip <- current)
        @Assert(ordersEqualLeafwise(rewritten, o))
    }

    // ===== double set with same value is a no-op =====
    @TestCase
    func doubleSetIdempotent(): Unit {
        let o = sampleOrder()
        let once = @Lucida(o.id <- 42)
        let twice = @Lucida(once.id <- 42)
        @Assert(ordersEqualLeafwise(twice, once))
    }

    // ===== stdlib at(i): in-bounds update, out-of-bounds identity/Left =====
    @TestCase
    func stdlibAtLaws(): Unit {
        let nums = [10, 20, 30]
        let bumped = @Lucida(nums.at(1) <- 99)
        @Assert(bumped[0] == 10)
        @Assert(bumped[1] == 99)
        @Assert(bumped[2] == 30)
        @Assert(bumped.size == 3)
        // immutability: the caller's array must be untouched (CoW aliasing bug class)
        @Assert(nums[1] == 20)

        let untouched = @Lucida(nums.at(7) <- 99)
        @Assert(untouched.size == 3)
        @Assert(untouched[0] == 10 && untouched[1] == 20 && untouched[2] == 30)

        // source-form read returns Either: Right(focus) / Left(original)
        var leftOk = false
        if (let Left(src) <- @Lucida(nums.at(7))) {
            leftOk = src.size == 3
        }
        @Assert(leftOk)
        var rightOk = false
        if (let Right(fv) <- @Lucida(nums.at(0))) {
            rightOk = fv == 10
        }
        @Assert(rightOk)
    }

    // ===== stdlib selectFirst: first match only, non-match identity =====
    @TestCase
    func stdlibSelectFirstLaws(): Unit {
        let staff = ArrayList<Employee2>()
        staff.add(Employee2("dup", 100))
        staff.add(Employee2("dup", 200))
        staff.add(Employee2("other", 300))
        let arr = staff.toArray()

        let raised = @Lucida(arr.selectFirst({ e: Employee2 => e.name == "dup" }).salary <- 999)
        @Assert(raised[0].salary == 999)
        @Assert(raised[1].salary == 200)
        @Assert(raised[2].salary == 300)

        let miss = @Lucida(arr.selectFirst({ e: Employee2 => e.name == "nobody" }).salary <- 999)
        @Assert(miss.size == 3)
        @Assert(miss[0].salary == 100)
        @Assert(miss[1].salary == 200)
        @Assert(miss[2].salary == 300)
    }

    // ===== coerce unwraps a single-field derivation to its payload type =====
    // (mechanical contract: coerce<X> resolves against the derived iso
    //  Wrapper <-> FieldType, so X must be the field type)
    @TestCase
    func coerceUnwrapsPayload(): Unit {
        let m = Meters(7)
        let unwrapped = @Lucida(m.coerce<Int64>())
        @Assert(unwrapped == 7)
    }

    // ===== @TypeOf setter form constructs a reusable Setter optic =====
    @TestCase
    func typeOfSetterForm(): Unit {
        let c = City("Atlanta", 30301)
        let setter = @Lucida(@TypeOf(c).zip <- 99999)
        let rewritten = setter.modify(c, { _: Int64 => 99999 })
        @Assert(rewritten.zip == 99999)
        // source immutable
        @Assert(c.zip == 30301)
    }

    // ===== enum optic inside expressions stays law-abiding (ties to enum_derive) =====
    @TestCase
    func aggregateAndEnumMixSanity(): Unit {
        let holder = Order(3, Customer("x", Address(City("y", 1))))
        let renamed = @Lucida(holder.customer.name <- "y")
        @Assert(renamed.customer.name == "y")

        let sq = Shape.Square(5)
        let kept = @Lucida(sq?.Circle.n <- 77)
        var keptSquare = false
        match (kept) {
            case Square(v) => keptSquare = v == 5
            case _ => ()
        }
        @Assert(keptSquare)
    }
}
