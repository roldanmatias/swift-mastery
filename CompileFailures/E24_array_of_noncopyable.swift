// expect: does not conform to protocol 'Copyable'
struct Lock: ~Copyable {}
let locks: [Lock] = []
