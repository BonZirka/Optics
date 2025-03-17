package optics_experiments.test

import std.unittest.testmacro.*
import std.unittest.*

import lucida_macro.Lucida
import lucida_macro.DeriveLenses
import lucida.*

struct Muta {
    public Muta(
        var value: Int
    ) {}

    mut prop change: Int {
        get() {
            value
        }
        set(newval) {
            value = newval * 10
        }
    }
}

struct MutaMuta {
    public MutaMuta(
        var muta: Muta,
        var value: Int
    ) {}

    mut prop change: Int {
        get() {
            value
        }
        set(newval) {
            value = newval * 10
        }
    }
}

struct MutaMutaMuta {
    public MutaMutaMuta(
        var muta: MutaMuta,
        var value: Int
    ) {}

    mut prop change: Int {
        get() {
            value
        }
        set(newval) {
            value = newval * 10
        }
    }
}

@Test
func propertyCOWTest() {
    let muta = Muta(3)
    let muta1 = MutaMuta(muta, 2)
    let muta2 = MutaMutaMuta(muta1, 1)
    var test = muta
    test.change = 50
    let __test = test
    @Assert[allPassed]([
        (muta.value, 3),
        (muta1.muta.value, 3),
        (muta2.muta.muta.value, 3),
        (__test.value, 500)
    ])
    var test1 = muta1
    test1.muta.change = 30
    let __test1 = test1
    @Assert[allPassed]([
        (muta.value, 3),
        (muta1.muta.value, 3),
        (muta2.muta.muta.value, 3),
        (__test.value, 500),
        (__test1.value, 2),
        (__test1.muta.value, 300)
    ])
}

@Test
func simpleMutableMutaMutaMuta() {
    let a = Muta(3)
    let a1 = MutaMuta(a, 2)
    let a2 = MutaMutaMuta(a1, 1)
    var b = a
    b.value = 0
    let __b = b
    @Assert[allPassed]([
        (a.value, 3),
        (a1.muta.value, 3),
        (a1.value, 2),
        (a2.muta.muta.value, 3),
        (a2.muta.value, 2),
        (a2.value, 1),
        (__b.value, 0)
    ])
    var b1 = a1
    b1.muta.value = 8888
    let __b1 = b1
    @Assert[allPassed]([
        (a.value, 3),
        (a1.muta.value, 3),
        (a1.value, 2),
        (a2.muta.muta.value, 3),
        (a2.muta.value, 2),
        (a2.value, 1),
        (__b.value, 0),
        (__b1.value, 2),
        (__b1.muta.value, 8888)
    ])
    var b2 = a2
    b2.muta.value = 65535
    b2.value = -2134
    b2.muta.muta.value = 3000
    let __b2 = b2
    @Assert[allPassed]([
        (a.value, 3),
        (a1.muta.value, 3),
        (a1.value, 2),
        (a2.muta.muta.value, 3),
        (a2.muta.value, 2),
        (a2.value, 1),
        (__b.value, 0),
        (__b1.value, 2),
        (__b1.muta.value, 8888),
        (__b2.value, -2134),
        (__b2.muta.value, 65535),
        (__b2.muta.muta.value, 3000)
    ])
}