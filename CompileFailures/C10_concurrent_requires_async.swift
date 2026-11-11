// expect: cannot use @concurrent on non-async global function 'checksum'
// flags: -swift-version 6
@concurrent func checksum(_ bytes: [UInt8]) -> Int { bytes.reduce(0) { $0 &+ Int($1) } }
