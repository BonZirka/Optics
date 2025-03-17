# Optical shenanigans

Trying to do the most primitive kind of optics there's known to the humatity: get + set

I don't want to go anywhere further than lenses for now

```cangjie
public struct ValueLens<S, A> <: Lens<S, A> {

    public ValueLens(
        private let _getter: (S) -> A,
        private let _setter: (S, A) -> S
    ) {}

    public prop getter: (S) -> A {
        get() {
            _getter
        }
    }

    public prop setter: (S, A) -> S {
        get() {
           _setter 
        }
    }
}
```
