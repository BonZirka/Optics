package optics_experiments.bench.big_example

import lucida.*
import lucida_macro.*

@DeriveOptics
public struct TheBigOne {
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
public struct TheMiddleOne {
    public TheMiddleOne(
        public let a: String,
        public let b: Int64,
        public let c: String,
        public let d: TheSmallOne,
        public let e: Array<String>
    ) { }
}

@DeriveOptics
public struct TheSmallOne {
    public TheSmallOne(
        public let a: String,
        public let b: String
    ) { }
}

let example = { =>
    let middle = TheMiddleOne(
        "Middle Name",
        42,
        "Middle Description",
        TheSmallOne("Inner A", "Inner B"),
        ["tag1", "tag2", "tag3"]
    )
    return TheBigOne(
        "Very Long String",
        128423,
        middle,
        [middle],
        [middle],
        [middle],
        "g1", "g2", "g3", "g4", "g5", "g6", "g7", "g8"
    )
}()
