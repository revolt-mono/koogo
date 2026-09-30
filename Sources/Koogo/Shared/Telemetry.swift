import os

enum Telemetry {
    static let usage = Logger(subsystem: "com.revolt.koogo", category: "usage")
    static let quota = Logger(subsystem: "com.revolt.koogo", category: "quota")
}
