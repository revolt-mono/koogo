import os

extension Logger {
    private static let subsystem = "com.revolt.koogo"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let usage = Logger(subsystem: subsystem, category: "usage")
    static let quota = Logger(subsystem: subsystem, category: "quota")
    static let activity = Logger(subsystem: subsystem, category: "activity")
}
