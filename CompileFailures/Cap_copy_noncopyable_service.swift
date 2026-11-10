// expect: used after consume
struct Service: ~Copyable { var n = 0 }
func use(_ s: borrowing Service) {}
func f() { let service = Service(); let copy = service; use(service); use(copy) }
