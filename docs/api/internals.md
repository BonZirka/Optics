# API boundaries

[API index](index.md) · [Implementation notes](../README.md#work-on-the-library)

The library exposes more names to the compiler than an application needs to
use. Macro expansions are compiled in the consumer's package, so helpers
referenced by those expansions must be accessible there.

## Application interface

Use the five optic types and their members: `Lens`, `Affine`, `Iso`, `Prism`,
and `Setter`. Use `@f`, its inner macros `@ty`, `@typeof`, and `@use`,
`@DeriveOptics`, and custom declarations through `@Optic`, `@Lens`, `@Affine`,
`@Prism`, and `@Iso`.

Tuple element optics are supplied by the core library.
`Option` is the Cangjie standard type used
for partial results; Lucida does not define it. The former `Either` type has
been removed.

## Implementation names

Names starting with `__` and the `Registry*` types are reserved. They are not
stable application interfaces. The other helpers listed below also serve
macro expansion; their public visibility should not be treated as an
invitation to build application code around their signatures.

| Names | Purpose |
|---|---|
| `RegistryMagical<T>` | Carries the current source or focus type during resolution |
| `RegistryLenses`, `RegistryAffines`, `RegistryIsos`, `RegistryPrisms`, `RegistrySetters` | Select kind-specific overloads |
| `magic`, `magicFirstClass`, `magicFirstClassDowncast` | Construct type witnesses |
| `__downcast`, `__downcast_method_*` | Resolve a slot's registered kind |
| `__*_impl_forward`, `__*_impl_backward`, `__*_optics` | Generated operations and next-focus witnesses |
| `__OpticsCompositions` | Generated composition overloads |
| `__FirstClassConstruction`, `__FirstClassGetters` | Adapt function pairs and optic structs |
| `__fwdApply*`, `__bwdApply*` | Apply operations and enforce operator-kind checks |
| `pinForward`, `pinBackward`, `pinBackwardSourceless`, `pinPrismForward*` | Supply typed entry points for fused functions |
| `finalizingSetterForward`, `finalizingSetterBackward` | Construct preset replacement setters |
| `@GenerateCompositions`, `@GenerateTupleExtendsLenses`, `@GeneratePrismForward` | Generate library implementation declarations |

## Name collisions

Generated declarations and temporaries use conventional names. The current
implementation does not provide a general guarantee against every possible
collision with consumer code. Avoid defining `__` names or registry types
in packages that use Lucida.

Most emitted names use the reserved prefix. Some bindings in the composed
emitter have older names without it. A local scope reduces exposure but is
not a proof of hygienic expansion.

Custom optic interfaces encode their signature in the generated name.
Dispatch members still use the optic name. These are separate concerns:
unique interface names permit reuse across source types, while two matching
dispatch names on one source can still collide.

## Package visibility

The implementation currently keeps its generated-code helpers available
through `import lucida.*`. Moving a helper to a different package requires
checking how every consumer expansion imports and resolves it; moving the
source file alone is insufficient.

This is a constraint of the current expansion and import strategy. It does
not establish that every possible package organization or compiler version
must use the same design. See [registry dispatch](../architecture/registry-plumbing.md)
for the actual call sequence.
