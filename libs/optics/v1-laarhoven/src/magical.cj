package lucida

public struct Magical<T> {}

@Frozen
public func magic<T>(_: T): Magical<T> {
    Magical()
}