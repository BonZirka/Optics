package lucida

import lucida.macrodsl.*

// Tuple-lens plumbing for arities 2..16: per arity, an extend of
// RegistryLenses<(X...)> with the element impl forward/backward pair and an
// extend of RegistryMagical<(X...)> with the element accessor + __downcast.
// The DSL reaches elements as `._0` .. `._15`.
@GenerateTupleExtendsLenses(16)
