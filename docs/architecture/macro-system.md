# The macro system

Everything the `@Lucida` DSL does — the chains of the [DSL reference](../api/dsl.md),
the segments [deriving](../examples/deriving.md) and
[user-declared optics](../examples/user-optics.md) introduce — exists because
three macros emit code for it: `@DeriveOptics`, `@LucidaOptic` and `@Lucida`.
They are procedure macros: functions from tokens to tokens that run at compile
time. Cangjie hands the macro the token stream of what it annotates; the macro
parses it into its own small syntax trees, decides what the code should be,
and returns new tokens that are spliced into the file before type checking.
There is no compiler plugin, no runtime — the macro's output is ordinary code
you could have written, and everything this page shows as "emitted" is
literally text the macro produces.

The three split the work the way the user-facing tiers do:

- `@DeriveOptics` inspects a type declaration and emits the optics its fields
  and cases expose. Its output is a fixed scheme of `__`-prefixed members on
  the registry types ([deriving](../examples/deriving.md) shows the surface).
- `@LucidaOptic` takes a declaration whose body is a spec — source, focus,
  kind, two bodies — and emits the members that turn the carrier's name into
  a chain segment.
- `@Lucida` takes a chain expression and emits the walk that evaluates it:
  either a fused straight-line pass or a library composition, segment by
  segment.

Around them sit two smaller pieces of the same package: `@Type`, `@TypeOf`
and `@Optic`, which are only valid inside `@Lucida` and exist so the outer
macro can recognize anchors in the token stream; and `@GenerateCompositions`,
which fills the `__OpticsCompositions` table the composed path walks
([composition](../api/composition.md) documents it). This page covers the
macro side: what each macro parses, what it emits, and why the emissions
look the way they do. The runtime side — the registry types the emitted
members land on, and the fused walk itself — has its own pages:
[registry plumbing](registry-plumbing.md) and [the fusion walk](fusion-walk.md).

## @DeriveOptics

The derive (`derive_macro.cj`) attaches to a `struct`, `class` or `enum`
declaration and rejects
anything else. It reads the declaration — primary-constructor fields for
structs and classes, constructors for enums — and emits optics named after
each field or case.

### Three extend blocks

For a struct or class with fields `f1, f2, ...`, the derive emits three
`extend` blocks. For a type `City` with fields `name: String` and
`zip: Int64`, the first is:

```cangjie
sealed interface __City_optics_impl {
    @Frozen
    func __name_impl_forward(source: City): String
    @Frozen
    func __name_impl_backward(source: City, focus: String): City
    // ... one forward/backward pair per field
}

extend RegistryLenses<City> <: __City_optics_impl {
    public func __name_impl_forward(source: City): String {
        source.name
    }
    public func __name_impl_backward(source: City, focus: String): City {
        City(focus, source.zip)
    }
    // ...
}
```

The other two land on `RegistryMagical<City>`:

- the *suboptic accessors* — one `__name_optics` member per field, returning
  a fresh `RegistryMagical<FieldType>`. These are what let a chain continue
  past a field: the walk calls `__name_optics` to move from `City`'s registry
  to the field type's.
- the *downcast* — a single `__downcast` member returning a fresh
  `RegistryLenses<City>`. The walk holds a `RegistryMagical` (the chain's
  currency) and needs the lens members; `__downcast` is the exchange.

The sealed interfaces are not decoration. An extension member added by a bare
`extend` stays package-local in Cangjie; the language's channel for publishing
one outside its package is an interface that the extend conforms to. So the
derive emits a `sealed interface` (the public channel) and has the extend
implement it (the implementation). `sealed` keeps user code from implementing
the interface itself, and the `__` prefix keeps the channel out of the public
API surface — [deriving](../examples/deriving.md)'s gotcha that derived
members "are not part of the public API" is enforced by naming, not by
modifiers.

The interface is emitted only when at least one field is `public`, and it
declares exactly the public fields' members. A package-visible field still
gets its extend member (usable inside the package, where bare extension
members are visible anyway); it just does not appear on the interface. That
is how "visibility mirrors the field" from the examples tier falls out of the
emission: the interface carries what the world may see, the extend carries
everything.

### The `__`-prefixed scheme

Every member the derive emits is named by a fixed pattern (the shared
identifiers live in the macro's `naming.cj`; the per-field patterns are
built inline in `derive_macro.cj`):

