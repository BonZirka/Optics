package optics_experiments.bench.big_example

@DeriveOptics
struct TheBigOne {
    public TheBigOne(
        public let a: String,
        public let b: Int64,
        public let c: TheMiddleOne,
        public let d: Array<TheMiddleOne>,
        public let e: Array<TheMiddleOne>,
        public let f: Array<TheMiddleOne>,
        public let g1: String,
        public let g2: String,
        public let g3: String,
        public let g4: String,
        public let g5: String,
        public let g6: String,
        public let g7: String,
        public let g8: String
    ) { }
}

@DeriveOptics
struct TheMiddleOne {
    public TheMiddleOne(
        public let a: String,
        public let b: Int64,
        public let c: String,
        public let d: TheSmallOne,
        public let e: Array<String>
    ) { }
}

@DeriveOptics
struct TheSmallOne {
    public TheSmallOne(
        public let a: String,
        public let b: String
    ) { }
}

let example = { => 
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
    return TheBigOne(
        "Very Long String",
        128423,
        TheMiddleOne(

        ),
        res.toArray(),
        Info(1000000, Address("USA", "Atlanta"))
    )
}()