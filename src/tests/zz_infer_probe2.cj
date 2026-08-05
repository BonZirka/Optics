package lucida.tests

import lucida.*

// Cross-file control: MyMaybe is declared in zz_infer_probe.cj (same package).
func myCrossFileMiss(): MyMaybe<Int64> {
    Miss
}

func myCrossFileQualified(): MyMaybe<Int64> {
    MyMaybe<Int64>.Miss
}
