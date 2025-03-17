macro package lucida_macro

import std.ast.*
import std.collection.*

class DiagReportException <: Exception {
    DiagReportException(
        message: String,
        public let tokens: Tokens,
        public let hint!: String = ""
    ) { super(message) }
}

public macro Lucida(input: Tokens): Tokens {
    try {
        match (parseExpr(input)) {
            case aexpr: AssignExpr => evalSetter(aexpr)
            case maccess: MemberAccess => giveLens(maccess)
            case _ => throw DiagReportException(
                "Unknown expression, passed to @Lucida macro",
                input
            )
        }
    } catch (e: DiagReportException) {
        diagReport(
            DiagReportLevel.ERROR,
            e.tokens,
            e.message,
            e.hint
        )
        quote($input)
    }
}

func expansionMain(cont: () -> Tokens): Tokens {
    quote(
        { =>
            $(cont())
        }()
    )
}

func evalSetter(aexpr: AssignExpr): Tokens {
    let maccess = aexpr.leftExpr as MemberAccess ?? 
        throw DiagReportException(
            "Left part of AssignExpr is not a MemberAccess",
            aexpr.leftExpr.toTokens()
        )

    expansionMain { =>
        let args = checkMemberAccessing(maccess)
        let composedLens = makeLensComposition(args)
        composedLens { lensId: Token => 
            quote($lensId.update($(args[0]), $(aexpr.rightExpr)))
        }
    }
}

func giveLens(maccess: MemberAccess): Tokens {
    expansionMain { =>
        let args = checkMemberAccessing(maccess)
        let composedLens = makeLensComposition(args)
        composedLens { lensId: Token => 
            quote($lensId)
        }
    }
}


func checkMemberAccessing(maccess: MemberAccess): Array<Token> {
    var expr: Expr = maccess.baseExpr
    let fields = ArrayList<Token>()
    fields.add(maccess.field)
    while (let Some(member) <- (expr as MemberAccess)) {
        expr = member.baseExpr
        fields.add(member.field)
    }

    match (expr) {
        case ce: CallExpr =>
            throw DiagReportException(
                "Call expr is not supported in @Lucida macro",
                ce.toTokens()
            )
        case oe: OptionalExpr =>
            throw DiagReportException(
                "Prisms are yet to come",
                oe.toTokens()
            )
        case se: SubscriptExpr =>
            throw DiagReportException(
                "SubscriptExpr is not supported in @Lucida macro",
                se.toTokens()
            )
        case field: RefExpr => 
            fields.add(field.identifier)
        case _ => 
            throw DiagReportException(
                "Some unexpected kind of token",
                expr.toTokens()
            )
    }
    fields.reverse()
    fields.toArray()
}

func accessesToLenses(accesses: Array<Token>): Array<Tokens> {
    if (accesses.size <= 1) {
        return accesses |> map {it: Token => quote($it)} |> collectArray
    }
    let result = ArrayList<Tokens>()
    var lensAccessor = quote($(accesses[0]))
    var i = 1
    while (i < accesses.size) {
        let ident = Token(IDENTIFIER, "__lens_${accesses[i].value}")
        result.add(quote($lensAccessor . $ident))
        lensAccessor = quote($lensAccessor.$(accesses[i]))
        i++
    }
    result.toArray()
}

func makeLensComposition(idents: Array<Token>): ((Token) -> Tokens) -> Tokens {
    let n = idents.size
    if (n == 0) {
        return { _ => quote() }
    }
    if (n == 1) {
        return { _ => quote($(idents[0])) }
    }
    let enumerator = enumerate(idents)
    let (i, arg) = enumerator.next() ?? throw Exception()
    var letId = Token(IDENTIFIER, "x${i}") 
    var xCurr = VarDecl(quote(let $letId = identityLens($arg)))
    let result = ArrayList<Decl>()
    result.add(xCurr)
    while (let Some((i, arg)) <- enumerator.next()) {
        let newLetId = Token(IDENTIFIER, "x${i}") 
        let methodId = Token(IDENTIFIER, "${arg.value}Impl")
        result.add(VarDecl(quote(let $newLetId = magic($letId).$methodId($letId))))
        letId = newLetId
    }
    let finalLetid = letId
    return { cont: (Token) -> Tokens => quote(
        $(result |> collectArrayList)
        $(cont(finalLetid))
    )}
}

