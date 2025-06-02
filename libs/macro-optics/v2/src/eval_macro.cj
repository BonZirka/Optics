macro package lucida_macro

import std.ast.*
import std.collection.*

public macro Lucida(input: Tokens): Tokens {
    // return quote(__FirstClassGetters.forward(Iso({ x: String => () }, { _: Unit => "Hello "})))
    try {
        expansionMain { =>
            evalOptics(parseOpticalExpression(input))
        }
    } catch (e: DiagReportException) {
        // Sometimes it throws because it says, that input is from different files.
        // diagReport(
        //     DiagReportLevel.ERROR,
        //     e.tokens,
        //     e.message,
        //     e.hint
        // )
        quote($input)
    }
}

private func expansionMain(cont: () -> Tokens): Tokens {
    quote(
        { =>
            $(cont())
        }()
    )
}

private func evalOptics(expr: OpticalExpr): Tokens {
    let forwardBackwardCont = composeOptics(expr.compositionNodes)
    match (expr) {
        case OpticsBackward(source, _, target) => forwardBackwardCont { forward: Token, backward: Token =>
            quote($evalBackwardCallexprId($backward, $source, $target))
        }
        case OpticsForward(source, _) => forwardBackwardCont { forward: Token, backward: Token =>
            quote($forward($source))
        }
        case FirstClassOptics(_) => forwardBackwardCont { forward: Token, backward: Token =>
            quote($constructFirstClassCallexprId($forward, $backward))
        }
        case FirstClassSetter(_, target) => forwardBackwardCont { forward: Token, backward: Token =>
            quote(
                let $finalSetterForwardVarname = $finalizingSetterForwardCallexpr($backward, $target)
                let $finalSetterBackwardVarname = $finalizingSetterBackwardCallexpr($backward, $target)
                $constructFirstClassCallexprId($finalSetterForwardVarname, $finalSetterBackwardVarname)
            )
        }
    }
}

private func composeOptics(nodes: Array<CompositionNode>): ((Token, Token) -> Tokens) -> Tokens {
    let iter = nodes.iterator()

    var currentNode: ?CompositionNode = iter.next()
    let magicCont: ((Tokens) -> Tokens) -> Tokens = if (let Some(node) <- currentNode) {
        match (node) {
            case Derived(input)     => throw Exception("WTF") // We change this case to `TypeOf, it should be impossible`
            case Type(input)        => 
                currentNode = iter.next()
                unwrapType(input)
            case TypeOf(input)      =>
                currentNode = iter.next()
                unwrapTypeOf(input)
            case Optic(input)       => { x => x(quote()) }    // TODO: REMOVE after making normal CPS. It will never be used if we encounter Optic first
            case Coerce(input)      => throw Exception("WTF") // We explicitly forbid that case while parsing
            case UserDefined(name, _, args) => throw Exception("WTF") // throw Exception("NOT_IMPLEMENTED")
        }
    } else { throw Exception("WTF") }

    var compositionCont: ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens = { _ => quote() }
    var first = true
    while (let Some(node) <- currentNode) {
        let currentCont = compositionCont
        match (node) {
            case Derived(input) => 
                if (first) {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        magicCont { currMagicalExpr: Tokens =>
                            unwrapDerivedStart(input)(currMagicalExpr)(cont)
                        }
                    }
                } else {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        currentCont { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
                            unwrapDerived(input)(currMagicalExpr, expectOptics, forward, backward, index)(cont)
                        }
                    }
                }
            case Type(input)        => throw Exception("WTF") // Not really clear what is the Type/TypeOf in the middle
            case TypeOf(input)      => throw Exception("WTF") // Not really clear what is the Type/TypeOf in the middle
            case Optic(input)       => 
                if (first) {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        magicCont { currMagicalExpr: Tokens =>
                            unwrapOpticStart(input)(currMagicalExpr)(cont)
                        }
                    }
                } else {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        currentCont { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
                            unwrapOptic(input)(currMagicalExpr, expectOptics, forward, backward, index)(cont)
                        }
                    }
                }
            case Coerce(input)      => 
                if (first) {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        magicCont { currMagicalExpr: Tokens =>
                            unwrapCoercionStart(input)(currMagicalExpr)(cont)
                        }
                    }
                } else {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        currentCont { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
                            unwrapCoercion(input)(currMagicalExpr, expectOptics, forward, backward, index)(cont)
                        }
                    }
                }
            case UserDefined(name, targs, args) =>
                if (first) {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        magicCont { currMagicalExpr: Tokens =>
                            unwrapUserDefinedStart(name, targs, args)(currMagicalExpr)(cont)
                        }
                    }
                } else {
                    compositionCont = { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
                        currentCont { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
                            unwrapUserDefined(name, targs, args)(currMagicalExpr, expectOptics, forward, backward, index)(cont)
                        }
                    }
                }
        }
        first = false
        currentNode = iter.next()
    }
    let currentCont = compositionCont
    { cont: (Token, Token) -> Tokens =>
        currentCont { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
            cont(forward, backward)
        }
    }
}

