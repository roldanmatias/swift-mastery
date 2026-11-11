// expect: mutation of captured var 'count' in concurrently-executing code
// flags: -swift-version 6
func countInBackground() {
    var count = 0
    let work: @Sendable () -> Void = { count += 1 }
    work()
}
