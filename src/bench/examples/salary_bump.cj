package optics_experiments.bench.examples

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

import lucida.*
import lucida_macro.*
import lucida.stdlib.*

import stdx.serialization.serialization.*

extend RegistryMagical<DataModel> {
    public func __downcast_method_serialization<T>(_: RegistryMagical<DataModel>): RegistryPrisms<DataModel> {
        RegistryPrisms()
    }
    public func __method_serialization_optics<T>(_: RegistryMagical<DataModel>): RegistryMagical<T> {
        RegistryMagical()
    }
}

extend RegistryPrisms<DataModel> {
    public func __method_serialization_impl_forward<T>(_: RegistryMagical<DataModel>): (DataModel)-> Either<DataModel, T> where T <: Serializable<T> { { source: DataModel => Right(T.deserialize(source)) } }
    public func __method_serialization_impl_backward<T>(_: RegistryMagical<DataModel>): (T) -> DataModel where T <: Serializable<T> { { focus: T => focus.serialize() } }
}

public struct Ruble {
    public Ruble(
        let value: Int64
    ) { }
}

@DeriveOptics
public struct Info <: Serializable<Info> {
    public Info(
        let capitalization: Int64,
        let address: Address
    ) { }
    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field("capitalization", capitalization))
            .add(field("address", address))
    }

    public static func deserialize(dm: DataModel): Info {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw Exception()
        }
        Info(
            Int64.deserialize(dms.get("capitalization")),
            Address.deserialize(dms.get("address"))
        )
    }
}

@DeriveOptics
public struct Address <: Serializable<Address> {
    public Address(
        let country: String,
        let city: String
    ) { }

    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field("country", country))
            .add(field("city", city))
    }

    public static func deserialize(dm: DataModel): Address {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw Exception()
        }
        Address(
            String.deserialize(dms.get("country")),
            String.deserialize(dms.get("city"))
        )
    }
}

@DeriveOptics
public struct Employee <: Serializable<Employee> {
    public Employee(
        let name: String,
        let salary: Int64
    ) { }

    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field("name", name))
            .add(field("salary", salary))
    }

    public static func deserialize(dm: DataModel): Employee {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw Exception()
        }
        Employee(
            String.deserialize(dms.get("name")),
            Int64.deserialize(dms.get("salary"))
        )
    }
}

@DeriveOptics
public struct Department <: Serializable<Department> {
    public Department(
        let name: String,
        let employees: Array<Employee>,
        let information: Info
    ) { }

    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field("name", name))
            .add(field("employees", employees))
            .add(field("information", information))
    }

    public static func deserialize(dm: DataModel): Department {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw Exception()
        }
        Department(
            String.deserialize(dms.get("name")),
            Array<Employee>.deserialize(dms.get("employees")),
            Info.deserialize(dms.get("information"))
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

let serialized = department.serialize()

var test: Option<Department> = None
var test2: Option<DataModel> = None

// @Test
// @Configure[baseline: "baseline"]
// class BenchBump {
// 
//     @Bench
//     func baseline(): Unit {
//         let updated = ArrayList<Employee>()
//         var found = false
//         for (e in department.employees) {
//             if (!found && e.name == "Mark") {
//                 updated.add(
//                     Employee(e.name, e.salary * 2)
//                 )
//                 found = true
//             } else {
//                 updated.add(e)
//             }
//         }
// 
//         let test = Department(
//             department.name,
//             updated.toArray()
//         )
//     }
// 
//     @Bench
//     func opticsBaseline(): Unit {
//         let test = @Lucida(department
//             .employees
//             .selectFirst({e => e.name == "Mark"})
//             .salary
//         , 20000)
//     }
// 
//     @AfterAll
//     func aa(): Unit {
//         let _ = test
//     }
// }


@Test
@Configure[baseline: "baseline"]
class BenchBumpSerialized {

    @Bench
    func baseline(): Unit {
        let desered = Department.deserialize(serialized)
        let test2 = Department(
            desered.name,
            desered.employees,
            Info(
                desered.information.capitalization,
                Address(
                    desered.information.address.country,
                    "Melbourne"
                )
            )
        ).serialize()
    }

    @Bench
    func opticsBaseline(): Unit {
        test2 = @Lucida(serialized.serialization<Department>()
            .information.address.city <- "Melbourne")
    }

    @AfterAll
    func aa(): Unit {
        let _ = test2
    }
}