private func unwrapDerivedStart(input: Token): (Tokens) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens =>
        let index: UInt64 = 0
        let currMagical = Token(IDENTIFIER, "magic${index}")
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")

        let accessForward  = Token(IDENTIFIER, "__${input.value}_impl_forward")
        let accessBackward = Token(IDENTIFIER, "__${input.value}_impl_backward")
        let accessMagic = Token(IDENTIFIER, "__${input.value}_optics")
        let nextMagicalExpr = quote($currMagical.$accessMagic($currMagical))
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $currMagical = $currMagicalExpr
                let $opticsId = $currMagical.__downcast($currMagical)
                let $opticsIdImplForward = $opticsId.$accessForward
                let $opticsIdImplBackward = $opticsId.$accessBackward
                $(cont(nextMagicalExpr, opticsId, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}


private func unwrapDerived(input: Token): (Tokens, Token, Token, Token, UInt64) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
        let currMagical = Token(IDENTIFIER, "magic${index}")
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")

        let accessForward  = Token(IDENTIFIER, "__${input.value}_impl_forward")
        let accessBackward = Token(IDENTIFIER, "__${input.value}_impl_backward")
        let accessMagic = Token(IDENTIFIER, "__${input.value}_optics")
        let nextMagicalExpr = quote($currMagical.$accessMagic($currMagical))

        let newExpect = Token(IDENTIFIER, "__expect${index}")
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $currMagical = $currMagicalExpr
                let $opticsId = $currMagical.__downcast($currMagical)
                let $newExpect = $opticsUpcastCallexprId($expectOptics, $opticsId)
                let $opticsIdImplForward  = $composeForwardCallexprId($expectOptics, $opticsId)($forward, $opticsId.$accessForward, $backward, $opticsId.$accessBackward)
                let $opticsIdImplBackward = $composeBackwardCallexprId($expectOptics, $opticsId)($forward, $opticsId.$accessForward, $backward, $opticsId.$accessBackward)
                $(cont(nextMagicalExpr, newExpect, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}

private func unwrapType(input: RefExpr): ((Tokens) -> Tokens) -> Tokens {
    { thisMagicCont: (Tokens) -> Tokens  =>
        let tokens = quote($magicCallexprId<$input>())
        quote(
            $(thisMagicCont(tokens))
        )
    }
}

private func unwrapTypeOf(input: Tokens): ((Tokens) -> Tokens) -> Tokens {
    let magicId = Token(IDENTIFIER, "magicStart")
    { thisMagicCont: (Tokens) -> Tokens  =>
        let tokens = quote($magicCallexprId({ => $input}))
        quote(
            $(thisMagicCont(tokens))
        )
    }
}

private func unwrapOpticStart(input: Token): (Tokens) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { _: Tokens =>
        let index: UInt64 = 0
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")
        let nextMagicalExpr = quote(magicFirstClass($input))
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $opticsId = magicFirstClassDowncast($input)
                let $opticsIdImplForward = $forwardFieldId($input)
                let $opticsIdImplBackward = $backwardFieldId($input)
                $(cont(nextMagicalExpr, opticsId, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}


private func unwrapOptic(input: Token): (Tokens, Token, Token, Token, UInt64) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")
        let nextMagicalExpr = quote(magicFirstClass($input))
        let newExpect = Token(IDENTIFIER, "__expect${index}")
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $opticsId = magicFirstClassDowncast($input)
                let $newExpect = $opticsUpcastCallexprId($expectOptics, $opticsId)
                let $opticsIdImplForward  = $composeForwardCallexprId($expectOptics, $opticsId)($forward, $forwardFieldId($input), $backward, $backwardFieldId($input))
                let $opticsIdImplBackward = $composeBackwardCallexprId($expectOptics, $opticsId)($forward, $forwardFieldId($input), $backward, $backwardFieldId($input))
                $(cont(nextMagicalExpr, newExpect, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}

private func unwrapCoercionStart(input: TypeNode): (Tokens) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens =>
        let index: UInt64 = 0
        let currMagical = Token(IDENTIFIER, "magic${index}")
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")

        let nextMagicalExpr = quote($magicCallexprId<$input>())
        let accessForward  = quote($coerceForwardId($currMagical, $nextMagicalExpr))
        let accessBackward = quote($coerceBackwardId($currMagical, $nextMagicalExpr))

        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $currMagical = $currMagicalExpr
                let $opticsId = $downcastMethodCoerceId($currMagical, $nextMagicalExpr)
                let $opticsIdImplForward = $opticsId.$accessForward
                let $opticsIdImplBackward = $opticsId.$accessBackward
                $(cont(nextMagicalExpr, opticsId, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}

private func unwrapCoercion(input: TypeNode): (Tokens, Token, Token, Token, UInt64) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
        let currMagical = Token(IDENTIFIER, "magic${index}")
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")

        let nextMagicalExpr = quote($magicCallexprId<$input>())
        let accessForward  = quote($coerceForwardId($currMagical, $nextMagicalExpr))
        let accessBackward = quote($coerceBackwardId($currMagical, $nextMagicalExpr))

        let newExpect = Token(IDENTIFIER, "__expect${index}")
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $currMagical = $currMagicalExpr
                let $opticsId = $downcastMethodCoerceId($currMagical, $nextMagicalExpr)
                let $newExpect = $opticsUpcastCallexprId($expectOptics, $opticsId)
                let $opticsIdImplForward  = $composeForwardCallexprId($expectOptics, $opticsId)($forward, $opticsId.$accessForward, $backward, $opticsId.$accessBackward)
                let $opticsIdImplBackward = $composeBackwardCallexprId($expectOptics, $opticsId)($forward, $opticsId.$accessForward, $backward, $opticsId.$accessBackward)
                $(cont(nextMagicalExpr, newExpect, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}

private func unwrapUserDefinedStart(name: Token, targs: ArrayList<TypeNode>, args: ArrayList<Argument>): (Tokens) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens =>
        let index: UInt64 = 0
        let currMagical = Token(IDENTIFIER, "magic${index}")
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")

        let accessForward  = Token(IDENTIFIER, "__method_${name.value}_impl_forward")
        let accessBackward = Token(IDENTIFIER, "__method_${name.value}_impl_backward")
        let accessMagic = Token(IDENTIFIER, "__method_${name.value}_optics")
        let downcastName = Token(IDENTIFIER, "__downcast_method_${name.value}")
        let nextMagicalExpr = quote($currMagical.$accessMagic$(generics(targs))($currMagical))
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $currMagical = $currMagicalExpr
                let $opticsId = $currMagical.$downcastName$(generics(targs))($currMagical)
                let $opticsIdImplForward = $opticsId.$accessForward$(generics(targs))($currMagical, $(commaSeparated(args)))
                let $opticsIdImplBackward = $opticsId.$accessBackward$(generics(targs))($currMagical, $(commaSeparated(args)))
                $(cont(nextMagicalExpr, opticsId, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}


private func unwrapUserDefined(name: Token, targs: ArrayList<TypeNode>, args: ArrayList<Argument>): (Tokens, Token, Token, Token, UInt64) -> ((Tokens, Token, Token, Token, UInt64) -> Tokens) -> Tokens {
    { currMagicalExpr: Tokens, expectOptics: Token, forward: Token, backward: Token, index: UInt64 =>
        let currMagical = Token(IDENTIFIER, "magic${index}")
        let opticsId = Token(IDENTIFIER, "optics${index}")
        let opticsIdImplForward  = Token(IDENTIFIER, "optics${index}ImplForward")
        let opticsIdImplBackward = Token(IDENTIFIER, "optics${index}ImplBackward")

        let accessForward  = Token(IDENTIFIER, "__method_${name.value}_impl_forward")
        let accessBackward = Token(IDENTIFIER, "__method_${name.value}_impl_backward")
        let accessMagic = Token(IDENTIFIER, "__method_${name.value}_optics")
        let downcastName = Token(IDENTIFIER, "__downcast_method_${name.value}")
        let nextMagicalExpr = quote($currMagical.$accessMagic$(generics(targs))($currMagical))

        let newExpect = Token(IDENTIFIER, "__expect${index}")
        { cont: (Tokens, Token, Token, Token, UInt64) -> Tokens =>
            quote(
                let $currMagical = $currMagicalExpr
                let $opticsId = $currMagical.$downcastName$(generics(targs))($currMagical)
                let $newExpect = $opticsUpcastCallexprId($expectOptics, $opticsId)
                let $opticsIdImplForward  = $composeForwardCallexprId($expectOptics, $opticsId)($forward, $opticsId.$accessForward$(generics(targs))($currMagical, $(commaSeparated(args))), $backward, $opticsId.$accessBackward$(generics(targs))($currMagical, $(commaSeparated(args))))
                let $opticsIdImplBackward = $composeBackwardCallexprId($expectOptics, $opticsId)($forward, $opticsId.$accessForward$(generics(targs))($currMagical, $(commaSeparated(args))), $backward, $opticsId.$accessBackward$(generics(targs))($currMagical, $(commaSeparated(args))))
                $(cont(nextMagicalExpr, newExpect, opticsIdImplForward, opticsIdImplBackward, index + 1))
            )
        }
    }
}