| Pattern | Member | On |
|---|---|---|
| `__<field>_impl_forward` | the lens read | `RegistryLenses<T>` |
| `__<field>_impl_backward` | the lens rebuild | `RegistryLenses<T>` |
| `__<field>_optics` | the suboptic accessor | `RegistryMagical<T>` |
| `__downcast` | registry exchange | `RegistryMagical<T>` |
| `__<Type>_optics_impl` | sealed interface of lens signatures | top level |
| `__<Type>_suboptics_accessors` | sealed interface of accessor signatures | top level |
| `__<Type>_downcast` | sealed interface of the downcast signature | top level |

The lens rebuild is the interesting one. The straightforward emission — one
hand-written `City(focus, source.zip)`-style expression per field — is what
the derive actually produces, but it builds it without duplicating the
argument list: it materializes the full argument vector once
(`source.name, source.zip`), and for field *i* substitutes `focus` at slot
*i* in place, emits the rebuild call, then restores the slot. One pass over
the fields, linear output; a naive template per field would copy the whole
argument list into every backward.

### Single-field types: the iso pair

A struct or class with exactly one field gets the three blocks above *plus*
two extends on `RegistryIsos` — the pair `coerce<T>()` resolves against. For
a wrapper `Meters` over `Int64`, the two directions are:

```cangjie
sealed interface __from_Meters_isos_impl {
    @Frozen
    func __method_coerce_impl_forward(
        _: RegistryMagical<Meters>, _: RegistryMagical<Int64>): (Meters) -> Int64
    @Frozen
    func __method_coerce_impl_backward(
        _: RegistryMagical<Meters>, _: RegistryMagical<Int64>): (Int64) -> Meters
}

extend RegistryIsos<Meters> <: __from_Meters_isos_impl { /* Meters -> Int64 */ }

sealed interface __to_Meters_isos_impl {
    // same two signatures, argument types swapped
}

extend RegistryIsos<Int64> <: __to_Meters_isos_impl { /* Int64 -> Meters */ }
```

The forward of `__from_...` is `{ source => source.field }` — unwrap the
wrapper; the forward of `__to_...` is `{ focus => Meters(focus) }` — wrap the
payload. Both extends exist because coercion can run either way mid-chain,
and the walk's `coerce<T>()` segment (below) resolves the members
`__method_coerce_impl_forward`/`__method_coerce_impl_backward` against the
`RegistryIsos` of whichever side it is leaving. The `coerce` dispatch itself —
`__downcast_method_coerce`, a free top-level function rather than an
extension member — is runtime
plumbing ([registry plumbing](registry-plumbing.md)).

### Enums: affines per case

Every case of a derived enum emits three members — a forward returning
`Either<Enum, Focus>`, a backward rebuilding the case from a focus, and a
`__<case>_optics` accessor — plus the same interface/extend pairing as a
struct. The focus depends on the case shape: a single-payload case focuses
the payload itself, a multi-payload case focuses the *tuple* of payloads
(`Cons(head, tail)` focuses `(Head, Tail)`), and a payloadless case focuses
`Unit` — reading it doubles as a match check. The registries differ in one
deliberate way: the case
optics land on `RegistryAffines`, not `RegistryPrisms`, because a case read
is affine-kind — partial forward, *sourceful* backward whose miss is an
identity ([prisms](../examples/prisms.md) walks the contract). The emission
is worth reading in full, because the shape of the whole enum derive is
these three interfaces and three extends:

```cangjie
sealed interface __<Enum>_prisms_impl {
    @Frozen
    func __<Case>_impl_forward(source: <Enum>): Either<<Enum>, <Payload>>
    @Frozen
    func __<Case>_impl_backward(source: <Enum>, payload: <Payload>): <Enum>
}

sealed interface __<Enum>_suboptics_accessors {
    @Frozen
    func __<Case>_optics(_: RegistryMagical<<Enum>>): RegistryMagical<<Payload>>
}

sealed interface __<Enum>_downcast {
    @Frozen
    func __downcast(_: RegistryMagical<<Enum>>): RegistryAffines<<Enum>>
}

extend RegistryAffines<<Enum>> <: __<Enum>_prisms_impl {
    @Frozen
    public func __<Case>_impl_forward(source: <Enum>): Either<<Enum>, <Payload>> {
        match (source) {
            case <Case>(__payload_<Case>) => Right<<Enum>, <Payload>>(__payload_<Case>)
            case _ => Left<<Enum>, <Payload>>(source)
        }
    }
    // ...
}

extend RegistryMagical<<Enum>> <: __<Enum>_suboptics_accessors { /* ... */ }
extend RegistryMagical<<Enum>> <: __<Enum>_downcast { /* ... */ }
```

