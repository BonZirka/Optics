package lucida

import lucida.macrodsl.*

/*
 * The complete composition/upcast table is generated at compile time by
 * @GenerateCompositions (src/macrodsl/generate_compositions.cj):
 *   - composeForward / composeBackward for all 25 ordered optic-kind pairs,
 *   - opticsUpcast for every ordered pair (both argument orders of the 15
 *     unordered ones). The result is the lattice meet — the weaker, more
 *     partial kind of the two (Iso > {Lens, Prism} > Affine > Setter;
 *     siblings meet at Affine) — the kind of the chain "a then b" and the
 *     registry the next compose row expects.
 *
 * Each generated row mirrors the historically hand-written implementation 1:1.
 * Behavioral parity is gated by the law suite (src/tests/composition_laws.cj,
 * src/tests/composition_property_laws.cj, src/tests/upcast_laws.cj).
 */
@GenerateCompositions
public struct __OpticsCompositions {}
