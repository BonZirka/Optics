# Internals: reserved names and macro plumbing

The `@f` macros expand **inside your package** — the emitted code has to
resolve every library symbol from your own `import lucida.*` /
`import lucida.macrodsl.*`. Cangjie has no mechanism to hide library members
from that surface (see the referencing matrix at the bottom), so the plumbing
is irreducibly public. What makes it safe to ignore is a namespace contract.

## The contract

- Identifiers starting with `__`, and the `Registry*` structs, are **reserved
  by lucida**. They are not API: they may change in any minor release, and
  user code must not define or call them.
- Everything else under `lucida` and `lucida.stdlib` — the five optic
  structs, `Option`, `magic`, the stdlib optics — is public API and follows
  semantic versioning.
- If a generated name ever collides with one of yours, the compiler will
  tell you: rename your member. (There is no gensym in the macro API;
  [macro hygiene, today](../architecture/macro-system.md) states exactly
  what the `__` convention covers.)

## The plumbing surface

| Symbol group | Role |
|---|---|
| `RegistryMagical<T>`, `RegistryIsos/Lenses/Prisms/Affines/Setters<T>` | phantom kinds — empty structs whose only job is selecting the right composition row and kind gate at compile time |
| `magic<T>()`, `magicFirstClass`, `magicFirstClassDowncast` | enter the registry world: mint a phantom for a type or a first-class optic |
| `__downcast`, `__<name>_optics`, `__<name>_impl_forward/backward` | per-derived-type members the `@DeriveOptics` expansion emits: the registry hop and the halves of each field/case optic |
| `__method_<name>_impl_forward/backward`, `__method_<name>_optics`, `__downcast_method_<name>` | the same, for optics declared with `@Optic` |
| `__OpticsCompositions.composeForward/composeBackward/opticsUpcast` | the generated 25-row composition table; `opticsUpcast` returns the lattice meet (the weaker kind) |
| `__fwdApplyTotal/Partial`, `__bwdApply`, `__bwdApplyTotal` | the kind gates — overload sets that turn a wrong `.`/`?.` mark into a compile error |
| `pinForward`, `pinBackward`, `pinBackwardSourceless`, `pinPrismForward1..16` | the fused-walk helpers the macro's chains emit calls to; the prism family is generated (`@GeneratePrismForward`) |
| `finalizingSetterForward/Backward`, `__FirstClassConstruction`, `__FirstClassGetters` | setter tails and the first-class construction/getter glue |
| `GenerateTupleExtendsLenses`, `GeneratePrismForward`, `GenerateCompositions` | the generation macros; applied inside the library, not meant for external use |

Per-type members are emitted into **your** package by `@DeriveOptics` /
`@Optic` — they are part of your type's surface and appear in docs and
completion. The `__` prefix is what keeps them from colliding with your own
names.

## Why hiding is impossible (verified, cjc 0.57.3 / 1.3.0-alpha)

The obvious fix — a `package lucida.internal` — does not exist in Cangjie
today. Measured on this toolchain:

| Referencing form | Works? |
|---|---|
| `lucida.internal.x` fully qualified, no import | no — subpackages are never dotted members of their parent |
| `import lucida.internal.x` / `import lucida.internal.*` | yes — the only subpackage access |
| `import lucida.*` leaking subpackage members | no |
| `public import lucida.internal.*` re-export from `lucida` | rejected: *it is not allowed to re-export a macro package in a package* |
| dotted emission from macros (`lucida.internal.__bwdApply(...)`) | no — macros expand inside your package, and expression macros cannot inject imports |

So everything the walk emits must stay visible under `import lucida.*` —
hence the documented contract instead of enforced privacy.

## Where to go next

- [First-class optics](first-class.md) — the public surface these internals
  serve, and the laws each kind promises.
- [Registry plumbing](../architecture/registry-plumbing.md) — how a chain
  walks the registries step by step.
- [The macro system](../architecture/macro-system.md) — how the emissions
  are produced.
