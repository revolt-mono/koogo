@preconcurrency import ApplicationServices
import Foundation

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// posted whenever any app's accessibility trust changes.
    static var changes: NotificationCenter.Notifications {
        DistributedNotificationCenter.default().notifications(named: Notification.Name("com.apple.accessibility.api"))
    }

    /// prompts for missing trust; grants arrive through the change notification.
    static func request() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }
}
