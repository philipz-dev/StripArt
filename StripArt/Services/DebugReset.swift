#if DEBUG
import StoreKitTest

/// Resets local test state so the app behaves like a fresh install.
enum DebugReset {
    @MainActor
    static func performFullReset(store: StoreManager, viewModel: StripArtViewModel, gallery: GalleryStore) async {
        UserDefaults.standard.removeObject(forKey: "freeExportsUsed")
        UserDefaults.standard.removeObject(forKey: "hideTipsOnPhotoAction")
        UserDefaults.standard.removeObject(forKey: "hasSeenStartupAnimation")

        viewModel.resetTestingState()
        gallery.removeAllForTesting()
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
