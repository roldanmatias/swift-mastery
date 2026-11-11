// expect: call to main actor-isolated global function 'unregister' in a synchronous nonisolated context
// flags: -swift-version 6
@MainActor func unregister(_ id: Int) {}
@MainActor final class PhotoUploadSession {
    let id = 1
    deinit { unregister(id) }       // fix: `isolated deinit`
}
