import os

enum Telemetry {
    static let app = Logger(subsystem: "com.revolt.koogo", category: "app")
    static let usage = Logger(subsystem: "com.revolt.koogo", category: "usage")
    static let quota = Logger(subsystem: "com.revolt.koogo", category: "quota")
}
