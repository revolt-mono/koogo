@preconcurrency import ApplicationServices
import Foundation

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Posted whenever any app's Accessibility trust changes.
    static var changes: NotificationCenter.Notifications {
        DistributedNotificationCenter.default().notifications(named: Notification.Name("com.apple.accessibility.api"))
    }

    /// Prompts the user when trust is missing and returns the trust at the time of the call.
    static func request() -> Bool {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }
}
