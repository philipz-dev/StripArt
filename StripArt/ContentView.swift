import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = StripArtViewModel()

    var body: some View {
        NavigationStack {
            screenContent
                .animation(.easeInOut(duration: 0.25), value: viewModel.screen)
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Saved", isPresented: successBinding) {
            Button("OK", role: .cancel) {
                viewModel.saveSuccessMessage = nil
            }
        } message: {
            Text(viewModel.saveSuccessMessage ?? "")
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

    private var successBinding: Binding<Bool> {
        Binding(
            get: { viewModel.saveSuccessMessage != nil },
            set: { if !$0 { viewModel.saveSuccessMessage = nil } }
        )
    }
}

#Preview {
    ContentView()
}
