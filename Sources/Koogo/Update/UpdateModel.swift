import Observation
import Sparkle

/// app-scoped; the app starts the updater once at launch.
@MainActor
@Observable
final class UpdateModel: NSObject {
  private(set) var isUpdateAvailable = false

  func start() {
    updaterController.startUpdater()
  }

  func checkForUpdates() {
    updaterController.checkForUpdates(nil)
  }

  @ObservationIgnored private lazy var updaterController = SPUStandardUpdaterController(
    startingUpdater: false,
    updaterDelegate: nil,
    userDriverDelegate: self,
  )
}

extension UpdateModel: @MainActor SPUStandardUserDriverDelegate {
  var supportsGentleScheduledUpdateReminders: Bool {
    true
  }

  func standardUserDriverShouldHandleShowingScheduledUpdate(
    _: SUAppcastItem,
    andInImmediateFocus _: Bool,
  ) -> Bool {
    false
  }

  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool,
    forUpdate _: SUAppcastItem,
    state _: SPUUserUpdateState,
  ) {
    if !handleShowingUpdate {
      isUpdateAvailable = true
    }
  }

  func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
    isUpdateAvailable = false
  }

  func standardUserDriverWillFinishUpdateSession() {
    isUpdateAvailable = false
  }
}
