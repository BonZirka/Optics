package optics_experiments.bench.examples

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

import lucida.*
import lucida.macrodsl.*

public enum Wire {
    | Text(String)
    | Num(Int64)
    | Rec(ArrayList<(String, Wire)>)
    | Seq(ArrayList<Wire>)
}

public func wireText(s: String): Wire { Wire.Text(s) }
public func wireNum(n: Int64): Wire { Wire.Num(n) }
public func wireRec(): Wire {
    Wire.Rec(ArrayList<(String, Wire)>())
}

public func wireAdd(w: Wire, name: String, value: Wire): Wire {
    match (w) {
        case Wire.Rec(fields) => fields.add((name, value))
        case _ => throw Exception("wireAdd on a non-record")
    }
    w
}

public func wireGet(w: Wire, name: String): Wire {
    match (w) {
        case Wire.Rec(fields) =>
            for ((k, v) in fields) {
                if (k == name) {
                    return v
                }
            }
            throw Exception("no field '${name}'")
        case _ => throw Exception("wireGet on a non-record")
    }
}

public func wireTextOf(w: Wire): String {
    match (w) {
        case Wire.Text(s) => s
        case _ => throw Exception("not text")
    }
}

public func wireNumOf(w: Wire): Int64 {
    match (w) {
        case Wire.Num(n) => n
        case _ => throw Exception("not a number")
    }
}

public func wireItemsOf(w: Wire): ArrayList<Wire> {
    match (w) {
        case Wire.Seq(items) => items
        case _ => throw Exception("not a seq")
    }
}

public func wireSeq(items: ArrayList<Wire>): Wire { Wire.Seq(items) }

public interface Codec<T> {
    func encode(): Wire
    static func decode(w: Wire): T
}

extend String <: Codec<String> {
    public func encode(): Wire { Wire.Text(this) }
    public static func decode(w: Wire): String { wireTextOf(w) }
}

extend Int64 <: Codec<Int64> {
    public func encode(): Wire { Wire.Num(this) }
    public static func decode(w: Wire): Int64 { wireNumOf(w) }
}

extend<T> Array<T> <: Codec<Array<T>> where T <: Codec<T> {
    public func encode(): Wire {
        var items = ArrayList<Wire>()
        for (x in this) {
            items.add(x.encode())
        }
        Wire.Seq(items)
    }
    public static func decode(w: Wire): Array<T> {
        let items = wireItemsOf(w)
        let out = ArrayList<T>(items.size, { i: Int64 => T.decode(items[i]) })
        out.toArray()
    }
}

extend RegistryMagical<Wire> {
    public func __downcast_method_serialization<T>(_: RegistryMagical<Wire>): RegistryPrisms<Wire> {
        RegistryPrisms()
    }
    public func __method_serialization_optics<T>(_: RegistryMagical<Wire>): RegistryMagical<T> {
        RegistryMagical()
    }
}

extend RegistryPrisms<Wire> {
    public func __method_serialization_impl_forward<T>(_: RegistryMagical<Wire>): (Wire) -> Option<T> where T <: Codec<T> { { source: Wire => Some(T.decode(source)) } }
    public func __method_serialization_impl_backward<T>(_: RegistryMagical<Wire>): (T) -> Wire where T <: Codec<T> { { focus: T => focus.encode() } }
}

@DeriveOptics
public struct Info <: Codec<Info> {
    public Info(
        let capitalization: Int64,
        let address: Address
    ) { }

    public func encode(): Wire {
        wireAdd(
            wireAdd(wireRec(), "capitalization", capitalization.encode()),
            "address",
            address.encode()
        )
    }

    public static func decode(w: Wire): Info {
        Info(
            Int64.decode(wireGet(w, "capitalization")),
            Address.decode(wireGet(w, "address"))
        )
    }
}

@DeriveOptics
public struct Address <: Codec<Address> {
    public Address(
        let country: String,
        let city: String
    ) { }

    public func encode(): Wire {
        wireAdd(
            wireAdd(wireRec(), "country", country.encode()),
            "city",
            city.encode()
        )
    }

    public static func decode(w: Wire): Address {
        Address(
            String.decode(wireGet(w, "country")),
            String.decode(wireGet(w, "city"))
        )
    }
}

@DeriveOptics
public struct Employee <: Codec<Employee> {
    public Employee(
        let name: String,
        let salary: Int64
    ) { }

    public func encode(): Wire {
        wireAdd(
            wireAdd(wireRec(), "name", name.encode()),
            "salary",
            salary.encode()
        )
    }

    public static func decode(w: Wire): Employee {
        Employee(
            String.decode(wireGet(w, "name")),
            Int64.decode(wireGet(w, "salary"))
        )
    }
}

@DeriveOptics
public struct Department <: Codec<Department> {
    public Department(
        let name: String,
        let employees: Array<Employee>,
        let information: Info
    ) { }

    public func encode(): Wire {
        wireAdd(
            wireAdd(
                wireAdd(wireRec(), "name", name.encode()),
                "employees",
                employees.encode()
            ),
            "information",
            information.encode()
        )
    }

    public static func decode(w: Wire): Department {
        Department(
            String.decode(wireGet(w, "name")),
            Array<Employee>.decode(wireGet(w, "employees")),
            Info.decode(wireGet(w, "information"))
        )
    }
}

let department = { =>
    let res = ArrayList<Employee>()
    for (i in 0..10) {
        res.add(Employee(
            "Jonh Lennon ${i}",
            i
        ))
    }
    res.add(Employee(
        "Mark",
        10000
    ))
    return Department(
        "Shits & Giggles. Inc",
        res.toArray(),
        Info(1000000, Address("USA", "Atlanta"))
    )
}()

let encoded = department.encode()

var test2: Option<Wire> = None

@Test
@Configure[baseline: "baseline"]
class BenchBumpEncoded {

    @Bench
    func baseline(): Unit {
        let decoded = Department.decode(encoded)
        let _ = Department(
            decoded.name,
            decoded.employees,
            Info(
                decoded.information.capitalization,
                Address(
                    decoded.information.address.country,
                    "Melbourne"
                )
            )
        ).encode()
    }

    @Bench
    func opticsBaseline(): Unit {
        test2 = @f[unfuse](encoded.serialization<Department>()
            .information.address.city <- "Melbourne")
    }

    @AfterAll
    func aa(): Unit {
        let _ = test2
    }
}
