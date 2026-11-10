// expect: cannot partially consume
struct Lock: ~Copyable {}
struct Hold: ~Copyable { var lock: Lock; deinit {}; consuming func take() -> Lock { lock } }
