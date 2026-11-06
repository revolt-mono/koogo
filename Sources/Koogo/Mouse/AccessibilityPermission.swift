@preconcurrency import ApplicationServices
import Foundation

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// rereads trust whenever any app's accessibility trust changes.
    static var changes: some AsyncSequence<Bool, Never> {
        DistributedNotificationCenter.default().notifications(named: Notification.Name("com.apple.accessibility.api"))
            .map { _ in
                // the notification arrives before the trust query reflects the change.
                try? await Task.sleep(for: .milliseconds(250))
                return isTrusted
            }
    }

    /// prompts for missing trust; grants arrive through the change notification.
    static func request() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }
}
