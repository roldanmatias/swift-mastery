// Ex 08 — Escaping closures and capture lists.

import Foundation

enum E08 {
    final class ImageLoader {
        private var completions: [(Data) -> Void] = []

        func load(_ url: URL, completion: @escaping (Data) -> Void) {
            completions.append(completion)
        }

        func finishAll(with data: Data) {
            completions.forEach { $0(data) }
            completions.removeAll()
        }

        var pendingCount: Int { completions.count }
    }

    final class ListingDetailModel {
        var title = ""
        var imageData: Data?
        var onChange: (() -> Void)?
        let loader: ImageLoader
        private let url = URL(string: "https://example.com/photo.jpg")!

        init(loader: ImageLoader) {
            self.loader = loader
        }

        /// Step 1 — two retain cycles:
        /// self → onChange → self, and self → loader → completions → self.
        func startLeaking() {
            onChange = { print(self.title) }
            loader.load(url) { data in
                self.imageData = data
            }
        }

        /// Fix A — `[weak self]`: never crashes. If the model is gone, the work is skipped.
        func startWeak() {
            onChange = { [weak self] in
                guard let self else { return }
                print(self.title)
            }
            loader.load(url) { [weak self] data in
                self?.imageData = data
            }
        }

        /// Fix B — `[unowned self]`: no optional, but it crashes if the closure runs
        /// after `self` is deallocated. Only use it when the closure provably can't
        /// outlive `self` (here `onChange` is owned by self, so it's safe;
        /// the loader completion is NOT safe with unowned, so it uses weak).
        func startUnowned() {
            onChange = { [unowned self] in print(self.title) }
            loader.load(url) { [weak self] data in self?.imageData = data }
        }

        /// Fix C — capture only what you need. `title` is captured as a *value*
        /// at creation time; self isn't captured at all.
        func startCapturingValues() -> () -> String {
            let closure = { [title] in "Loading \(title)" }
            onChange = { [loader] in _ = loader.pendingCount }
            return closure
        }
    }

    /// Step 3 — a closure captures the *variable* (a reference to its box);
    /// a capture-list entry captures the *value* at creation time.
    static func captureSemantics() -> (byReference: Int, snapshot: Int) {
        var price = 100
        let byReference = { price }
        let snapshot = { [price] in price }
        price = 200
        return (byReference(), snapshot())
    }

    /// Step 4 — `withoutActuallyEscaping`: lets a non-escaping closure be used
    /// where the type system wants `@escaping` (here, a lazy filter stores its
    /// predicate). The contract: the closure must not actually escape, i.e.
    /// the lazy sequence must not outlive this call. It's checked at runtime
    /// and traps if the closure is still referenced when the block returns.
    static func countMatches(_ values: [Int], where predicate: (Int) -> Bool) -> Int {
        withoutActuallyEscaping(predicate) { escapable in
            values.lazy.filter(escapable).count
        }
    }
}
