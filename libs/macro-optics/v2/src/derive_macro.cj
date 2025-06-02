macro package lucida_macro

import std.ast.*
import std.collection.*

public macro DeriveOptics(input: Tokens): Tokens {
    try {
        let currentDecl = parseDecl(input)

        let result = match (currentDecl) { 
            case c: ClassDecl =>
                deriveClassOptics(c)
            case s: StructDecl =>
                deriveStructOptics(s)
            case e: EnumDecl => 
                throw Exception("NOT_IMPLEMENTED")
            case _ => throw DiagReportException(
                "${deriveOpticsMacro}: Deriving optics for other than `struct` and `class` and `enum` is not implemented",
                currentDecl.identifier.toTokens()
            )
        }

        return quote(
            $currentDecl
            $result
        ) 
    } catch(e: DiagReportException) {
        diagReport(
            DiagReportLevel.ERROR,
            e.tokens,
            e.message,
            e.hint
        )
        quote($input)
    }
}

enum OpticsVisibility {
    | PUBLIC_OPTICS
    | PACKAGE_OPTICS

    public prop isPublic: Bool {
        get() {
            match (this) {
                case PUBLIC_OPTICS => true
                case PACKAGE_OPTICS => false
            }
        }
    }
}

struct DerivableLens {
    DerivableLens(
        public let visibility: OpticsVisibility,
        public let identifier: Token,
        public let sourceType: Tokens,
        public let focusType: Tokens
    ) { }
}

private func deriveStructOptics(s: StructDecl): Tokens {
    let params = obtainVarDecls(s.body, s.identifier)
    let lenses = deriveLenses(params, s.identifier)
    if (params.size == 1) {
        let isos = deriveIsos(params[0], s.identifier)
        quote(
            $lenses
            $isos
        )
    } else {
        quote($lenses)
    }
}

private func deriveClassOptics(c: ClassDecl): Tokens {
    let params = obtainVarDecls(c.body, c.identifier)
    let lenses = deriveLenses(params, c.identifier)
    if (params.size == 1) {
        let isos = deriveIsos(params[0], c.identifier)
        quote(
            $lenses
            $isos
        )
    } else {
        quote($lenses)
    }
}

private func deriveIsos(param: DerivableLens, declIdentifier: Token): Tokens {
    let optics = deriveOpticsExtendIso(param, declIdentifier)
    quote($optics)
}

private func deriveOpticsExtendIso(param: DerivableLens, declIdentifier: Token): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    let (aToBDecls, bToADecls) = deriveIsoDecls(param)
    let (aToBImpls, bToAImpls) = (deriveIsoImpls(param), deriveIsoImpls(param, reverse: true))
    let interfaceId1 = Token(IDENTIFIER, "__from_${declIdentifier.value}_isos_impl")
    let interfaceId2 = Token(IDENTIFIER, "__to_${declIdentifier.value}_isos_impl")

    let makeExtend = { interfaceId: Token, decls: ArrayList<Decl>, impls: ArrayList<Decl>, sourceType: Tokens => 
        let interfaceExtension = if (param.visibility.isPublic) {
            result.addContra(InterfaceDecl(quote(
                sealed interface $interfaceId {
                    $(decls)
                }
            )))
            quote(<: $interfaceId)
        } else { quote() }
        result.addContra(ExtendDecl(quote(
            extend $registryIsoId<$sourceType> $interfaceExtension {
                $impls
            }
        )))
    }
    makeExtend(interfaceId1, aToBDecls, aToBImpls, param.sourceType)
    makeExtend(interfaceId2, bToADecls, bToAImpls, param.focusType)
    result
}

private func deriveIsoDecls(param: DerivableLens): (ArrayList<Decl>, ArrayList<Decl>) {
    let sourceType = param.sourceType
    let focusType = param.focusType

    let genDecls = { sourceType: Tokens, focusType: Tokens =>
        let res = ArrayList<Decl>()
        res.addContra(FuncDecl(quote(
            @Frozen
            func $coerceForwardId(_: $registryMainId<$sourceType>, _: $registryMainId<$focusType>): ($sourceType) -> $focusType
        )))
        res.addContra(FuncDecl(quote(
            @Frozen
            func $coerceBackwardId(_: $registryMainId<$sourceType>, _: $registryMainId<$focusType>): ($focusType) -> $sourceType
        )))
        res
    }
    (genDecls(sourceType, focusType), genDecls(focusType, sourceType))
}

