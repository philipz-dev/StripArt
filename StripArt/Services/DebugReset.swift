#if DEBUG
import Foundation

/// Resets local test state so the app behaves like a fresh install.
///
/// StoreKit sandbox transaction reset belongs in a unit-test target (StoreKitTest
/// pulls in XCTest and cannot be linked into the app). For manual testing, use
/// Xcode's StoreKit Configuration file on the run scheme instead.
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

        await store.refreshEntitlements()
    }
}
#endif
