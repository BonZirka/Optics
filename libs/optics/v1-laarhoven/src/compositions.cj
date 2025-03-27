package lucida

import macro_test_utils.GenerateComposeFuncDecls

@Frozen
public func composeFunc < X0, X1, X2 >(x0:(X0) ->(X1), x1:(X1) -> X2):(X0) -> X2 {
    { input: X0 => x1(x0(input)) }
}

@GenerateComposeFuncDecls(26)