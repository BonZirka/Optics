package lucida

import lucida_macro.*

/*
 * The complete composition/upcast table is generated at compile time by
 * @GenerateCompositions (libs/macro-optics/v2/src/generate_compositions.cj):
 *   - composeForward / composeBackward for all 25 ordered optic-kind pairs,
 *   - opticsUpcast for all 15 unordered pairs (lattice: Setter < Affine <
 *     {Lens, Prism} < Iso, join(Lens, Prism) = Affine).
 *
 * Each generated row mirrors the historically hand-written implementation 1:1.
 * Behavioral parity is gated by the law suite (src/test/composition_laws.cj
 * and friends in the root package).
 */
@GenerateCompositions
public struct __OpticsCompositions {}
