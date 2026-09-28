struct ClaudeQuotaSnapshot: Equatable, Sendable, Encodable {
    let account: QuotaLimits?
    let models: [ModelQuotaLimits]

    init?(account: QuotaLimits?, models: [ModelQuotaLimits]) {
        guard account != nil || !models.isEmpty else { return nil }
        self.account = account
        self.models = models
    }
}