Two asymmetries with the struct path are visible here. First, `__downcast`
returns `RegistryAffines` for an enum where it returns `RegistryLenses` for a
struct — the walk re-enters the registry that holds the type's actual optics.
Second, the enum path always emits interfaces and always marks members
`public`: enum cases have no access modifiers of their own, so there is no
visibility to mirror.

Case shape is handled, not rejected: every constructor derives, whatever its
arity. A single payload binds by name; several payloads bind positionally and
travel as a tuple; zero payloads bind nothing and carry `Unit`. The
mechanical constraint the old derive hit — a `match` arm needs names to bind
— is met by binding positionally into a tuple, which also lets the chain
continue through the tuple lens plumbing.

### Generics, and what is rejected

Generic parameters thread through every emission the same way: a `genHeader`
helper renders `<T>` (or `<K, V>`) once per derived type, and the same
spelling is used both as the declaration-site header (`extend <T>
RegistryLenses<City<T>>`) and as the type-use suffix on the interface names
(`__City_optics_impl<T>`). One decision, both uses.

A `where` clause on the type is rejected outright. The constraint would have
to be re-derived and re-emitted onto every extend and interface, and the
derive cannot verify that the emitted members still satisfy it — a wrong
constraint would surface as a type error deep inside generated code, far
from the declaration that caused it. The rejection moves the failure to the
declaration, with the escape hatch in the hint: hand-write the optics.

Every emitted member — interface signatures and implementations alike —
carries `@Frozen`. The macro's own generated call sites (in `@Lucida`
expansions across other modules) address these members by exact name and
shape; `@Frozen` is the language's seal that the member cannot be redefined
or patched after compilation, so the generated code and the emitted surface
cannot drift apart.

## @LucidaOptic

A user-declared optic is spelled as a bracket of fields hung on an empty
carrier struct:

```cangjie
@LucidaOptic[source: UBox, focus: Int64, kind: Lens, forward: { src.v }, backward: { UBox(focus) }]
struct uBoxLens {}
```

The carrier-struct pattern (`user_optic_macro.cj`) exists because of what a
macro can attach to.
Cangjie macros annotate declarations or wrap expressions; there is no
attribute form that mints a bare top-level name out of nothing. So the
declaration supplies the name — the carrier *is* the optic's name — and the
macro re-emits the struct untouched, followed by the members that make the
name callable in a chain. The carrier must be empty (any member is rejected:
it would be dead weight the optic machinery never touches) and constraint-free
(`where` clauses are rejected, same reasoning as the derive).

### The emission

The fields parse into two bodies, a kind, and optional value parameters, and
the macro emits exactly two extends — one on the kind's registry carrying the
optic's halves, one on `RegistryMagical<Source>` carrying the plumbing the
walk uses:

```cangjie
extend RegistryLenses<UBox> {
    public func __method_uBoxLens_impl_forward(_: RegistryMagical<UBox>): (UBox) -> Int64 {
        { src: UBox => src.v }
    }
    public func __method_uBoxLens_impl_backward(_: RegistryMagical<UBox>): (UBox, Int64) -> UBox {
        { src: UBox, focus: Int64 => UBox(focus) }
    }
}

extend RegistryMagical<UBox> {
    public func __method_uBoxLens_optics(_: RegistryMagical<UBox>): RegistryMagical<Int64> {
        RegistryMagical<Int64>()
    }
    public func __downcast_method_uBoxLens(_: RegistryMagical<UBox>): RegistryLenses<UBox> {
        RegistryLenses<UBox>()
    }
}
```

The kind picks the registry: `Lens` → `RegistryLenses`, `Iso` →
`RegistryIsos`, `Prism` → `RegistryPrisms`, `Affine` → `RegistryAffines`.
Setters are absent on purpose — a setter is a value you mint from a write,
not a declarable optic.

The kind also picks the shape of each half, and the shapes are the whole
reason the operator marks work the way they do:

| Kind | forward type | backward type | backward slots |
|---|---|---|---|
| `Lens` | `(S) -> F` | `(S, F) -> S` | `src`, `focus` |
| `Iso` | `(S) -> F` | `(F) -> S` | `focus` alone |
| `Prism` | `(S) -> Either<S, F>` | `(F) -> S` | `focus` alone |
| `Affine` | `(S) -> Either<S, F>` | `(S, F) -> S` | `src`, `focus` |

