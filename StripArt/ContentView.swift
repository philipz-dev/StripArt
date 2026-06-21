import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = StripArtViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                screenContent

                if viewModel.showSaveConfirmation {
                    SaveSuccessOverlay {
                        viewModel.confirmSaveSuccess()
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.screen)
            .animation(.easeInOut(duration: 0.25), value: viewModel.showSaveConfirmation)
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
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
            PreviewView(viewModel: viewModel)
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
