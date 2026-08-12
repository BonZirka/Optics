macro package lucida.macrodsl

import std.ast.*

// Optics registries
let registryMainId     = Token(IDENTIFIER, "RegistryMagical")
let registryIsoId      = Token(IDENTIFIER, "RegistryIsos")
let registryLensId     = Token(IDENTIFIER, "RegistryLenses")
let registryPrismId    = Token(IDENTIFIER, "RegistryPrisms")
let registryOptionalId = Token(IDENTIFIER, "RegistryAffines")
let registrySetterId   = Token(IDENTIFIER, "RegistrySetters")

// Macros
let deriveOpticsMacro = "@DeriveOptics"

let mainMacroName   = "@f"
let typeMacroName   = "@ty"
let typeOfMacroName = "@typeof"
let opticMacroName  = "@use"

// Fake Call Exprs
let typeFakeCallexprId     = Token(IDENTIFIER, "__lucida_type_fake_callexpr")
let typeOfFakeCallexprId   = Token(IDENTIFIER, "__lucida_type_of_fake_callexpr")
let opticFakeCallexprId    = Token(IDENTIFIER, "__lucida_optic_fake_callexpr")
let coercionFakeCallexprId = Token(IDENTIFIER, "coerce")

// Lib APIs
let magicCallexprId = Token(IDENTIFIER, "magic")
let evalBackwardCallexprId = Token(IDENTIFIER, "evalBackward")

let composeForwardCallexprId = quote(__OpticsCompositions.composeForward)
let composeBackwardCallexprId = quote(__OpticsCompositions.composeBackward)
let opticsUpcastCallexprId = quote(__OpticsCompositions.opticsUpcast)

let pinForwardCallexprId = Token(IDENTIFIER, "pinForward")
let pinBackwardCallexprId = Token(IDENTIFIER, "pinBackward")
let pinBackwardSourcelessCallexprId = Token(IDENTIFIER, "pinBackwardSourceless")
let bwdApplyCallexprId = Token(IDENTIFIER, "__bwdApply")
let bwdApplyTotalCallexprId = Token(IDENTIFIER, "__bwdApplyTotal")
let fwdApplyTotalCallexprId = Token(IDENTIFIER, "__fwdApplyTotal")
let fwdApplyPartialCallexprId = Token(IDENTIFIER, "__fwdApplyPartial")

func pinPrismForwardCallexprId(k: Int64): Token {
    Token(IDENTIFIER, "pinPrismForward${k}")
}

let downcastMethodCoerceId = Token(IDENTIFIER, "__downcast_method_coerce")
let coerceForwardId  = Token(IDENTIFIER, "__method_coerce_impl_forward")
let coerceBackwardId = Token(IDENTIFIER, "__method_coerce_impl_backward")

// First Class APIs

let forwardFieldId = quote(__FirstClassGetters.forward)
let backwardFieldId = quote(__FirstClassGetters.backward)
let constructFirstClassCallexprId = quote(__FirstClassConstruction.perform)

let isoStructId      = Token(IDENTIFIER, "Iso")
let lensStructId     = Token(IDENTIFIER, "Lens")
let prismStructId    = Token(IDENTIFIER, "Prism")
let optionalStructId = Token(IDENTIFIER, "Affine")
let setterStructId   = Token(IDENTIFIER, "Setter")

// Final Setter
let finalizingSetterForwardCallexpr = Token(IDENTIFIER, "finalizingSetterForward")
let finalizingSetterBackwardCallexpr = Token(IDENTIFIER, "finalizingSetterBackward")
let finalSetterForwardVarname = Token(IDENTIFIER, "finalSetterForward")
let finalSetterBackwardVarname = Token(IDENTIFIER, "finalSetterBackward")