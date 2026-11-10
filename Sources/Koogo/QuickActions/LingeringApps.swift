import Foundation

/// an app that quit while processes it spawned or helper apps it opened keep running; macos 27 keeps such an app in
/// the dock as running in background.
struct LingeringApp: Sendable {
    /// launch services serial number, an immutable cf object.
    fileprivate nonisolated(unsafe) let serialNumber: CFTypeRef
    let name: String
    fileprivate let processes: [(identity: ProcessIdentity, name: String)]

    /// nil without a process left to stop, and for an app koogo runs under, since stopping that app stops koogo.
    init?(serialNumber: CFTypeRef, name: String, processes: [(identity: ProcessIdentity, name: String)]) {
        guard
            !processes.isEmpty,
            !processes.contains(where: { $0.identity.pid == ProcessInfo.processInfo.processIdentifier })
        else { return nil }
        self.serialNumber = serialNumber
        self.name = name
        self.processes = processes
    }
}

struct LingeringApps: Sendable {
    enum Failure: LocalizedError {
        case scan
        case termination(LingeringApp)

        var errorDescription: String? {
            switch self {
            case .scan: "Could not read lingering apps."
            case .termination(let app): "Could not stop \(app.name)."
            }
        }
    }

    let values: [LingeringApp]

    init?(_ apps: [LingeringApp]) {
        guard !apps.isEmpty else {
            return nil
        }
        values = apps
    }

    var summary: String {
        values.map { app in
            "\(app.name) (\(Set(app.processes.map(\.name)).sorted().joined(separator: ", ")))"
        }
        .joined(separator: ", ")
    }

    @concurrent
    func forceTerminate() async throws {
        for process in values.flatMap(\.processes) {
            // a process that survives keeps its app lingering, which the wait below reports.
            try? LibProc.forceKill(process.identity)
        }
        // launch services drops an app a moment after its last process dies.
        let deadline = ContinuousClock.now + .seconds(2)
        while let survivor = values.first(where: Self.isLingering) {
            guard ContinuousClock.now < deadline else { throw Failure.termination(survivor) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

extension LingeringApps {
    private typealias CopyMatchingApplications = @convention(c) (Int32, CFDictionary) -> Unmanaged<CFArray>?
    private typealias CopyApplicationInformationItem =
        @convention(c) (Int32, CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    /// private launch services calls also made by `lsappinfo`; the public running application list drops an app once
    /// it exits.
    private static let copyMatchingApplications = dlsym(dlopen(nil, RTLD_NOW), "_LSCopyMatchingApplications")
        .map { unsafeBitCast($0, to: CopyMatchingApplications.self) }
    private static let copyApplicationInformationItem =
        dlsym(dlopen(nil, RTLD_NOW), "_LSCopyApplicationInformationItem")
        .map { unsafeBitCast($0, to: CopyApplicationInformationItem.self) }
    private static let currentSession: Int32 = -2
    private static let lingering =
        "LSApplicationExitedButHasRemainingCoalitionPIDsOrNonForegroundChildrenApplicationsKey"

    /// agents and background-only apps that exit with leftovers linger too, but never show in the dock.
    @concurrent
    static func running() async throws -> LingeringApps? {
        guard let copyMatchingApplications, copyApplicationInformationItem != nil else { throw Failure.scan }
        let query: [String: Any] = [
            "LSApplicationCopyMatchingApplicationsIncludeExitedApplicationsKey": true,
            lingering: true,
            "ApplicationType": "Foreground",
        ]
        // no match comes back as a missing array.
        let serialNumbers =
            copyMatchingApplications(currentSession, query as CFDictionary)?.takeRetainedValue() as? [CFTypeRef] ?? []
        return LingeringApps(serialNumbers.compactMap(lingeringApp))
    }

    private static func lingeringApp(_ serialNumber: CFTypeRef) -> LingeringApp? {
        guard let name = item("LSDisplayName", of: serialNumber) as? String else { return nil }
        return LingeringApp(
            serialNumber: serialNumber,
            name: name,
            processes: remainingPIDs(of: serialNumber).compactMap { pid in
                guard let identity = LibProc.identity(of: pid), let path = LibProc.executablePath(of: pid) else {
                    return nil
                }
                return (identity, (path as NSString).lastPathComponent)
            }
        )
    }

    /// what keeps an exited app listed: the rest of its coalition, and the coalitions of the agents and
    /// background-only apps it opened.
    private static func remainingPIDs(of serialNumber: CFTypeRef) -> [pid_t] {
        let opened = item("LSApplicationChildApplicationASNsArrayKey", of: serialNumber) as? [CFTypeRef] ?? []
        let helpers = opened.filter { item("ApplicationType", of: $0) as? String != "Foreground" }
        return ([serialNumber] + helpers).flatMap { item("LSApplicationCoalitionPIDsKey", of: $0) as? [pid_t] ?? [] }
    }

    private static func isLingering(_ app: LingeringApp) -> Bool {
        item(lingering, of: app.serialNumber) as? Bool == true
    }

    private static func item(_ key: String, of serialNumber: CFTypeRef) -> CFTypeRef? {
        copyApplicationInformationItem?(currentSession, serialNumber, key as CFString)?.takeRetainedValue()
    }
}
