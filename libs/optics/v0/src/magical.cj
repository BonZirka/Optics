package lucida

public struct Magical<T> {}

@Frozen
public func magic<T, G>(_: Optional<T, G>): Magical<G> {
    Magical()
}