# Optics (lucida v2)

Law-abiding optics for [Cangjie](https://cangjie-lang.cn): lenses, prisms,
affines, isos and setters with a `@Lucida` update DSL, a `@DeriveOptics` code
generator, and a generated composition table.

```cangjie
let updated = @Lucida(department.employees?.selectFirst(e => e.name == "Mark").salary, 42000)
```

Updates are **immutable** (they return a new value) and **law-abiding**: an
optic that does not focus never writes — a set through a non-matching prism
or affine returns the source unchanged.

## Repository layout

```
libs/optics/v2/         lucida        — optics core + composition table + stdlib
libs/macro-optics/v2/   lucida_macro  — compiler macros (@Lucida, @DeriveOptics, ...)
libs/macro-test-utils/                — macro authoring helpers
src/                    optics_experiments — benches + the law test suite
scripts/check.sh        verification gate (build + tests)
docs/superpowers/       design specs & implementation plans
```

## Toolchain

Requires the Cangjie SDK (developed against `1.2.0-alpha`) plus stdx.

```bash
source ~/cangjie-sdk/cangjie/envsetup.sh
export CANGJIE_STDX_PATH=/absolute/path/to/linux_x86_64_cjnative/dynamic/stdx
./scripts/check.sh     # cjpm build -i && cjpm test; non-zero exit on failure
```

Gotchas learned the hard way:

- `CANGJIE_STDX_PATH` must be an **absolute path** (`~` is not expanded) and
  must point *into* the `stdx` directory — cjpm's scan of `path-option`
  entries is not recursive.
- Running `bin/main` needs `LD_LIBRARY_PATH=target/release/lucida` so the
  macro plugin / runtime libraries resolve.
- Macro packages compile to plugins under `target/release/lucida_macro`;
  after editing any `lucida_macro` source, rebuild before expecting new
  expansions elsewhere.

## @DeriveOptics

Annotates a `struct`, `class` or `enum` with a primary constructor and emits
the registry plumbing that powers the `@Lucida` DSL.

- **struct / class** — every `let`/`var` constructor field becomes a lens:
  `__<field>_impl_forward/backward`, a sub-optic accessor, and
  `RegistryMagical<T>.__downcast → RegistryLenses<T>`. A single-field type
  additionally derives isos, which is what makes `.coerce<Type>()` work in
  chains.
- **generics** are propagated: `@DeriveOptics struct GBox<T>` emits
  `extend <T> RegistryLenses<GBox<T>>` etc. Generic constraints
  (`where` clauses) are rejected with a diagnostic for now.
- **enum** — each single-payload case `| Case(P)` derives an affine-style
  optic: forward matches the case (`Right(payload)`) or returns
  `Left(source)`; backward rebuilds only when the source matches, so sets on
  non-matching cases are identities. Multi-payload and payloadless cases are
  diagnosed, not silently skipped.

Derived members follow the `__`-prefixed naming scheme and are not part of
the public API surface.

## The @Lucida DSL

```
@Lucida(<chain>)                 // read: evaluates the focused value
@Lucida(<chain>, <newValue>)     // write: returns an updated copy
```

A chain is a member path whose segments resolve, in order, to:

- derived fields/cases — `order.customer.address.city`,
  `shape.Circle.radius`
- stdlib optics — `Array.at(i)`, `Array.selectFirst(pred)`
- `@Type(T).<optic>` — start from a type instead of a value
- `@TypeOf(expr).<optic>` — same, inferring from an expression
- `@Optic(firstClassOptic)` — splice a hand-built optic into a chain
- `expr.coerce<T>()` — iso-based type coercion between single-field
  derivations
- user method optics declared via `@LucidaOptic` — two body blocks, one kind:

  ```cangjie
  @LucidaOptic[
      source: Array<T>
      focus: T
      kind: Affine            // Lens | Prism | Affine | Iso
      args: (n: Int64)        // optional call-site arguments
      forward:  { if (let Some(f) <- src.get(n)) { Right(f) } else { Left(src) } }
      backward: { let a = src.clone(); a[n] = focus; a }
  ]
  struct at2<T> {}
  ```

  Fixed body slots: `src` (every forward; backward for Lens/Affine only) and
  `focus` (last backward slot), plus names from `args:`. Generated members have
  exactly the declared kind's shape (plain forward for Lens/Iso, `Either` for
  Prism/Affine; backward arity per kind), and `__downcast_method_<name>` routes
  to the kind's registry so `[unfuse]` composition stays kind-correct.

  The `.`/`?.` operator decides semantics at every call site — user and stdlib
  optics alike: `.` means a total read/write (plain result, like derived lens
  segments), `?.` means partial (`Either` result carrying the original source
  on miss, like derived prism segments). Wrong pairings fail to compile with
  bespoke messages, checked per segment (mid-chain or tail) against each
  segment's kind registry, routed through strict-`@Deprecated` diagnostic
  overloads: `.` on a partial optic ("its forward returns Either... use `?.`"),
  `?.` on a total one ("its forward cannot miss... use `.`"), and `.`-writes
  through a prism ("would rebuild the source unconditionally on miss"). Coerce
  segments are fixed-total, so `x?.coerce<T>()` is rejected at macro time.
  Write `xs?.at(1)` for `Array.at`, `m?.uJust()` for a prism-typed user optic.
  Hand-rolled `__method_<name>_impl_*` extends with arbitrary shapes should
  migrate to `@LucidaOptic` or stay on `@Lucida[unfuse]` call sites (see
  `bench/examples/salary_bump.cj` for a serialization prism kept on the
  unfused path).

  Optics over generic types work too — declare the parameters on the carrier
  struct and use them in `source:`/`focus:`:

  ```cangjie
  @LucidaOptic[source: Box<T>, focus: T, kind: Lens, forward: { src.value }, backward: { Box(focus) }]
  struct boxLens<T> {}
  ```

  Call sites stay unchanged (`@Lucida(box.boxLens())`) — inference resolves
  `T` from the receiver. Multiple parameters work the same way — declare them
  all on the carrier (`struct pairFirst<A, B> {}` over your own
  `Pair<A, B>`-style type). `where` constraints are rejected at macro time.
  Parameters must be declared on the carrier — the macro is syntactic and
  cannot distinguish a free type variable from a concrete type argument.

