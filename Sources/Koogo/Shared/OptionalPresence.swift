extension Optional {
    /// Binds `isPresented:` to an optional: dismissing clears the value.
    var isPresent: Bool {
        get { self != nil }
        set {
            if !newValue {
                self = nil
            }
        }
    }
}
