// expect: passing closure as a 'sending' parameter risks causing data races
// flags: -swift-version 6
final class ReservationDraft { var notes: [String] = [] }
// Without `sending`, the caller still owns `draft` and could use it concurrently.
func annotateInBackground(_ draft: ReservationDraft) -> Task<Void, Never> {
    Task { draft.notes.append("checked") }
}
