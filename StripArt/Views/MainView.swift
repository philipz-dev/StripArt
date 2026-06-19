import PhotosUI
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: StripArtViewModel

    var body: some View {
        VStack(spacing: 28) {
            header

            resolutionSection

            photoSection

            Spacer()

            Button(action: viewModel.goToCrop) {
                Label("Doorgaan", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canProceedFromMain)
        }
        .padding(24)
        .navigationTitle("StripArt")
        .onChange(of: viewModel.selectedPhotoItem) {
            Task { await viewModel.loadSelectedPhoto() }
        }
        .onChange(of: viewModel.heightText) { viewModel.syncResolutionFromText() }
        .onChange(of: viewModel.widthText) { viewModel.syncResolutionFromText() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.split.3x1.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("LED Strip Animator")
                .font(.title2.bold())
            Text("Kies een foto en stel de resolutie van je LED-bar in.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resolutie (hoogte × breedte)")
                .font(.headline)

            HStack(spacing: 16) {
                resolutionField(title: "Hoogte", text: $viewModel.heightText)
                Text("×")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                resolutionField(title: "Breedte", text: $viewModel.widthText)
            }

            if !viewModel.resolutionIsValid {
                Text("Voer geldige waarden in (1–256 hoogte, 1–512 breedte).")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Aspect ratio: \(viewModel.resolution.width):\(viewModel.resolution.height)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func resolutionField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var photoSection: some View {
        VStack(spacing: 16) {
            if let image = viewModel.sourceImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            PhotosPicker(
                selection: $viewModel.selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(
                    viewModel.sourceImage == nil ? "Foto kiezen" : "Andere foto kiezen",
                    systemImage: "photo.on.rectangle"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
    }
}
