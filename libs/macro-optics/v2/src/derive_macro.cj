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
                deriveEnumOptics(e)
            case _ => throw DiagReportException(
                "${deriveOpticsMacro}: deriving optics is only implemented for `struct`, `class` and `enum`",
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

/// Splices to nothing for non-generic decls, or to `<T>` / `<K, V>` for generic ones.
/// Used both as a declaration-site header (`extend <T> ...`) and as a type-use suffix
/// (`__Box_optics_impl<T>`), which share the same spelling.
func genHeader(gen: ?Tokens): Tokens {
    if (let Some(t) <- gen) {
        return quote(<$t>)
    }
    return quote()
}

/// Rejects `where` clauses on annotated declarations (not supported yet).
func rejectGenericConstraints(constraints: ArrayList<GenericConstraint>, declIdentifier: Token): Unit {
    if (constraints.size > 0) {
        throw DiagReportException(
            "${deriveOpticsMacro}: generic constraints ('where' clauses) are not supported yet",
            declIdentifier.toTokens(),
            hint: "Remove the constraint or hand-write the optics"
        )
    }
}

private func deriveStructOptics(s: StructDecl): Tokens {
    rejectGenericConstraints(s.genericConstraint, s.identifier)
    let gen: ?Tokens = if (s.isGenericDecl) { Some(s.genericParam.parameters) } else { None }
    let hdr = genHeader(gen)
    let idTok = s.identifier
    let fullTypeId = if (let Some(t) <- gen) { quote($idTok<$t>) } else { quote($idTok) }
    let params = obtainVarDecls(s.body, fullTypeId)
    let lenses = deriveLenses(params, s.identifier, hdr)
    if (params.size == 1) {
        let isos = deriveIsos(params[0], s.identifier, hdr)
        quote(
            $lenses
            $isos
        )
    } else {
        quote($lenses)
    }
}

private func deriveClassOptics(c: ClassDecl): Tokens {
    rejectGenericConstraints(c.genericConstraint, c.identifier)
    let gen: ?Tokens = if (c.isGenericDecl) { Some(c.genericParam.parameters) } else { None }
    let hdr = genHeader(gen)
    let idTok = c.identifier
    let fullTypeId = if (let Some(t) <- gen) { quote($idTok<$t>) } else { quote($idTok) }
    let params = obtainVarDecls(c.body, fullTypeId)
    let lenses = deriveLenses(params, c.identifier, hdr)
    if (params.size == 1) {
        let isos = deriveIsos(params[0], c.identifier, hdr)
        quote(
            $lenses
            $isos
        )
    } else {
        quote($lenses)
    }
}

private func deriveIsos(param: DerivableLens, declIdentifier: Token, genHdr: Tokens): Tokens {
    let optics = deriveOpticsExtendIso(param, declIdentifier, genHdr)
    quote($optics)
}

private func deriveOpticsExtendIso(param: DerivableLens, declIdentifier: Token, genHdr: Tokens): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    let (aToBDecls, bToADecls) = deriveIsoDecls(param)
    let (aToBImpls, bToAImpls) = (deriveIsoImpls(param), deriveIsoImpls(param, reverse: true))
    let interfaceId1 = Token(IDENTIFIER, "__from_${declIdentifier.value}_isos_impl")
    let interfaceId2 = Token(IDENTIFIER, "__to_${declIdentifier.value}_isos_impl")

    let makeExtend = { interfaceId: Token, decls: ArrayList<Decl>, impls: ArrayList<Decl>, sourceType: Tokens =>
        let interfaceExtension = if (param.visibility.isPublic) {
            result.addContra(InterfaceDecl(quote(
                sealed interface $interfaceId$genHdr {
                    $(decls)
                }
            )))
            quote(<: $interfaceId$genHdr)
        } else { quote() }
        result.addContra(ExtendDecl(quote(
            extend $genHdr $registryIsoId<$sourceType> $interfaceExtension {
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

private func deriveLenses(params: ArrayList<DerivableLens>, declIdentifier: Token, genHdr: Tokens): Tokens {
    let optics = deriveOpticsExtend(params, declIdentifier, genHdr)
    let suboptics = deriveSubopticAccessorExtend(params, declIdentifier, genHdr)
    let downcasts = deriveDowncastExtend(params, declIdentifier, genHdr)
    quote(
        $optics
        $suboptics
        $downcasts
    )
}

private func obtainVarDecls(b: Body, fullTypeId: Tokens): ArrayList<DerivableLens> {
    let primary = (b.decls |> filterMap { it: Decl => it as PrimaryCtorDecl} |> first) ??
        throw DiagReportException(
            "Primary constructor should be specified",
            fullTypeId
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
        DerivableLens(visibility, it.identifier, fullTypeId, it.paramType.toTokens())
    } |> collectArrayList
}

func deriveOpticsExtend(params: ArrayList<DerivableLens>, pctorId: Token, genHdr: Tokens): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    let publicInterfaceDecls = params |> filter { it: DerivableLens => it.visibility.isPublic } |> collectArrayList
    let interfaceExtension = if (publicInterfaceDecls.size != 0) {
        let interfaceId = Token(IDENTIFIER, "__${pctorId.value}_optics_impl")
        result.addContra(InterfaceDecl(quote(
            sealed interface $interfaceId$genHdr {
                $(deriveLensDecls(publicInterfaceDecls))
            }
        )))
        quote(<: $interfaceId$genHdr)
    } else { quote() }
    result.addContra(ExtendDecl(quote(
        extend $genHdr $registryLensId<$pctorId$genHdr> $interfaceExtension {
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

func deriveSubopticAccessorExtend(params: ArrayList<DerivableLens>, pctorId: Token, genHdr: Tokens): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    let publicInterfaceDecls = params |> filter { it: DerivableLens => it.visibility.isPublic } |> collectArrayList
    let interfaceExtension = if (publicInterfaceDecls.size != 0) {
        let interfaceId = Token(IDENTIFIER, "__${pctorId.value}_suboptics_accessors")
        result.addContra(InterfaceDecl(quote(
            sealed interface $interfaceId$genHdr {
                $(deriveSubopticAccessorDecls(publicInterfaceDecls))
            }
        )))
        quote(<: $interfaceId$genHdr)
    } else { quote() }
    result.addContra(ExtendDecl(quote(
        extend $genHdr $registryMainId<$pctorId$genHdr> $interfaceExtension {
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

func deriveDowncastExtend(params: ArrayList<DerivableLens>, pctorId: Token, genHdr: Tokens): ArrayList<Decl> {
    let result = ArrayList<Decl>()
    let publicInterfaceDecls = params |> filter { it: DerivableLens => it.visibility.isPublic } |> collectArrayList
    let interfaceExtension = if (publicInterfaceDecls.size != 0) {
        let interfaceId = Token(IDENTIFIER, "__${pctorId.value}_downcast")
        result.addContra(InterfaceDecl(quote(
            sealed interface $interfaceId$genHdr {
                $(deriveDowncastDecls(pctorId, genHdr))
            }
        )))
        quote(<: $interfaceId$genHdr)
    } else { quote() }
    result.addContra(ExtendDecl(quote(
        extend $genHdr $registryMainId<$pctorId$genHdr> $interfaceExtension {
            $(deriveDowncastImpl(pctorId, genHdr))
        }
    )))
    result
}

func deriveDowncastDecls(pctorId: Token, genHdr: Tokens): Decl {
    let funcId = Token(IDENTIFIER, "__downcast")
    let out: Decl = FuncDecl(quote(
        @Frozen
        func $funcId(_: $registryMainId<$pctorId$genHdr>): $registryLensId<$pctorId$genHdr>
    ))
    out
}

func deriveDowncastImpl(pctorId: Token, genHdr: Tokens): Decl {
    let funcId = Token(IDENTIFIER, "__downcast")
    let out: Decl = FuncDecl(quote(
        @Frozen
        public func $funcId(_: $registryMainId<$pctorId$genHdr>): $registryLensId<$pctorId$genHdr> { $registryLensId() }
    ))
    out
}

// ==================== Enum prism derivation ====================

private func joinTokenValues(toks: ArrayList<Token>): String {
    let sb = StringBuilder()
    for (t in toks) {
        sb.append(t.value)
        sb.append(" ")
    }
    sb.toString()
}

private func tokensOf(toks: ArrayList<Token>): Tokens {
    Tokens(toks)
}

/// Splits a constructor's payload into top-level token segments between its
/// outer parentheses. Empty list when the case has no parentheses at all.
private func casePayloadSegments(c: Constructor): ArrayList<ArrayList<Token>> {
    let toks = ArrayList<Token>()
    c.toTokens() |> forEach { tk: Token => toks.add(tk) }
    let segments = ArrayList<ArrayList<Token>>()
    var depth = 0
    var cur = ArrayList<Token>()
    var seenParens = false
    for (t in toks) {
        if (t.kind == TokenKind.LPAREN) {
            depth += 1
            seenParens = true
            if (depth >= 2) { cur.add(t) }
            continue
        }
        if (t.kind == TokenKind.RPAREN) {
            depth -= 1
            if (depth == 0) {
                segments.add(cur)
                break
            }
            cur.add(t)
            continue
        }
        if (t.kind == TokenKind.COMMA && depth == 1) {
            segments.add(cur)
            cur = ArrayList<Token>()
            continue
        }
        if (depth >= 1) { cur.add(t) }
    }
    if (!seenParens) {
        return ArrayList<ArrayList<Token>>()
    }
    return segments
}

private func deriveEnumOptics(e: EnumDecl): Tokens {
    rejectGenericConstraints(e.genericConstraint, e.identifier)
    let gen: ?Tokens = if (e.isGenericDecl) { Some(e.genericParam.parameters) } else { None }
    let hdr = genHeader(gen)
    let idTok = e.identifier
    let fullTypeId = if (let Some(t) <- gen) { quote($idTok<$t>) } else { quote($idTok) }

    let implDecls = ArrayList<Decl>()
    let accessorDecls = ArrayList<Decl>()

    for (c in e.constructors) {
        let segs = casePayloadSegments(c)
        let isEmpty = segs.size == 0 || (segs.size == 1 && segs[0].size == 0)
        if (isEmpty) {
            throw DiagReportException(
                "${deriveOpticsMacro}: enum case '${c.identifier.value}' has no associated value; only single-payload cases are supported",
                c.identifier.toTokens(),
                hint: "Give the case exactly one associated value, or hand-write its prism"
            )
        }
        if (segs.size > 1) {
            throw DiagReportException(
                "${deriveOpticsMacro}: enum case '${c.identifier.value}' has ${segs.size} associated values; only single-payload cases are supported",
                c.identifier.toTokens(),
                hint: "Bundle the values into one struct and derive optics for that struct"
            )
        }
        let (payloadType, _) = parseTypeFragment(tokensOf(segs[0]))
        let caseId = c.identifier
        let fwdId = Token(IDENTIFIER, "__${caseId.value}_impl_forward")
        let bwdId = Token(IDENTIFIER, "__${caseId.value}_impl_backward")
        let accId = Token(IDENTIFIER, "__${caseId.value}_optics")
        let binder = Token(IDENTIFIER, "__payload_${caseId.value}")

        implDecls.addContra(FuncDecl(quote(
            @Frozen
            public func $fwdId(source: $fullTypeId): Either<$fullTypeId, $payloadType> {
                match (source) {
                    case $caseId($binder) => Right<$fullTypeId, $payloadType>($binder)
                    case _ => Left<$fullTypeId, $payloadType>(source)
                }
            }
        )))
        implDecls.addContra(FuncDecl(quote(
            @Frozen
            public func $bwdId(source: $fullTypeId, payload: $payloadType): $fullTypeId {
                match (source) {
                    case $caseId(_) => $caseId(payload)
                    case _ => source
                }
            }
        )))
        accessorDecls.addContra(FuncDecl(quote(
            @Frozen
            public func $accId(_: $registryMainId<$fullTypeId>): $registryMainId<$payloadType> { $registryMainId() }
        )))
    }

    // Interface signatures mirror the impls (bodies dropped).
    let implSigDecls = ArrayList<Decl>()
    let accessorSigDecls = ArrayList<Decl>()
    for (c in e.constructors) {
        let segs = casePayloadSegments(c)
        let (payloadType, _) = parseTypeFragment(tokensOf(segs[0]))
        let caseId = c.identifier
        let fwdId = Token(IDENTIFIER, "__${caseId.value}_impl_forward")
        let bwdId = Token(IDENTIFIER, "__${caseId.value}_impl_backward")
        let accId = Token(IDENTIFIER, "__${caseId.value}_optics")

        implSigDecls.addContra(FuncDecl(quote(
            @Frozen
            func $fwdId(source: $fullTypeId): Either<$fullTypeId, $payloadType>
        )))
        implSigDecls.addContra(FuncDecl(quote(
            @Frozen
            func $bwdId(source: $fullTypeId, payload: $payloadType): $fullTypeId
        )))
        accessorSigDecls.addContra(FuncDecl(quote(
            @Frozen
            func $accId(_: $registryMainId<$fullTypeId>): $registryMainId<$payloadType>
        )))
    }

    let implsInterfaceId = Token(IDENTIFIER, "__${idTok.value}_prisms_impl")
    let accessorsInterfaceId = Token(IDENTIFIER, "__${idTok.value}_suboptics_accessors")
    let downcastInterfaceId = Token(IDENTIFIER, "__${idTok.value}_downcast")
    let downcastFuncId = Token(IDENTIFIER, "__downcast")

    quote(
        sealed interface $implsInterfaceId$hdr {
            $(implSigDecls)
        }
        sealed interface $accessorsInterfaceId$hdr {
            $(accessorSigDecls)
        }
        sealed interface $downcastInterfaceId$hdr {
            @Frozen
            func $downcastFuncId(_: $registryMainId<$fullTypeId>): $registryOptionalId<$fullTypeId>
        }

        extend $hdr $registryOptionalId<$fullTypeId> <: $implsInterfaceId$hdr {
            $(implDecls)
        }
        extend $hdr $registryMainId<$fullTypeId> <: $accessorsInterfaceId$hdr {
            $(accessorDecls)
        }
        extend $hdr $registryMainId<$fullTypeId> <: $downcastInterfaceId$hdr {
            @Frozen
            public func $downcastFuncId(_: $registryMainId<$fullTypeId>): $registryOptionalId<$fullTypeId> { $registryOptionalId() }
        }
    )
}
