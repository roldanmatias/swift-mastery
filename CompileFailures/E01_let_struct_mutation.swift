// expect: cannot use mutating member on immutable value
struct Gallery { var urls: [Int] = [] }

struct Listing { var gallery = Gallery() }

func f() {
    let fixed = Listing();
    fixed.gallery.urls.append(1)
}
