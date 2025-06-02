package lucida

/**
 * Works for:
 * <Iso, Iso>
 * <Iso, Lens>
 * <Lens, Iso>
 * <Lens, Lens>
 */
// private func isoForward<S, A, B>(i1to: (S) -> A, i2to: (A) -> B) {
//     { source: S => i2to(i1to(source)) }
// }
/**
 * Works for:
 * <Iso, Iso>
 * <Iso, Prism>
 * <Prism, Iso>
 * <Prism, Prism>
 */
// private func isoBackward<S, A, B>(i1from: (A) -> S, i2from: (B) -> A) {
//     { focus: B => i1from(i2from(focus)) }
// }
/**
 * Works for:
 * <Iso, Prism>
 * <Iso, Option>
 * <Lens, Option>
 * <Lens, Prism>
 */
// private func isoPrismForward<S, A, B>(i1to: (S) -> A, p2preview: (A) -> Either<A, B>) {
//     { source: S => 
//         if (let Right(prv2) <- p2preview(i1to(source))) {
//             Right<S, B>(prv2)
//         } else {
//             Left<S, B>(source)
//         }
//     }
// }
/**
 * Works for:
 * <Prism, Iso>
 * <Option, Iso>
 * <Prism, Lens>
 * <Option, Lens>
 */
// private func prismIsoForward<S, A, B>(p1preview: (S) -> Either<S, A>, i2to: (A) -> B) {
//     { source: S => 
//         if (let Right(prv1) <- p1preview(source)) {
//             Right<S, B>(i2to(prv1))
//         } else {
//             Left<S, B>(source)
//         }
//     }
// }
/**
 * Works for:
 * <Iso, Lens>
 */
// private func isoLensBackward<S, A, B>(i1to: (S) -> A, i1from: (A) -> S, l2update: (A, B) -> A) {
//     { source: S, focus: B => i1from(l2update(i1to(source), focus)) }
// }
/**
 * Works for:
 * <Lens, Iso>
 */
// private func lensIsoBackward<S, A, B>(l1update: (S, A) -> S, i2from: (B) -> A) {
//     { source: S, focus: B => l1update(source, i2from(focus)) }
// }
/**
 * Works for:
 * <Lens, Lens>
 */
// private func lensBackward<S, A, B>(l1view: (S) -> A, l1update: (S, A) -> S, l2update: (A, B) -> A) {
//     { source: S, focus: B => l1update(source, l2update(l1view(source), focus)) }
// }
/**
 * Works for:
 * <Prism, Prism>
 * <Prism, Option>
 * <Option, Prism>
 */
// private func prismForward<S, A, B>(p1preview: (S) -> Either<S, A>, p2preview: (A) -> Either<A, B>) {
//     { source: S => 
//         if (let Right(prv1) <- p1preview(source) && let Right(res) <- p2preview(prv1)) {
//             Right<S, B>(res)
//         } else {
//             Left<S, B>(source)
//         }
//     }
// }

public struct __OpticsCompositions {
    // 1 <Iso, Iso> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryIsos<S>, _: RegistryIsos<A>) {
        { i1to: (S) -> A, i2to: (A) -> B, _: (A) -> S, _: (B) -> A =>
            { source: S => i2to(i1to(source)) }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryIsos<S>, _: RegistryIsos<A>) {
        { _: (S) -> A, _: (A) -> B, i1from: (A) -> S, i2from: (B) -> A =>
            { focus: B => i1from(i2from(focus)) }
        }
    }

    // 2 <Lens, Lens> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryLenses<S>, _: RegistryLenses<A>) {
        { l1view: (S) -> A, l2view: (A) -> B, _: (S, A) -> S, _: (A, B) -> A =>
            { source: S => l2view(l1view(source)) }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryLenses<S>, _: RegistryLenses<A>) {
        { l1view: (S) -> A, _: (A) -> B, l1update: (S, A) -> S, l2update: (A, B) -> A =>
            { source: S, focus: B => l1update(source, l2update(l1view(source), focus)) }
        }
    }

