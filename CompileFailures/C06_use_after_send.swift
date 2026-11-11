// expect: sending 'draft' risks causing data races
// flags: -swift-version 6
final class ReservationDraft { var notes: [String] = [] }
actor ReservationOutbox {
    var pending: [ReservationDraft] = []
    func submit(_ draft: ReservationDraft) { pending.append(draft) }
}
func submitAndEdit(_ outbox: ReservationOutbox) async {
    let draft = ReservationDraft()
    await outbox.submit(draft)        // the draft's region now belongs to the actor
    draft.notes.append("late edit")   // ...so using it here would race
}
