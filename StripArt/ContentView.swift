import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = StripArtViewModel()
    @StateObject private var store = StoreManager()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                screenContent

                if viewModel.showSaveConfirmation {
                    SaveSuccessOverlay(
                        remainingFreeExports: store.isUnlocked ? nil : viewModel.remainingFreeExports,
                        store: store
                    ) {
                        viewModel.confirmSaveSuccess()
                    }
                    .transition(.opacity)
                }

                if viewModel.showPaywall {
                    PaywallView(
                        store: store,
                        freeLimit: viewModel.freeExportLimit,
                        onClose: { viewModel.showPaywall = false },
                        onUnlocked: {
                            viewModel.showPaywall = false
                            Task { await viewModel.saveGIF(unlocked: true) }
                        }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.screen)
            .animation(.easeInOut(duration: 0.25), value: viewModel.showSaveConfirmation)
            .animation(.easeInOut(duration: 0.25), value: viewModel.showPaywall)
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
                await DebugReset.performFullReset(store: store, viewModel: viewModel)
            }
        }
        #endif
    }

    @ViewBuilder
    private var screenContent: some View {
        switch viewModel.screen {
        case .main:
            MainView(viewModel: viewModel)
        case .crop:
            CropView(viewModel: viewModel)
        case .frameRate:
            FrameRateView(viewModel: viewModel)
        case .appearance:
            AppearanceView(viewModel: viewModel)
        case .preview:
            PreviewView(viewModel: viewModel, store: store)
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