private func deriveIsoImpls(param: DerivableLens, reverse!: Bool = false): ArrayList<Decl> {
    let sourceType = param.sourceType
    let focusType = param.focusType
    let identifier = param.identifier

    let mod = match (param.visibility) {
        case PUBLIC_OPTICS  => quote(public)
        case PACKAGE_OPTICS => quote()
    }

    let forwardMethod = quote({ source: $sourceType => source.$identifier})
    let backwardMethod = quote({ focus: $focusType => $sourceType(focus)})

    let res = ArrayList<Decl>()
    let getMethods = { sourceType: Tokens, focusType: Tokens, forwardMethod: Tokens, backwardMethod: Tokens =>
        res.addContra(FuncDecl(quote(
            @Frozen
            $mod func $coerceForwardId(_: $registryMainId<$sourceType>, _: $registryMainId<$focusType>): ($sourceType) -> $focusType {
                $forwardMethod
            }
        )))
        res.addContra(FuncDecl(quote(
            @Frozen
            $mod func $coerceBackwardId(_: $registryMainId<$sourceType>, _: $registryMainId<$focusType>): ($focusType) -> $sourceType {
                $backwardMethod
            }
        )))
    }
    if (!reverse) {
        getMethods(sourceType, focusType, forwardMethod, backwardMethod)
    } else {
        getMethods(focusType, sourceType, backwardMethod, forwardMethod)
    }
    res
}

private func deriveLenses(params: ArrayList<DerivableLens>, declIdentifier: Token): Tokens {
    let optics = deriveOpticsExtend(params, declIdentifier)
    let suboptics = deriveSubopticAccessorExtend(params, declIdentifier)
    let downcasts = deriveDowncastExtend(params, declIdentifier)
    quote(
        $optics
        $suboptics
        $downcasts
    )
}

private func obtainVarDecls(b: Body, declIdentifier: Token): ArrayList<DerivableLens> {
    let primary = (b.decls |> filterMap { it: Decl => it as PrimaryCtorDecl} |> first) ??
        throw DiagReportException(
            "Primary constructor should be specified",
            declIdentifier.toTokens()
        )

    primary.funcParams |> forEach { it: FuncParam =>
        if (it.keyword.kind != LET && it.keyword.kind != VAR) {
            throw DiagReportException(
                "Primary constructor should contain only field declarations",
                it.toTokens()
            ) 
        }
        if (let Some(kind) <- it.accessModifier?.keyword.kind && kind == TokenKind.PRIVATE) {
            throw DiagReportException(
                "Primary constructor should contain only non-private field declarations",
                it.toTokens()
            ) 
        }
    }

    primary.funcParams |> map { it: FuncParam =>
        let visibility = if (let Some(kind) <- it.accessModifier?.keyword.kind && kind == TokenKind.PUBLIC) {
            PUBLIC_OPTICS
        } else { PACKAGE_OPTICS }
        DerivableLens(visibility, it.identifier, declIdentifier.toTokens(), it.paramType.toTokens())
    } |> collectArrayList
}

func deriveOpticsExtend(params: ArrayList<DerivableLens>, pctorId: Token): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    let publicInterfaceDecls = params |> filter { it: DerivableLens => it.visibility.isPublic } |> collectArrayList
    let interfaceExtension = if (publicInterfaceDecls.size != 0) {
        let interfaceId = Token(IDENTIFIER, "__${pctorId.value}_optics_impl")
        result.addContra(InterfaceDecl(quote(
            sealed interface $interfaceId {
                $(deriveLensDecls(publicInterfaceDecls))
            }
        )))
        quote(<: $interfaceId)
    } else { quote() }
    result.addContra(ExtendDecl(quote(
        extend $registryLensId<$pctorId> $interfaceExtension {
            $(deriveLensImpls(params))
        }
    )))
    result
}

func deriveLensDecls(params: ArrayList<DerivableLens>): ArrayList<Decl> {
    params |> flatMap { it: DerivableLens =>
        let funcForwardId = Token(IDENTIFIER, "__${it.identifier.value}_impl_forward")
        let funcBackwardId = Token(IDENTIFIER, "__${it.identifier.value}_impl_backward")
        let sourceType = it.sourceType
        let focusType = it.focusType

        let res = ArrayList<Decl>()
        let forward: Decl = FuncDecl(quote(
            @Frozen
            func $funcForwardId(source: $sourceType): $focusType
        ))
        res.add(forward)

        let backward: Decl = FuncDecl(quote(
            @Frozen
            func $funcBackwardId(source: $sourceType, focus: $focusType): $sourceType
        ))
        res.add(backward)
        res
    } |> collectArrayList
}

