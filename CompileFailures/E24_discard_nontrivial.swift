// expect: trivially-destroyed stored properties
final class Registry {}
struct Lock: ~Copyable { let registry: Registry; deinit {}; consuming func release() { discard self } }
