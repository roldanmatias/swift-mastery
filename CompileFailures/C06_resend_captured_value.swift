// expect: sending 'draft' risks causing data races
// flags: -swift-version 6
final class ReservationDraft { var notes: [String] = [] }
actor ReservationOutbox {
    var pending: [ReservationDraft] = []
    func submit(_ draft: sending ReservationDraft) { pending.append(draft) }
}
// Captured values belong to the closure's region (a closure may run more than once).
func forward(_ draft: sending ReservationDraft, to outbox: ReservationOutbox) -> Task<Void, Never> {
    Task { await outbox.submit(draft) }
}
