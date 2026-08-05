package lucida.tests

// Reproduction probe: does the expected type of a lambda in return position
// propagate into match arms vs if/else branches, for a bare no-payload enum
// constructor (None)?

// (1) match, lambda in return position — the pinPrismForward shape
func matchLambda(f: (Int64) -> Option<Int64>): (Int64) -> Option<Int64> {
    { x: Int64 =>
        match (f(x)) {
            case Some(v) => Some<Int64>(v + 1)
            case None => None
        }
    }
}

// (2) if-let/else, lambda in return position — the composeForward shape
func ifLetLambda(f: (Int64) -> Option<Int64>): (Int64) -> Option<Int64> {
    { x: Int64 =>
        if (let Some(v) <- f(x)) {
            Some<Int64>(v + 1)
        } else {
            None
        }
    }
}

// (3) match, direct function body — no lambda
func matchDirect(f: (Int64) -> Option<Int64>): Option<Int64> {
    match (f(1)) {
        case Some(v) => Some<Int64>(v + 1)
        case None => None
    }
}

// (4) if-let/else, direct function body — no lambda
func ifLetDirect(f: (Int64) -> Option<Int64>): Option<Int64> {
    if (let Some(v) <- f(1)) {
        Some<Int64>(v + 1)
    } else {
        None
    }
}

// (5) generic member, single lambda — the composeForward shape minus nesting
public struct InferRepro {
    static public func genericSingleLambda<S, A, B>(
        f1: (S) -> A, f2: (A) -> Option<B>
    ): (S) -> Option<B> {
        { x: S =>
            if (let Some(v) <- f2(f1(x))) {
                Some<B>(v)
            } else {
                None
            }
        }
    }

    // (6) generic member, lambda inside lambda — the exact original shape
    static public func genericNestedLambda<S, A, B>(
        f1: (S) -> A, f2: (A) -> Option<B>
    ): ((S) -> A, (A) -> Option<B>, (A) -> S) -> (S) -> Option<B> {
        { f1b, f2b, b2 =>
            { x: S =>
                if (let Some(v) <- f2b(f1b(x))) {
                    Some<B>(v)
                } else {
                    None
                }
            }
        }
    }

    // (7) like 6 but match instead of if-let
    static public func genericNestedMatch<S, A, B>(
        f1: (S) -> A, f2: (A) -> Option<B>
    ): ((S) -> A, (A) -> Option<B>, (A) -> S) -> (S) -> Option<B> {
        { f1b, f2b, b2 =>
            { x: S =>
                match (f2b(f1b(x))) {
                    case Some(v) => Some<B>(v)
                    case None => None
                }
            }
        }
    }
}

// ===== same shapes with a USER-DEFINED generic enum =====
public enum MyMaybe<T> {
    | Just(T)
    | Miss
}

// (8) match, lambda
func myMatchLambda(f: (Int64) -> MyMaybe<Int64>): (Int64) -> MyMaybe<Int64> {
    { x: Int64 =>
        match (f(x)) {
            case Just(v) => Just<Int64>(v + 1)
            case Miss => Miss
        }
    }
}

// (9) if-let, lambda
func myIfLetLambda(f: (Int64) -> MyMaybe<Int64>): (Int64) -> MyMaybe<Int64> {
    { x: Int64 =>
        if (let Just(v) <- f(x)) {
            Just<Int64>(v + 1)
        } else {
            Miss
        }
    }
}

// (10) match, direct body
func myMatchDirect(f: (Int64) -> MyMaybe<Int64>): MyMaybe<Int64> {
    match (f(1)) {
        case Just(v) => Just<Int64>(v + 1)
        case Miss => Miss
    }
}

// (11) if-let, direct body
func myIfLetDirect(f: (Int64) -> MyMaybe<Int64>): MyMaybe<Int64> {
    if (let Just(v) <- f(1)) {
        Just<Int64>(v + 1)
    } else {
        Miss
    }
}

// (12) generic member, nested lambda, if-let — the original failing shape
public struct MyInferRepro {
    static public func genericNestedLambda<S, A, B>(
        f1: (S) -> A, f2: (A) -> MyMaybe<B>
    ): ((S) -> A, (A) -> MyMaybe<B>, (A) -> S) -> (S) -> MyMaybe<B> {
        { f1b, f2b, b2 =>
            { x: S =>
                if (let Just(v) <- f2b(f1b(x))) {
                    Just<B>(v)
                } else {
                    Miss
                }
            }
        }
    }
}
