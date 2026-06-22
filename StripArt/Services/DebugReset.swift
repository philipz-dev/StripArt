#if DEBUG
import StoreKitTest

/// Resets local test state so the app behaves like a fresh install.
enum DebugReset {
    @MainActor
    static func performFullReset(store: StoreManager, viewModel: StripArtViewModel) async {
        UserDefaults.standard.removeObject(forKey: "freeExportsUsed")
        UserDefaults.standard.removeObject(forKey: "hideTipsOnPhotoAction")

        viewModel.resetTestingState()
        store.purchaseError = nil
        viewModel.showPaywall = false

        if let session = try? SKTestSession(configurationFileNamed: "StripArt") {
            session.clearTransactions()
            try? session.resetToDefaultState()
        }

        await store.refreshEntitlements()
    }
}
#endif
