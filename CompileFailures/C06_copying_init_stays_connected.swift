// expect: task or actor-isolated value cannot be sent
// flags: -swift-version 6
final class ReservationDraft {
    var notes: [String] = []
    init() {}
    init(copying other: ReservationDraft) { notes = other.notes }
}
actor ReservationOutbox {
    var pending: [ReservationDraft] = []
    // The init takes a non-Sendable argument, so its result is assumed connected to `first`.
    func exportFirst() -> sending ReservationDraft? {
        guard let first = pending.first else { return nil }
        return ReservationDraft(copying: first)
    }
}
