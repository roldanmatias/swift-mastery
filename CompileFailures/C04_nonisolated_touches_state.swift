// expect: actor-isolated property 'messages' can not be referenced from a nonisolated context
// flags: -swift-version 6
actor HostInbox {
    var messages: [String] = []
    nonisolated var summary: String { "\(messages.count) messages" }
}
