extension Optional {
    /// dismissing an optional-backed presentation clears the value.
    var isPresent: Bool {
        get { self != nil }
        set {
            if !newValue {
                self = nil
            }
        }
    }
}
