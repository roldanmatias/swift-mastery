// expect: cannot return a ~Escapable result
func makeSpan() -> Span<Double> { let a = [1.0, 2.0]; return a.span }
