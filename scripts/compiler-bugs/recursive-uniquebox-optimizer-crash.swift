// Swift 6.4.2 optimizer crash (x86_64 and arm64), found while doing Ex 30.
//
//   swiftc -O -parse-as-library -c recursive-uniquebox-optimizer-crash.swift
//
// Assertion failed: (endBit <= T::numCustomBits && "too many/large bit fields
// allocated in function"), function SILBitfield at SILBitfield.h:60.
// While running pass "SwiftArrayPropertyOpt" on the synthesized setter of `next`.
//
// Compiles fine with -Onone. Making `next` a `let` moves the crash to any `var`
// of type `UniqueBox<Node>?` that holds the recursive node.

@available(macOS 27, *)
struct Node: ~Copyable {
    var element: Int
    var next: UniqueBox<Node>?
}
