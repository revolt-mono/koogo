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

    /// Prompts the user when trust is missing; a grant arrives through `changes`.
    static func request() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }
}