    // 3 <Prism, Prism> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryPrisms<S>, _: RegistryPrisms<A>) {
        { p1preview: (S) -> Either<S, A>, p2preview: (A) -> Either<A, B>, _: (A) -> S, _: (B) -> A =>
            { source: S => 
                if (let Right(prv1) <- p1preview(source) && let Right(res) <- p2preview(prv1)) {
                    Right<S, B>(res)
                } else {
                    Left<S, B>(source)
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryPrisms<S>, _: RegistryPrisms<A>) {
        { _: (S) -> Either<S, A>, _: (A) -> Either<A, B>, p1build: (A) -> S, p2build: (B) -> A =>
            { focus: B => p1build(p2build(focus)) }
        }
    }

    // 4 <Opitonal, Optional> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryAffines<S>, _: RegistryAffines<A>) {
        { o1preview: (S) -> Either<S, A>, o2preview: (A) -> Either<A, B>, _: (S, A) -> S, _: (A, B) -> A =>
            { source: S => 
                if (let Right(prv1) <- o1preview(source) && let Right(res) <- o2preview(prv1)) {
                    Right<S, B>(res)
                } else {
                    Left<S, B>(source)
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryAffines<S>, _: RegistryAffines<A>) {
        { p1preview: (S) -> Either<S, A>, p2preview: (A) -> Either<A, B>, p1update: (S, A) -> S, p2update: (A, B) -> A =>
            { source: S, focus: B =>  
                if (let Right(v1) <- p1preview(source) && let Right(_) <- p2preview(v1)) {
                    p1update(source, p2update(v1, focus))
                } else {
                    source
                }
            }
        }
    }

    public static func composeForward<S, A, B>(_: RegistrySetters<S>, _:RegistrySetters<A>) {
        { _: (S) -> S, s2modifyId: (A) -> A, s1modify: (S, (A) -> A) -> S, _: (A, (B) -> B) -> A =>
            {
                source: S => s1modify(source, s2modifyId)
            }
        }
    }

    public static func composeBackward<S, A, B>(_: RegistrySetters<S>, _: RegistrySetters<A>) {
        { _: (S) -> S, _: (A) -> A, s1modify: (S, (A) -> A) -> S, s2modify: (A, (B) -> B) -> A =>
            {
                source: S, modifier: (B) -> B => 
                    let s2modify_curried_flipped: ((B) -> B) -> (A) -> A = { modifier_: (B) -> B => 
                        { source_: A => s2modify(source_, modifier_ ) }
                    }
                s1modify(source, s2modify_curried_flipped(modifier))
            }
        }
    }

    // 6 <Iso, Lens> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryIsos<S>, _: RegistryLenses<A>) {
        { i1to: (S) -> A, l2view: (A) -> B, _: (A) -> S, _: (A, B) -> A =>
            { source: S => l2view(i1to(source)) }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryIsos<S>, _: RegistryLenses<A>) {
        { i1to: (S) -> A, _: (A) -> B, i1from: (A) -> S, l2update: (A, B) -> A =>
            { source: S, focus: B => i1from(l2update(i1to(source), focus)) }
        }
    }

    // 7 <Lens, Iso> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryLenses<S>, _: RegistryIsos<A>) {
        { l1view: (S) -> A, i2to: (A) -> B, _: (S, A) -> S, _: (B) -> A =>
            { source: S => i2to(l1view(source)) }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryLenses<S>, _: RegistryIsos<A>) {
        { _: (S) -> A, _: (A) -> B, l1update: (S, A) -> S, i2from: (B) -> A =>
            { source: S, focus: B => l1update(source, i2from(focus)) }
        }
    }


    // 8 <Iso, Prism> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryIsos<S>, _: RegistryPrisms<A>) {
        { i1to: (S) -> A, p2preview: (A) -> Either<A, B>, _: (A) -> S, _: (B) -> A =>
            { source: S => 
                if (let Right(prv2) <- p2preview(i1to(source))) {
                    Right<S, B>(prv2)
                } else {
                    Left<S, B>(source)
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryIsos<S>, _: RegistryPrisms<A>) {
        { _: (S) -> A, _: (A) -> Either<A, B>, i1from: (A) -> S, p2build: (B) -> A =>
            { focus: B => i1from(p2build(focus)) }
        }
    }

    // 9 <Prism, Iso> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryPrisms<S>, _: RegistryIsos<A>) {
        { p1preview: (S) -> Either<S, A>, i2to: (A) -> B, _: (A) -> S, _: (B) -> A =>
            { source: S => 
                if (let Right(prv1) <- p1preview(source)) {
                    Right<S, B>(i2to(prv1))
                } else {
                    Left<S, B>(source)
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryPrisms<S>, _: RegistryIsos<A>) {
        { _: (S) -> Either<S, A>, _: (A) -> B, p1build: (A) -> S, i2from: (B) -> A =>
            { focus: B => p1build(i2from(focus)) }
        }
    }

    // 10 <Prism, Lens> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryPrisms<S>, _: RegistryLenses<A>) {
        { p1preview: (S) -> Either<S, A>, l2view: (A) -> B, _: (A) -> S, _: (A, B) -> A =>
            { source: S => 
                if (let Right(prv1) <- p1preview(source)) {
                    Right<S, B>(l2view(prv1))
                } else {
                    Left<S, B>(source)
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryPrisms<S>, _: RegistryLenses<A>) {
        { p1preview: (S) -> Either<S, A>, _: (A) -> B, p1build: (A) -> S, l2update: (A, B) -> A =>
            { source: S, focus: B =>  
                if (let Right(v1) <- p1preview(source)) {
                    p1build(l2update(v1, focus))
                } else {
                    source
                }
            }
        }
    }

    // 11 <Lens, Prism> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryLenses<S>, _: RegistryPrisms<A>) {
        { l1view: (S) -> A, p2preview: (A) -> Either<A, B>, _: (S, A) -> S, _: (B) -> A =>
            { source: S => 
                if (let Right(prv2) <- p2preview(l1view(source))) {
                    Right<S, B>(prv2)
                } else {
                    Left<S, B>(source)
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryLenses<S>, _: RegistryPrisms<A>) {
        { l1view: (S) -> A, p2preview: (A) -> Either<A, B>, l1update: (S, A) -> S, p2build: (B) -> A =>
            { source: S, focus: B =>  
                // if (let Right(_) <- p2preview(l1view(source))) {
                //     l1update(source, p2build(focus))
                // } else {
                //     source
                // }
                l1update(source, p2build(focus))
            }
        }
    }

    // 12 <Iso, Option> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryIsos<S>, _: RegistryAffines<A>) {
        { i1to: (S) -> A, p2preview: (A) -> Either<A, B>, _: (A) -> S, _: (A, B) -> A =>
            { source: S => 
                if (let Right(prv2) <- p2preview(i1to(source))) {
                    Right<S, B>(prv2)
                } else {
                    Left<S, B>(source)
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryIsos<S>, _: RegistryAffines<A>) {
        { i1to: (S) -> A, o2preview: (A) -> Either<A, B>, i1from: (A) -> S, o2update: (A, B) -> A =>
            { source: S, focus: B =>  
                let t = i1to(source)
                if (let Right(_) <- o2preview(t)) {
                    i1from(o2update(t, focus))
                } else {
                    source
                }
            }
        }
    }

    // 13 <Option, Iso> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryAffines<S>, _: RegistryIsos<A>) {
        { o1preview: (S) -> Either<S, A>, i2to: (A) -> B, _: (S, A) -> S, _: (B) -> A =>
            { source: S => 
                if (let Right(prv1) <- o1preview(source)) {
                    Right<S, B>(i2to(prv1))
                } else {
                    Left<S, B>(source)
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryAffines<S>, _: RegistryIsos<A>) {
        { o1preview: (S) -> Either<S, A>, _: (A) -> B, o1update: (S, A) -> S, i2from: (B) -> A =>
            { source: S, focus: B =>  
                if (let Right(_) <- o1preview(source)) {
                    o1update(source, i2from(focus))
                } else {
                    source
                }
            }
        }
    }

    // 14 <Iso, Setter>
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryIsos<S>, _: RegistrySetters<A>) {
        { i1to: (S) -> A, s2modifyId: (A) -> A, i1from: (A) -> S, _: (A, (B) -> B) -> A  => 
            { source: S =>
                i1from(s2modifyId(i1to(source)))
            }
        } 
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryIsos<S>, _: RegistrySetters<A>) {
        { i1to: (S) -> A, _: (A) -> A, i1from: (A) -> S, s2modify: (A, (B) -> B) -> A  => 
            { source: S, modifier: (B) -> B =>
                i1from(s2modify(i1to(source), modifier))
            }
        } 
    }

    // 15 <Setter, Iso>
    @Frozen
    public static func composeForward<S, A, B>(_: RegistrySetters<S>, _: RegistryIsos<A>) {
        { s1modifyId: (S) -> S, _: (A) -> B, _: (S, (A) -> A) -> S, _: (B) -> A => 
            s1modifyId
        } 
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistrySetters<S>, _: RegistryIsos<A>) {
        { _: (S) -> S, i2to: (A) -> B, s1modify: (S, (A) -> A) -> S, i2from: (B) -> A => 
            { source: S, modifier: (B) -> B =>
                let composed: (A) -> A = { source_: A => i2from(modifier(i2to(source_))) }
                s1modify(source, composed)
            }
        } 
    }


    // 16 <Lens, Option> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryLenses<S>, _: RegistryAffines<A>) {
        { l1view: (S) -> A, o2preview: (A) -> Either<A, B>, _: (S, A) -> S, _: (A, B) -> A =>
            { source: S => 
                if (let Right(prv2) <- o2preview(l1view(source))) {
                    Right<S, B>(prv2)
                } else {
                    Left<S, B>(source)
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryLenses<S>, _: RegistryAffines<A>) {
        { l1view: (S) -> A, o2preview: (A) -> Either<A, B>, l1update: (S, A) -> S, o2update: (A, B) -> A =>
            { source: S, focus: B =>  
                let t = l1view(source)
                if (let Right(_) <- o2preview(t)) {
                    l1update(source, o2update(t, focus))
                } else {
                    source
                }
            }
        }
    }

    // 17 <Prism, Option> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryPrisms<S>, _: RegistryAffines<A>) {
        { p1preview: (S) -> Either<S, A>, o2preview: (A) -> Either<A, B>, _: (A) -> S, _: (A, B) -> A =>
            { source: S => 
                if (let Right(prv1) <- p1preview(source) && let Right(res) <- o2preview(prv1)) {
                    Right<S, B>(res)
                } else {
                    Left<S, B>(source)
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryPrisms<S>, _: RegistryAffines<A>) {
        { p1preview: (S) -> Either<S, A>, o2preview: (A) -> Either<A, B>, p1build: (A) -> S, o2update: (A, B) -> A =>
            { source: S, focus: B =>  
                if (let Right(v1) <- p1preview(source) && let Right(_) <- o2preview(v1)) {
                    p1build(o2update(v1, focus))
                } else {
                    source
                }
            }
        }
    }

    // 18 <Option, Lens> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryAffines<S>, _: RegistryLenses<A>) {
        { o1preview: (S) -> Either<S, A>, l2view: (A) -> B, _: (S, A) -> S, _: (A, B) -> A =>
            { source: S => 
                if (let Right(prv1) <- o1preview(source)) {
                    Right<S, B>(l2view(prv1))
                } else {
                    Left<S, B>(source)
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryAffines<S>, _: RegistryLenses<A>) {
        { o1preview: (S) -> Either<S, A>, _: (A) -> B, o1update: (S, A) -> S, l2update: (A, B) -> A =>
            { source: S, focus: B =>  
                if (let Right(v1) <- o1preview(source)) {
                    o1update(source, l2update(v1, focus))
                } else {
                    source
                }
            }
        }
    }

    // 19 <Option, Prism> +++
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryAffines<S>, _: RegistryPrisms<A>) {
        { o1preview: (S) -> Either<S, A>, p2preview: (A) -> Either<A, B>, _: (S, A) -> S, _: (B) -> A =>
            { source: S => 
                if (let Right(prv1) <- o1preview(source) && let Right(res) <- p2preview(prv1)) {
                    Right<S, B>(res)
                } else {
                    Left<S, B>(source)
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryAffines<S>, _: RegistryPrisms<A>) {
        { o1preview: (S) -> Either<S, A>, p2preview: (A) -> Either<A, B>, o1update: (S, A) -> S, p2build: (B) -> A =>
            { source: S, focus: B =>  
                // if (let Right(v1) <- o1preview(source) && let Right(_) <- p2preview(v1)) {
                //     o1update(source, p2build(focus))
                // } else {
                //     source
                // }
                if (let Right(v1) <- o1preview(source)) {
                    o1update(source, p2build(focus))
                } else {
                    source
                }
            }
        }
    }

    // 20 <Lens, Setter>
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryLenses<S>, _: RegistrySetters<A>) {
        { l1view: (S) -> A, s2modifyId: (A) -> A, l1update: (S, A) -> S, _: (A, (B) -> B) -> A =>
            { source: S =>  
                l1update(source, s2modifyId(l1view(source)))
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryLenses<S>, _: RegistrySetters<A>) {
        { l1view: (S) -> A, _: (A) -> A, l1update: (S, A) -> S, s2modify: (A, (B) -> B) -> A =>
            { source: S, modifier: (B) -> B =>  
                l1update(source, s2modify(l1view(source), modifier))
            }
        }
    }
    // 21 <Setter, Lens>
    @Frozen
    public static func composeForward<S, A, B>(_: RegistrySetters<S>, _: RegistryLenses<A>) {
        { s1modifyId: (S) -> S, _: (A) -> B, _: (S, (A) -> A) -> S, _: (A, B) -> A =>
            s1modifyId
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistrySetters<S>, _: RegistryLenses<A>) {
        { _: (S) -> S, l2view: (A) -> B, s1modify: (S, (A) -> A) -> S, l2update: (A, B) -> A =>
            { source: S, modifier: (B) -> B =>  
                let composed: (A) -> A = { source_: A => l2update(source_, modifier(l2view(source_))) }
                s1modify(source, composed)
            }
        }
    }
    // 22 <Prism, Setter>
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryPrisms<S>, _: RegistrySetters<A>) {
        { p1preview: (S) -> Either<S, A>, s2modifyId: (A) -> A, p1build: (A) -> S, _: (A, (B) -> B) -> A =>
            { source: S  =>
                if (let Right(v1) <- p1preview(source)) {
                    p1build(s2modifyId(v1))
                } else {
                    source
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryPrisms<S>, _: RegistrySetters<A>) {
        { p1preview: (S) -> Either<S, A>, _: (A) -> A, p1build: (A) -> S, s2modify: (A, (B) -> B) -> A =>
            { source: S, modifier: (B) -> B =>
                if (let Right(v1) <- p1preview(source)) {
                    p1build(s2modify(v1, modifier))
                } else {
                    source
                }
            }
        }
    }
    // 23 <Setter, Prism>
    @Frozen
    public static func composeForward<S, A, B>(_: RegistrySetters<S>, _: RegistryPrisms<A>) {
        { s1modifyId: (S) -> S, p2preview: (A) -> Either<A, B>, _: (S, (A) -> A) -> S, p2build: (B) -> A =>
            s1modifyId
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistrySetters<S>, _: RegistryPrisms<A>) {
        { _: (S) -> S, p2preview: (A) -> Either<A, B>, s1modify: (S, (A) -> A) -> S, p2build: (B) -> A =>
            { source: S, modifier: (B) -> B =>  
                let composed: (A) -> A = { source_: A =>
                    if (let Right(v2) <- p2preview(source_)) {
                        p2build(modifier(v2))
                    } else { source_ }
                }
                s1modify(source, composed)
            }
        }
    }
    // 24 <Optional, Setter>
    @Frozen
    public static func composeForward<S, A, B>(_: RegistryAffines<S>, _: RegistrySetters<A>) {
        { o1preview: (S) -> Either<S, A>, s2modifyId: (A) -> A, o1update: (S, A) -> S, _: (A, (B) -> B) -> A =>
            { source: S =>
                if (let Right(v1) <- o1preview(source)) {
                    o1update(source, s2modifyId(v1))
                } else {
                    source
                }
            }
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistryAffines<S>, _: RegistrySetters<A>) {
        { o1preview: (S) -> Either<S, A>, _: (A) -> A, o1update: (S, A) -> S, s2modify: (A, (B) -> B) -> A =>
            { source: S, modifier: (B) -> B =>
                if (let Right(v1) <- o1preview(source)) {
                    o1update(source, s2modify(v1, modifier))
                } else {
                    source
                }
            }
        }
    }
    // 25 <Setter, Optional>
    @Frozen
    public static func composeForward<S, A, B>(_: RegistrySetters<S>, _: RegistryAffines<A>) {
        { s1modifyId: (S) -> S, _: (A) -> Either<A, B>, _: (S, (A) -> A) -> S, _: (A, B) -> A =>
            s1modifyId
        }
    }
    @Frozen
    public static func composeBackward<S, A, B>(_: RegistrySetters<S>, _: RegistryAffines<A>) {
        { _: (S) -> S, o2preview: (A) -> Either<A, B>, s1modify: (S, (A) -> A) -> S, o2update: (A, B) -> A =>
            { source: S, modifier: (B) -> B =>  
                let composed: (A) -> A = { source_: A =>
                    if (let Right(v2) <- o2preview(source_)) {
                        o2update(source_, modifier(v2))
                    } else { source_ }
                }
                s1modify(source, composed)
            }
        }
    }

    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryIsos<S>,    _: RegistryIsos<A>): RegistryIsos<S>    { RegistryIsos() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryLenses<S>,    _: RegistryLenses<A>): RegistryLenses<S>    { RegistryLenses() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryPrisms<S>,    _: RegistryPrisms<A>): RegistryPrisms<S>    { RegistryPrisms() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryAffines<S>, _: RegistryAffines<A>): RegistryAffines<S> { RegistryAffines() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistrySetters<S>, _: RegistrySetters<A>): RegistryAffines<S> { RegistryAffines() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryLenses<S>,    _: RegistryPrisms<A>): RegistryAffines<S> { RegistryAffines() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryPrisms<S>,    _: RegistryLenses<A>): RegistryAffines<S> { RegistryAffines() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryLenses<S>,    _: RegistryAffines<A>): RegistryAffines<S> { RegistryAffines() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryPrisms<S>,    _: RegistryAffines<A>): RegistryAffines<S> { RegistryAffines() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryAffines<S>, _: RegistryLenses<A>): RegistryAffines<S> { RegistryAffines() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryAffines<S>, _: RegistryPrisms<A>): RegistryAffines<S> { RegistryAffines() }

    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryLenses<S>,    _: RegistryIsos<A>): RegistryLenses<S> { RegistryLenses() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryPrisms<S>,    _: RegistryIsos<A>): RegistryPrisms<S> { RegistryPrisms() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryAffines<S>, _: RegistryIsos<A>): RegistryAffines<S> { RegistryAffines() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryIsos<S>,       _: RegistryLenses<A>): RegistryLenses<S> { RegistryLenses() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryIsos<S>,       _: RegistryPrisms<A>): RegistryPrisms<S> { RegistryPrisms() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryIsos<S>,       _: RegistryAffines<A>): RegistryAffines<S> { RegistryAffines() }

    @Frozen
    public static func opticsUpcast<S, A>(_: RegistrySetters<S>, _: RegistryIsos<A>): RegistrySetters<S> { RegistrySetters() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistrySetters<S>, _: RegistryPrisms<A>): RegistrySetters<S> { RegistrySetters() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistrySetters<S>, _: RegistryLenses<A>): RegistrySetters<S> { RegistrySetters() }
    @Frozen
    public static func opticsUpcast<S, A>(_: RegistrySetters<S>, _: RegistryAffines<A>): RegistrySetters<S> { RegistrySetters() }

    @Frozen
    public static func opticsUpcast<S, A>(_: RegistryIsos<S>, _: RegistrySetters<A>): RegistrySetters<S> { RegistrySetters() }
    @Frozen                                      
    public static func opticsUpcast<S, A>(_: RegistryPrisms<S>, _: RegistrySetters<A>): RegistrySetters<S> { RegistrySetters() }
    @Frozen                                      
    public static func opticsUpcast<S, A>(_: RegistryLenses<S>, _: RegistrySetters<A>): RegistrySetters<S> { RegistrySetters() }
    @Frozen                                      
    public static func opticsUpcast<S, A>(_: RegistryAffines<S>, _: RegistrySetters<A>): RegistrySetters<S> { RegistrySetters() }

}
// Testing idea