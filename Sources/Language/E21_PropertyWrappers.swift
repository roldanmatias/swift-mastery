// Ex 21 — Property wrappers.

import Foundation

package enum E21 {
    package struct ClampReport<Value: Sendable>: Equatable, Sendable where Value: Equatable {
        package var wasClamped: Bool
        package var lastRawValue: Value?
    }

    /// `@Clamped(1...16) var guests = 20`
    ///
    /// The compiler generates (step 5):
    ///
    ///     private var _guests = Clamped(wrappedValue: 20, 1...16)
    ///     var guests: Int {
    ///         get { _guests.wrappedValue }
    ///         set { _guests.wrappedValue = newValue }
    ///     }
    ///     var $guests: ClampReport<Int> { _guests.projectedValue }
    ///
    /// It's a struct, so it's stored inline and copied with its owner: the
    /// owner keeps value semantics. A class wrapper would make every copy of
    /// the owner share one clamped value.
    @propertyWrapper
    package struct Clamped<Value: Comparable & Sendable>: Sendable {
        private var value: Value
        package let range: ClosedRange<Value>
        package private(set) var projectedValue: ClampReport<Value>

        package init(wrappedValue: Value, _ range: ClosedRange<Value>) {
            self.range = range
            value = Self.clamp(wrappedValue, to: range)
            projectedValue = ClampReport(wasClamped: value != wrappedValue, lastRawValue: wrappedValue)
        }

        package var wrappedValue: Value {
            get { value }
            set {
                value = Self.clamp(newValue, to: range)
                projectedValue = ClampReport(wasClamped: value != newValue, lastRawValue: newValue)
            }
        }

        private static func clamp(_ value: Value, to range: ClosedRange<Value>) -> Value {
            min(max(value, range.lowerBound), range.upperBound)
        }
    }

    // MARK: Composable text wrappers

    /// Composition `@A @B var x: String` produces storage `A<B<String>>`: the
    /// OUTER wrapper's wrapped value is the INNER wrapper. To compose, both
    /// wrappers must be generic over "something that holds text".
    package protocol TextBox: Sendable {
        var text: String { get set }
    }

    @propertyWrapper
    package struct Trimmed<Value: TextBox>: TextBox {
        private var storage: Value

        package init(wrappedValue: Value) {
            storage = wrappedValue
            storage.text = storage.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        package var wrappedValue: Value {
            get { storage }
            set {
                storage = newValue
                storage.text = storage.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        /// RAW access: writes the storage directly, bypassing this wrapper's
        /// own rule. An OUTER wrapper that edits our text therefore isn't
        /// re-checked by us, which is exactly why composition order matters.
        package var text: String {
            get { storage.text }
            set { storage.text = newValue }
        }
    }

    @propertyWrapper
    struct NonEmpty<Value: TextBox>: TextBox {
        static var placeholder: String { "Untitled" }
        private var storage: Value

        init(wrappedValue: Value) {
            storage = wrappedValue
            if storage.text.isEmpty { storage.text = Self.placeholder }
        }

        var wrappedValue: Value {
            get { storage }
            set {
                storage = newValue
                if storage.text.isEmpty { storage.text = Self.placeholder }
            }
        }

        var text: String {
            get { storage.text }
            set { storage.text = newValue }
        }
    }

    /// Step 3 — order matters. Wrappers apply inside-out on init/set, and the
    /// outer wrapper edits the inner one's text through the raw `text` channel:
    /// - `@Trimmed @NonEmpty`: NonEmpty sees "   " (not empty, kept), then
    ///   Trimmed trims it to "" → the result is EMPTY: the outer wrapper broke
    ///   the inner wrapper's invariant.
    /// - `@NonEmpty @Trimmed`: Trimmed makes "", then NonEmpty replaces it
    ///   → "Untitled".
    /// (If `text`'s setter re-applied each wrapper's rule instead, both orders
    /// would give "Untitled". I tried that first, and the test caught it.)
    struct TitleForms {
        @Trimmed @NonEmpty var trimmedOutside: String
        @NonEmpty @Trimmed var nonEmptyOutside: String

        init(_ title: String) {
            trimmedOutside = title
            nonEmptyOutside = title
        }
    }

    package struct GuestRequest: Sendable {
        @Clamped(1...16) package var guests: Int = 1
        @Trimmed package var note: String = ""

        package init(guests: Int, note: String) {
            self.guests = guests
            self.note = note
        }

        /// Exposes the projected value for the tests.
        package var guestsReport: ClampReport<Int> { $guests }
    }

    /// Step 4 — wrapper on a function parameter (SE-0293). The argument is
    /// passed through `Trimmed(wrappedValue:)` on entry. `$title` would only
    /// exist if `Trimmed` had a `projectedValue`.
    static func rename(@Trimmed _ title: String) -> String {
        title
    }
}

extension String: E21.TextBox {
    package var text: String {
        get { self }
        set { self = newValue }
    }
}
