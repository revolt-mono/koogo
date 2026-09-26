import Foundation

/// Why no Grok quota is shown; surfaced in telemetry and the `--report` output.
enum GrokQuotaUnavailability: String, Error, Encodable, Sendable {
    /// No grok.com session in the Grok CLI credentials, e.g. an API-key login.
    case signedOut
    /// Only the Grok CLI refreshes its session, so the quota waits until `grok` runs again.
    case credentialsExpired
    case requestFailed
    case emptyLimits
}

/// Reads the Grok Build credit limit the way `grok`'s `/usage` does, borrowing the CLI's
/// grok.com session read-only.
struct GrokQuotaService: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    private let authURL: URL
    private let transport: Transport

    init(
        authURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".grok/auth.json"),
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.authURL = authURL
        self.transport = transport
    }

    @concurrent
    func fetch() async -> Result<GrokQuotaSnapshot, GrokQuotaUnavailability> {
        let result = await load()
        switch result {
        case .success:
            Telemetry.quota.info("grok fetch available")
        case .failure(let reason):
            Telemetry.quota.info("grok fetch unavailable reason=\(reason.rawValue, privacy: .public)")
        }
        return result
    }

    private func load() async -> Result<GrokQuotaSnapshot, GrokQuotaUnavailability> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard
            let credentials = try? Data(contentsOf: authURL),
            let session = try? decoder.decode(GrokAuthFile.self, from: credentials).session
        else {
            return .failure(.signedOut)
        }
        if let expiresAt = session.expiresAt, expiresAt <= .now {
            return .failure(.credentialsExpired)
        }

        var request = URLRequest(url: Self.billingURL, timeoutInterval: 15)
        request.setValue("Bearer \(session.key)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue(session.userID, forHTTPHeaderField: "x-userid")
        guard
            case let (body, response)? = try? await transport(request),
            let status = (response as? HTTPURLResponse)?.statusCode, 200..<300 ~= status,
            let billing = try? decoder.decode(GrokBillingResponse.self, from: body)
        else {
            return .failure(.requestFailed)
        }
        return billing.snapshot.map(Result.success) ?? .failure(.emptyLimits)
    }
}

/// `auth.json` keys each session by `issuer::client_id`; billing accepts only the grok.com one.
private struct GrokAuthFile: Decodable {
    struct Session: Decodable {
        let key: String
        let userID: String
        let expiresAt: Date?

        private enum CodingKeys: String, CodingKey {
            case key
            case userID = "user_id"
            case expiresAt = "expires_at"
        }
    }

    let session: Session?

    private enum CodingKeys: String, CodingKey {
        case session = "https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828"
    }
}

private struct GrokBillingResponse: Decodable {
    struct Config: Decodable {
        /// proto3 JSON drops zero values, so an untouched quota arrives without this field.
        let creditUsagePercent: Double?
        let currentPeriod: Period?
    }

    struct Period: Decodable {
        let type: String?
        let end: Date?
    }

    let config: Config?

    var snapshot: GrokQuotaSnapshot? {
        guard let config else {
            return nil
        }
        let period: GrokQuotaSnapshot.Period? =
            switch config.currentPeriod?.type {
            case "USAGE_PERIOD_TYPE_WEEKLY": .weekly
            case "USAGE_PERIOD_TYPE_MONTHLY": .monthly
            default: nil
            }
        let usedPercent = min(max(config.creditUsagePercent ?? 0, 0), 100)
        return GrokQuotaSnapshot(
            period: period,
            // Grok floors the used share, so 3.9% used leaves 97%.
            window: QuotaWindow(usedPercent: Int(usedPercent.rounded(.down)), resetsAt: config.currentPeriod?.end)
        )
    }
}
