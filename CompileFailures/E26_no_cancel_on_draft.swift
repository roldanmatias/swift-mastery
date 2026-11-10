// expect: has no member 'cancel'
struct Draft: ~Copyable {}
func f() { let d = Draft(); d.cancel() }
