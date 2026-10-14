extension FixedWidthInteger where Self: UnsignedInteger {
    func checkedAdding(_ other: Self) -> Self? {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? nil : sum
    }

    func saturatingAdding(_ other: Self) -> Self {
        checkedAdding(other) ?? .max
    }
}
