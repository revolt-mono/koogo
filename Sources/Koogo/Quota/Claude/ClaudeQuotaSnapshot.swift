import Foundation

struct ClaudeQuotaSnapshot: Equatable, Sendable, Encodable {
    struct Model: Equatable, Identifiable, Sendable, Encodable {
        let title: String
        let weekly: QuotaWindow

        var id: String { title }
    }

    let session: QuotaWindow?
    let weekly: QuotaWindow?
    let models: [Model]

    init?(session: QuotaWindow?, weekly: QuotaWindow?, models: [Model]) {
        guard session != nil || weekly != nil || !models.isEmpty else { return nil }
        self.session = session
        self.weekly = weekly
        self.models = models
    }
}