public macro DeriveLenses(input: Tokens): Tokens {
    let currentDecl = parseDecl(input)

    let declIdentifier = currentDecl.identifier.toTokens()
    var body = Body()
    let varDecls = match (currentDecl) { 
        case c: ClassDecl => 
            body = c.body
            obtainVarDecls(c.body, declIdentifier)
        case s: StructDecl =>
            body = s.body
            obtainVarDecls(s.body, declIdentifier)
        case _ => throw DiagReportException(
            "Deriving optics for other than `struct` and `class` is not implemented",
            declIdentifier
        )
    }

    let interfaceDecl = deriveInterface(varDecls, currentDecl)
    let propertyExtends = deriveLensPropsExtend(varDecls, currentDecl)
    let magicalExtends = deriveMagicalExtend(varDecls, currentDecl)
    return quote(
        $currentDecl
        $interfaceDecl
        $propertyExtends
        $magicalExtends
    )
}

func obtainVarDecls(b: Body, declIdentifier: Tokens): ArrayList<FuncParam> {
    let primary = (b.decls |> filterMap { it: Decl => it as PrimaryCtorDecl} |> first) ??
        throw DiagReportException(
            "Primary constructor should be specified",
            declIdentifier
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
    return primary.funcParams
}

func deriveInterface(params: ArrayList<FuncParam>, decl: Decl): InterfaceDecl {
    let pctorId = decl.identifier
    let mod = if (let Some(am) <- decl.accessModifier) {
        if (am.keyword.kind == TokenKind.PUBLIC) { 
            quote(sealed)
        } else {
            am.toTokens()
        } 
    } else { quote() }
    let decls = params |> map { it : FuncParam =>
        let funcId = Token(IDENTIFIER, "${it.identifier.value}Impl")
        let mod = it.accessModifier?.toTokens() ?? Tokens()
        let focusType = it.paramType
        let res: Decl = FuncDecl(quote(
            @Frozen
            $mod func $funcId<T>(id: Lens<T, $pctorId>): Lens<T, $focusType>
        ))
        res
    } |> collectArrayList

    let interfaceId = Token(IDENTIFIER, "__${pctorId.value}_optics_impl")
    InterfaceDecl(quote(
        $mod interface $interfaceId {
            $decls
        }
    ))
}

func deriveLensPropsExtend(params: ArrayList<FuncParam>, decl: Decl): ExtendDecl {
    let pctorId = decl.identifier
    let argvars: Array<Tokens> = params |> map { it: FuncParam =>
        quote(source.$(it.identifier))
    } |> collectArray

    let sourceSetId = if (argvars.size <= 1) { quote(_) } else { quote(source) }
    let props = params |> enumerate |> map { pair: (Int64, FuncParam) =>
        let (i, it) = pair
        let mod = it.accessModifier?.toTokens() ?? Tokens()
        let lensId = Token(IDENTIFIER, "__lens_${it.identifier.value}")
        let focusType = it.paramType
        let prev = argvars[i]
        argvars[i] = quote(focus)
        let res: Decl = PropDecl(quote(
            @Frozen
            $mod static prop $lensId: Lens<$pctorId, $focusType> {
                get() {
                    createLens(
                        { source: $pctorId => source.$(it.identifier)},
                        { $sourceSetId: $pctorId, focus: $focusType =>
                            $pctorId($(commaSeparated(argvars)))
                        }
                    )
                }
            }
        ))
        argvars[i] = prev
        res
    } |> collectArrayList
    ExtendDecl(quote(
        extend $pctorId {
            $props
        }
    ))
}

func deriveMagicalExtend(params: ArrayList<FuncParam>, decl: Decl): Decl {
    let pctorId = decl.identifier
    let impls = params |> map { it : FuncParam =>
        let mod = it.accessModifier?.toTokens() ?? Tokens()
        let lensId = Token(IDENTIFIER, "__lens_${it.identifier.value}")
        let lensAccessor = quote($pctorId.$lensId)
        let funcId = Token(IDENTIFIER, "${it.identifier.value}Impl")
        let focusType = it.paramType
        let res: Decl = FuncDecl(quote(
            @Frozen
            $mod func $funcId<T>(id: Lens<T, $pctorId>): Lens<T, $focusType> {
                compose(
                    id,
                    $lensAccessor
                )
            }
        ))
        res
    } |> collectArrayList

    let interfaceId = Token(IDENTIFIER, "__${pctorId.value}_optics_impl")
    ExtendDecl(quote(
        extend Magical<$pctorId> <: $interfaceId {
            $impls
        }
    ))
}

extend Decl {
    prop accessModifier: ?Modifier {
        get() {
            this.modifiers |> filter { it: Modifier =>
                let kind = it.keyword.kind
                kind == TokenKind.PUBLIC ||
                kind == TokenKind.PROTECTED ||
                kind == TokenKind.PRIVATE
            } |> first
        }
    }
}

func commaSeparated<T>(things: Iterable<T>): Tokens where T <: ToTokens {
    let tokens = Tokens()
    let it = things.iterator()
    let first = it.next()

    (first?.toTokens() ?? return tokens) |> tokens.append

    for (e in it) {
        tokens.append(Token(COMMA)).append(e.toTokens())
    }
    return tokens
}
