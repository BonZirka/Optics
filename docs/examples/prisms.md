# Prisms

A lens is a total focus: the part is *always* there, so a read cannot miss.
A prism is the other bargain — a partial focus on a part that may not be
there. Ask a `Square` for its `Circle` payload and there is nothing to hand
back, so the prism answers in a type that can say so: `Either` — the
library's two-case type, `Either<L, R>` is `Left(L)` or `Right(R)` (see
[first-class optics](../api/first-class.md)) — with `Right(payload)` on a
match and `Left(source)` on a miss. The operator changes with it: `?.` marks
a partial segment where `.` marks a total one.

All the code below runs against one derived enum from the test suite,
`Shape` — a `Circle(Nested)` or a `Square(Int64)` — where `Nested` is a
one-field struct whose single field is `n`.

## Deriving a prism

```cangjie
@DeriveOptics
public enum Shape {
    | Circle(Nested)
    | Square(Int64)
}
```

One derive, one prism per case: `@DeriveOptics` emits a prism for every
single-payload case of the enum. `Circle` gets a prism focusing its `Nested`
payload, `Square` one focusing its `Int64` — and the payload type derives the
same way, which is what lets a chain keep going into `Nested`'s field `n`.
(The library kinds a case optic as an *affine* — same partial `?.` contract,
same miss-is-identity; [deriving](deriving.md) uses that name.)

A case with more than one payload cannot be rebuilt from its part alone, so
multi-payload cases are rejected at derive time. The full rules are in
[deriving](deriving.md).

## Reading with ?.

`?.` reads through a case that may not match. Pin one source of each case and
read `Circle` out of both:

```cangjie
let c = Shape.Circle(Nested(3))
let s = Shape.Square(2)
@Assert(isRightCircle(@Lucida(c?.Circle), 3))
@Assert(isLeftSquare(@Lucida(s?.Circle), 2))
```

`@Lucida(c?.Circle)` is a partial read: it evaluates to `Either<Shape,
Nested>`. `c` is a `Circle`, so the answer is `Right(payload)` — the
`Nested(3)` inside `c`. `s` is a `Square`, so the read misses and the answer
is `Left(source)` — the original `s`, carried back unchanged. The miss is a
value, not an error.

The two helpers spell out both sides:

```cangjie
func isRightCircle(e: Either<Shape, Nested>, expectedN: Int64): Bool {
    if (let Right(p) <- e) {
        return p.n == expectedN
    }
    return false
}

// Mismatched-case forward returns Left carrying the ORIGINAL source.
func isLeftSquare(e: Either<Shape, Nested>, originalSquareValue: Int64): Bool {
    if (let Left(src) <- e) {
        match (src) {
            case Square(v) => return v == originalSquareValue
            case _ => return false
        }
    }
    return false
}
```

The same read works the other way around: `s?.Square` comes back `Right(2)`,
and `c?.Square` — asking a circle for a square's payload — comes back
`Left(c)`.

## Writing — and what a miss does

```cangjie
let sq = Shape.Square(5)
let updated = @Lucida(sq?.Circle <- Nested(99))
// updated is still Square(5)
```

`sq` is a `Square`; the prism aims at `Circle`. There is no `Circle` payload
in `sq` to replace, so the write does the only honest thing: it returns the
source unchanged. No error, no branch to guard the write — the miss is an
identity, wired in by the kind. The suite checks it with a plain match:

```cangjie
var identityKept = false
match (updated) {
    case Square(v) => identityKept = v == 5
    case _ => ()
}
@Assert(identityKept)
```

That is the lesson this page exists for: a partial write is unconditional.
Write `@Lucida(src?.Case <- newValue)` without checking anything first. When
the case matches, the write rebuilds it around the new payload and you get a
new value — nothing mutates (the matching side is the next section's write).
When it misses, the same source comes back — nothing mutates either.

## Chaining through a prism

A prism composes with the lenses after it. `n` is a total segment — a lens on
the payload — so the chain marks the partial step with `?.` and continues
with `.`:

```cangjie
let c = Shape.Circle(Nested(3))
let updated = @Lucida(c?.Circle.n <- 7)
// updated is Circle(Nested(7)); a Square source would stay untouched
```

On a `Circle` the write lands: `updated` is `Circle(Nested(7))`. The same
write on a `Square` misses at `?.Circle` and returns the source untouched —
the miss rule from the last section, with a lens riding after the prism:

```cangjie
let sq = Shape.Square(4)
let untouched = @Lucida(sq?.Circle.n <- 7)
var untouchedOk = false
match (untouched) {
    case Square(v) => untouchedOk = v == 4
    case _ => ()
}
@Assert(untouchedOk)
```

One expression, two outcomes, decided by the source alone: a rebuilt `Circle`
or the untouched `Square` — and either way, nothing mutates.

## Gotchas

> **Gotcha:** `.Circle` (no `?.`) on a prism is a compile error — a total read
> of a partial optic is impossible. Use `?.` on partial segments.

## Where to go next

- [Introduction to optics](../introduction-to-optics.md) — where the prism
  sits among lenses, affines, isos and setters, and *a miss is an identity*
  from the ideas side.
- [The DSL reference](../api/dsl.md) — every `@Lucida` form on one page.
- [Deriving](deriving.md) — what `@DeriveOptics` generates for each type.
- Next example: [chains](chains.md) — mixing `.` and `?.` in one chain.
