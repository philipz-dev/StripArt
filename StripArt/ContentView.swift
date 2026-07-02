import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = StripArtViewModel()
    @StateObject private var store = StoreManager()
    @StateObject private var gallery = GalleryStore()
    @State private var showGallery = false
    @AppStorage("hasSeenStartupAnimation") private var hasSeenStartupAnimation = false
    @State private var showStartupOverlay = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                screenContent

                if showStartupOverlay {
                    StartupOverlayView {
                        hasSeenStartupAnimation = true
                        withAnimation(.easeOut(duration: 0.45)) {
                            showStartupOverlay = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }

                if viewModel.showSaveConfirmation {
                    SaveSuccessOverlay(
                        remainingFreeExports: viewModel.remainingFreeExports,
                        isUnlocked: store.isUnlocked,
                        store: store,
                        onConfirm: { viewModel.confirmSaveSuccess() }
                    )
                    .transition(.opacity)
                }

                if viewModel.showPaywall {
                    PaywallView(
                        store: store,
                        freeLimit: viewModel.freeExportLimit,
                        onClose: { viewModel.showPaywall = false },
                        onUnlocked: {
                            viewModel.showPaywall = false
                            Task { await viewModel.saveGIF(unlocked: true, gallery: gallery) }
                        }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.screen)
            .animation(.easeInOut(duration: 0.25), value: viewModel.showSaveConfirmation)
            .animation(.easeInOut(duration: 0.25), value: viewModel.showPaywall)
            .animation(.easeOut(duration: 0.45), value: showStartupOverlay)
        }
        .onAppear {
            if !hasSeenStartupAnimation {
                showStartupOverlay = true
            }
            Task { await store.syncEntitlementsWithAppStore() }
        }
        .fullScreenCover(isPresented: $showGallery) {
            GalleryView(gallery: gallery)
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-resetTestingState") {
                await DebugReset.performFullReset(store: store, viewModel: viewModel, gallery: gallery)
            }
        }
        #endif
    }

    @ViewBuilder
    private var screenContent: some View {
        switch viewModel.screen {
        case .main:
            MainView(viewModel: viewModel, store: store, gallery: gallery, onOpenGallery: { showGallery = true })
        case .crop:
            CropView(viewModel: viewModel)
        case .frameRate:
            FrameRateView(viewModel: viewModel)
        case .appearance:
            AppearanceView(viewModel: viewModel)
        case .preview:
            PreviewView(viewModel: viewModel, store: store, gallery: gallery)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}

#Preview {
    ContentView()
}