func deriveLensImpls(params: ArrayList<DerivableLens>): ArrayList<Decl> {
    let argvars: Array<Tokens> = params |> map { it: DerivableLens =>
        quote(source.$(it.identifier))
    } |> collectArray

    params |> enumerate |> flatMap { pair: (Int64, DerivableLens) =>
        let (i, it) = pair
        let funcForwardId = Token(IDENTIFIER, "__${it.identifier.value}_impl_forward")
        let funcBackwardId = Token(IDENTIFIER, "__${it.identifier.value}_impl_backward")
        let mod = match (it.visibility) {
            case PUBLIC_OPTICS  => quote(public)
            case PACKAGE_OPTICS => quote()
        }
        let sourceType = it.sourceType
        let focusType = it.focusType
        let prev = argvars[i]
        argvars[i] = quote(focus)

        let res = ArrayList<Decl>()
        let forward: Decl = FuncDecl(quote(
            @Frozen
            $mod func $funcForwardId(source: $sourceType): $focusType {
                source.$(it.identifier)
            }
        ))
        res.add(forward)
        let backward: Decl = FuncDecl(quote(
            @Frozen
            $mod func $funcBackwardId(source: $sourceType, focus: $focusType): $sourceType {
                $sourceType($(commaSeparated(argvars)))
            }
        ))
        res.add(backward)
        argvars[i] = prev
        res
    } |> collectArrayList
}

func deriveSubopticAccessorExtend(params: ArrayList<DerivableLens>, pctorId: Token): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    let publicInterfaceDecls = params |> filter { it: DerivableLens => it.visibility.isPublic } |> collectArrayList
    let interfaceExtension = if (publicInterfaceDecls.size != 0) {
        let interfaceId = Token(IDENTIFIER, "__${pctorId.value}_suboptics_accessors")
        result.addContra(InterfaceDecl(quote(
            sealed interface $interfaceId {
                $(deriveSubopticAccessorDecls(publicInterfaceDecls))
            }
        )))
        quote(<: $interfaceId)
    } else { quote() }
    result.addContra(ExtendDecl(quote(
        extend $registryMainId<$pctorId> $interfaceExtension {
            $(deriveSubopticAccessorImpl(params))
        }
    )))
    result
}

func deriveSubopticAccessorDecls(params: ArrayList<DerivableLens>): ArrayList<Decl> {
    params |> map { it: DerivableLens =>
        let funcId = Token(IDENTIFIER, "__${it.identifier.value}_optics")
        let sourceType = it.sourceType
        let focusType = it.focusType

        let out: Decl = FuncDecl(quote(
            @Frozen
            func $funcId(_: $registryMainId<$sourceType>): $registryMainId<$focusType>
        ))
        out
    } |> collectArrayList
}

func deriveSubopticAccessorImpl(params: ArrayList<DerivableLens>): ArrayList<Decl> {
    params |> map { it: DerivableLens =>
        let funcId = Token(IDENTIFIER, "__${it.identifier.value}_optics")
        let mod = match (it.visibility) {
            case PUBLIC_OPTICS  => quote(public)
            case PACKAGE_OPTICS => quote()
        }
        let sourceType = it.sourceType
        let focusType = it.focusType

        let out: Decl = FuncDecl(quote(
            @Frozen
            $mod func $funcId(_: $registryMainId<$sourceType>): $registryMainId<$focusType> { $registryMainId() }
        ))
        out
    } |> collectArrayList
}

func deriveDowncastExtend(params: ArrayList<DerivableLens>, pctorId: Token): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    let publicInterfaceDecls = params |> filter { it: DerivableLens => it.visibility.isPublic } |> collectArrayList
    let interfaceExtension = if (publicInterfaceDecls.size != 0) {
        let interfaceId = Token(IDENTIFIER, "__${pctorId.value}_downcast")
        result.addContra(InterfaceDecl(quote(
            sealed interface $interfaceId {
                $(deriveDowncastDecls(pctorId))
            }
        )))
        quote(<: $interfaceId)
    } else { quote() }
    result.addContra(ExtendDecl(quote(
        extend $registryMainId<$pctorId> $interfaceExtension {
            $(deriveDowncastImpl(pctorId))
        }
    )))
    result
}

func deriveDowncastDecls(pctorId: Token): Decl {
    let funcId = Token(IDENTIFIER, "__downcast")
    let out: Decl = FuncDecl(quote(
        @Frozen
        func $funcId(_: $registryMainId<$pctorId>): $registryLensId<$pctorId>
    ))
    out
}

func deriveDowncastImpl(pctorId: Token): Decl {
    let funcId = Token(IDENTIFIER, "__downcast")
    let out: Decl = FuncDecl(quote(
        @Frozen
        public func $funcId(_: $registryMainId<$pctorId>): $registryLensId<$pctorId> { $registryLensId() }
    ))
    out
}
