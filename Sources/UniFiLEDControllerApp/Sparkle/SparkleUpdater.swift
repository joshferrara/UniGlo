import Foundation
import Sparkle

@MainActor
final class SparkleUpdater: NSObject, ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    override init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    @objc
    func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }
}
