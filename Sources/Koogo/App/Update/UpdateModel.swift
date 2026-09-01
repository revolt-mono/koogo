import Observation
import Sparkle

@MainActor
@Observable
final class UpdateModel: NSObject {
    @ObservationIgnored
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    private(set) var isUpdateAvailable = false

    override init() {
        super.init()
        _ = updaterController
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
