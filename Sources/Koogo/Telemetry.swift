import os

/// Runtime telemetry; stream it with `script/build_and_run.sh telemetry`.
enum Telemetry {
    static let usage = Logger(subsystem: "com.revolt.koogo", category: "usage")
    static let quota = Logger(subsystem: "com.revolt.koogo", category: "quota")
}
