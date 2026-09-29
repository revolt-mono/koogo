import Observation
import Sparkle

@MainActor
@Observable
final class UpdateModel: NSObject {
    @ObservationIgnored
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    private(set) var isUpdateAvailable = false

    /// Debug builds always show the indicator so the toolbar can be checked without a pending update.
    var showsUpdateIndicator: Bool {
        #if DEBUG
        true
        #else
        isUpdateAvailable
        #endif
    }

    /// Starts scheduled update checks. Only the signed app bundle carries the Sparkle feed and key, so
    /// the app calls this once at launch and tests never do.
    func start() {
        updaterController.startUpdater()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

extension UpdateModel: @MainActor SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem,
        andInImmediateFocus _: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate _: SUAppcastItem,
        state _: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else {
            return
        }
        isUpdateAvailable = true
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        isUpdateAvailable = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        isUpdateAvailable = false
    }
}
