import SwiftUI

extension Binding {
    /// Whether the value is present; setting false clears it, so an alert's dismissal resets its source.
    func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { isPresented in
                if !isPresented {
                    wrappedValue = nil
                }
            }
        )
    }
}