Rules enforced with diagnostics rather than crashes: `@Lucida()` with no
arguments, misplaced `@Type/@TypeOf`, coerce-first chains, and unknown chain
starts all produce compiler errors pointing at your code.

Semantics note: writes always reconstruct — `@Lucida(obj.field, v)` on a
`class` returns a **new** object; nothing mutates.

## First-class API and composition

Optics exist as plain values too:

```cangjie
let l = Lens<Int64, Int64>({ s => s }, { _, v => v })
let p = Prism<Int64, Int64>(...)
__FirstClassGetters.forward(l)   // (S) -> A
__FirstClassGetters.backward(l)  // (S, A) -> S
__FirstClassConstruction.perform(fwd, bwd) // build Iso/Lens/Prism/Affine/Setter from functions
```

`__OpticsCompositions` holds `composeForward`/`composeBackward` overloads for
all 25 ordered kind pairs and `opticsUpcast` for mixing kinds mid-chain.
**Both tables are generated at compile time** by `@GenerateCompositions`
(`libs/macro-optics/v2/src/generate_compositions.cj`) from an explicit
kind-pair table; upcasts follow the lattice
`Setter < Affine < {Lens, Prism} < Iso` with `join(Lens, Prism) = Affine`.

The DSL uses these implicitly: each extra chain segment inserts one upcast +
one composition step.

## Testing

The law suite lives in `src/test/` (root package, `std.unittest`):

- per-kind unit laws (round trips, non-match identity, setter modify)
- all 25 composition pairs, matched and non-matched paths
- upcast resolution regression (compile-time assertion)
- generic derivation, enum derivation, cross-file usage

Run everything through `./scripts/check.sh`. If you touch the composition
table or a compose template, this suite is the parity gate.

## Known limitations

- Enum derivation covers single-payload cases only.
- No traversal support yet; `Either<L, R>` has no combinator API.
- Macro hygiene: generated locals (`magic0`, `optics0ImplForward`, ...) can
  shadow user identifiers; `coerce` as a chain segment cannot be redefined
  by users.
- Legacy versions (`v0`, `v1*`) remain under `libs/` for reference.
