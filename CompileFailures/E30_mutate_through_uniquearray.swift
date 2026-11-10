// expect: invalid return value from a mutate accessor
struct Tok: ~Copyable { var id: Int }
@available(macOS 27, *) struct P: ~Copyable { var items = UniqueArray<Tok>()
  var first: Tok { borrow { return items[0] } mutate { return &items[0] } } }