A `.`-marked chain segment requires a total forward `(S) -> F`; a `?.`-marked
one requires `Either`. Because the *type* of the emitted forward already
encodes totality, a wrong mark fails to resolve — the compiler enforces the
call-site mark against the kind without the macro doing anything extra at the
call site (the strict-deprecated overloads that turn the failure into a
readable message belong to the fused walk — [the fusion
walk](fusion-walk.md)).

The backward column is the introduction's rebuild arrow made literal:
`Lens` and `Affine` rebuild from source plus focus (an affine's miss keeps
the source), while `Iso` and `Prism` rebuild from the focus alone. The macro
enforces the distinction at declaration time: a `Prism` or `Iso` backward
whose body mentions `src` at the top level (nested lambdas may shadow it
freely — the scan tracks brace depth) is rejected, because the emitted lambda
simply has no such slot.

### Fixed slots, reserved names

The bodies are spliced into lambdas with fixed parameter names — `src` and
`focus`, plus any names from `args:`. Those slots are therefore not the
user's to choose: an arg named `src`, `_src` or `focus` is rejected, since it
would collide with (or shadow) the slots the emission introduces. Parsing the
`args:` list reuses the compiler's own function-parameter parser on a
synthesized declaration — a small trick that buys exact Cangjie parameter
syntax (modifiers, types, defaults' grammar) without reimplementing it.

### Generic carriers

Type parameters come from the carrier's generic list, and threading them hit
a genuine API snag worth recording. The token API that returns a
declaration's generic parameters yields *bare identifiers without separator
commas* — the `<T, U>` of `struct guPairFirst<T, U> {}` arrives as the two
identifier tokens `T`, `U`. Spliced directly into an emission template, the
extend header would render `<T U>` — not Cangjie. The workaround is to
comma-join the identifiers explicitly (defensively skipping any comma or
newline tokens that do slip through); single-parameter carriers are
unaffected either way. The same API quirk appears on the parsing side of
`@Lucida` — type arguments reconstructed from a parsed call splice with
`&`-separated supertype-list semantics (`&`-lists are Cangjie's
supertype-constraint spelling, so a reconstructed argument list renders
`T & U` where `T, U` is needed), so the macro re-joins them with
commas too. The general lesson the two workarounds share: token-level APIs
return parameter lists without their separators, and every re-emission must
re-join them.

## @Lucida

The evaluation macro (`eval_macro.cj`, with the chain grammar in
`parsing.cj`) is the walk. Its entry point `parseOpticalExpression` parses
the chain into a list of
*composition nodes*, then emits code — fused or composed — that reads the
list once and produces the result.

### Parsing

The entry point distinguishes read from write by scanning the token stream
for `<-`: `@Lucida(o.x <- v)` splits at the arrow into a chain and a value.
Both halves then go through the same trick: the tokens are wrapped in a
synthesized `dummy(...)` call and handed to the expression parser, so the
macro gets real Cangjie expression trees — `MemberAccess`, `OptionalExpr`,
`CallExpr` — instead of matching tokens by hand.

The chain is decomposed outside-in. The walker starts at the whole
expression and strips one segment at a time, recording each `.`-separated
field as a derived node and each `?.` as the same node with partial kind;
calls become user-defined nodes; the fake-call anchors become their node
kinds. Two parse-time decisions happen here:

- **The anchor is implicit.** A value-rooted chain like `o.customer.name`
  has no macro call at its head, so the tail of the decomposition (which is
  the chain's *root*) is wrapped in a `TypeOf` node over the leading
  expression. The user-facing rule "the macro inserts the `@TypeOf` anchor
  for you" is this step.
- **`coerce<T>()` is fixed-total.** A `?.` in front of a coercion is rejected
  at parse time — a total optic's forward cannot miss, so there is no
  `Either` to unwrap — with the reasoning in the message itself.

The nodes are collected root-last and reversed, so the walk reads them in
chain order. The node type is the macro's whole intermediate language:

```cangjie
enum CompositionNode {
    | Derived(Token, OpticKind)        // kind set by parser: . -> Lens, ?. -> Prism
    | Type(RefExpr)                    // start anchor @Type(T)
    | TypeOf(Tokens)                   // start anchor @TypeOf(x) or auto-derived from leading identifier
    | Optic(Token)                     // start anchor @Optic(o); forces fallback
    | Coerce(TypeNode)                 // kind = Iso
    | UserDefined(Token, ArrayList<TypeNode>, ArrayList<Argument>, Bool)
    // Bool = total: operator-derived call-site expectation.
    // '.' (plain member access) => true, '?.' (OptionalExpr) => false.
}
```

Note what the parser does *not* decide: `OpticKind` here records only the
operator mark (`.` vs `?.`). The full kind — which registry a segment rides,
whether its backward is sourceful — is already fixed by the emitted members
the segment resolves to; the parser just records the promise the call site
made.

### The composed walk

The non-fused emission is a continuation-passing fold over the node list.
`composeOptics` builds, for each node, a function that takes a continuation
and returns tokens; threading the continuations composes the segments. The
continuation's payload is the same five-slot tuple throughout the walk:

```text
(currMagicalExpr, expectOptics, forward, backward, index)
```

- `currMagicalExpr` — the token expression of the current registry value,
  the chain's currency ([registry plumbing](registry-plumbing.md));
- `expectOptics` — the registry the chain has *committed to* so far, used to
  upcast when the next segment's registry is stronger;
- `forward`, `backward` — the composed halves of everything walked so far;
- `index` — the counter that keeps generated names unique.

Each node kind has an `unwrap*` helper that emits its bindings and calls the
continuation. A start anchor emits `magic<T>()` (or `magic({ => expr })` for
`@TypeOf`); a derived segment downcasts, binds its two halves, and moves the
currency through its accessor; a `Coerce` node mints the target registry and
resolves the iso members; a user-defined segment resolves its
`__method_*` members, passing the call arguments through. A spliced
`@Optic(o)` is the one node the composed path cannot fold — a first-class
value already carries its composed halves, so the walk binds them directly
and forces the chain off fusion (below).

The tail of the fold decides what the expression *is*: a read applies the
composed forward to the source; a write applies the composed backward via
`evalBackward(backward, source, target)`; the sourceless forms hand both
halves to `__FirstClassConstruction.perform`, which mints the first-class
optic or the baked `Setter`. The whole expansion is wrapped in an
immediately-invoked lambda, so the per-segment `let` bindings never leak
into the user's scope.

For `@Lucida(o.customer.name)` the composed path comes out as:

```cangjie
{ =>
    let magic0 = magic({ => o })
    let optics0 = magic0.__downcast(magic0)
    let optics0ImplForward  = optics0.__customer_impl_forward
    let optics0ImplBackward = optics0.__customer_impl_backward
    let magic1 = magic0.__customer_optics(magic0)
    let optics1 = magic1.__downcast(magic1)
    let __expect1 = __OpticsCompositions.opticsUpcast(optics0, optics1)
    let optics1ImplForward  = __OpticsCompositions.composeForward(optics0, optics1)(
        optics0ImplForward, optics1.__name_impl_forward,
        optics0ImplBackward, optics1.__name_impl_backward)
    let optics1ImplBackward = __OpticsCompositions.composeBackward(optics0, optics1)(
        optics0ImplForward, optics1.__name_impl_forward,
        optics0ImplBackward, optics1.__name_impl_backward)
    optics1ImplForward(o)
}()
```

One structural decision repays attention: the *next* segment's currency is
not the previous registry value re-derived — it is a local binding,
`magic0.__customer_optics(magic0)`, referenced by name. Splicing the full
previous expression at every step would duplicate the chain prefix once per
segment, quadratic text for a linear chain; binding once and referring by
name keeps the emission linear in chain depth. The same discipline shows up
in the derive's rebuild and in the fused path's `__t` bindings.

### Fused or composed

The fused path replaces the per-segment closure composition with one
straight-line walk: bind each segment's halves once, then apply them in
sequence, with the shape chosen by the chain's partial segments
([the fusion walk](fusion-walk.md) documents the emission). Fusion is a
code-shape decision, not a semantic one, and the gate is small:

- the chain must not splice an `@Optic` value anywhere — a first-class value
  already carries composed closures, so there is nothing to inline;
- every segment after the anchor must be derived, user-defined, or a
  coercion — the node kinds whose members the macro can address by name;
- a read with partial segments fuses through the pinned prism walkers, and
  those come in fixed arities — more than eight partial segments exceeds the
  largest helper and falls back to composition (writes are not capped).

Any failed check routes the chain to the composed path — and so does
`[unfuse]`, which skips the gate entirely. The fallback being *the* composed
path, not a degraded one, is what makes the gate safe to fail: both
emissions produce the same results, differing only in closures allocated.

Fusion also carries the operator-mark enforcement for reads. Each segment's
forward is routed through a registry-checked gate — `__fwdApplyTotal` for
`.`-marked segments, `__fwdApplyPartial` for `?.`-marked ones — whose
overload sets cover every kind registry, with the mismatched pairs declared
strict-`@Deprecated`: a `.`-mark on a partial optic resolves only to the
deprecated trap, whose message is the diagnostic
([diagnostics](../api/diagnostics.md)). Writes gate asymmetrically: a
`.`-marked write through an affine is legal (its backward is sourceful), but
a total-marked user segment's backward goes through `__bwdApplyTotal`, whose
`RegistryPrisms` overload is itself the strict-deprecated trap — so the one
illegal write, `.` through a
prism, fails to compile rather than rebuilding silently on a miss.

## Macro hygiene, today

Every identifier a macro emits is a string the macro author chose. Cangjie's
token API has no fresh-symbol facility — no gensym — so hygiene, the guarantee
that generated names cannot collide with user names, is not something the
macros can *have*. What they have instead is a naming strategy, and it is
worth stating exactly what that strategy covers and where it stops.

The member layer is fully covered. Every member the macros emit onto user
types or registries is `__`-prefixed — the derive's `__<field>_impl_forward`
scheme, the method-optic `__method_<name>_*` scheme, the interfaces, the
downcasts — and the prefix is a documented reservation
([deriving](../examples/deriving.md)'s gotcha says the derived members are
the library's, not API). The library's own runtime helpers the walk calls
(`__OpticsCompositions.*`, `__bwdApply`, `__fwdApplyTotal`) live in the same
namespace. A user who avoids `__`-prefixed identifiers cannot collide with
any emitted member. The helpers that are not members — `magic`,
`evalBackward`, the `pin*` family — are the library's own public API rather
than generated names; they sit outside the reservation, and redefining one
shadows the expansion the same way a colliding local would.

The local layer is where the strategy stops being airtight. The fused path
is disciplined — its locals are all prefixed (`__magical0`, `__optics0`,
`__fwd0`, `__bwd0`, `__nmagic0`, `__t0`, `__gfwd0`, `__fusedForward`,
`__fusedBackward`) — but the composed path's per-segment bindings are not:
`magic0`, `optics0`, `optics0ImplForward`, `optics0ImplBackward` carry no
prefix. These `let` bindings live in the same scope as the user's spliced
expressions, so a user identifier named `optics0ImplForward` — contrived,
but constructible — would be shadowed by the generated binding later in the
expansion. The pinned lambdas of the fused path name their parameters `src`
and `fcs` unprefixed too, though user code never lands inside those lambda
bodies (the source and target expressions ride in separate thunks), so the
shadowing window there is empty.

Two more names are reserved by parsing rather than emission. `coerce` is a
fixed chain segment — any `coerce<T>()` call in a chain becomes a coercion
node, so a user method optic named `coerce` cannot be called in a chain. And
`@LucidaOptic` reserves `src`, `focus` and `_src` as arg names, because they
are the slots of the generated lambdas.

The single sustainable answer is the one already in force: keep generated
names in a namespace users are told to avoid, and make the reservation
visible — the `__` prefix for members and fused-path locals, the documented
slot names for user optics, `coerce` for the chain grammar. A true hygiene
fix would need fresh-symbol support in the macro API; until the language
offers it, the convention is the mechanism, and its limit — an unprefixed
composed-path local can shadow a contrived user name — is the price of the
token-level macro model the whole system is built on.

## Where to go next

- [Registry plumbing](registry-plumbing.md) — the registry types every
  emitted member lands on: the downcast, dispatch, and the magic entry
  points.
- [The fusion walk](fusion-walk.md) — the fused emission segment by segment,
  from `pinForward` to the pinned prism walkers.
- [The DSL reference](../api/dsl.md) — the user-facing contract all of this
  machinery implements, including the fused write expansion in its
  evaluation section.
- [Composition](../api/composition.md) — the table the composed walk steps
  through, and the upcast lattice behind `opticsUpcast`.
- [Diagnostics](../api/diagnostics.md) — every rejection the three macros
  can produce, collected on one page.
- [Design decisions](design-decisions.md) — why the system is shaped the
  way it is: the registry pattern, the diagnostic overloads, and every
  macro-envelope workaround, with reasoning.
