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
                Label("Continue", systemImage: "arrow.right.circle.fill")
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
            Text("Choose a photo and set your LED bar resolution.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resolution (height × width)")
                .font(.headline)

            HStack(spacing: 16) {
                resolutionField(title: "Height", text: $viewModel.heightText)
                Text("×")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                resolutionField(title: "Width", text: $viewModel.widthText)
            }

            if !viewModel.resolutionIsValid {
                Text("Enter valid values (1–256 height, 1–512 width).")
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
                    viewModel.sourceImage == nil ? "Choose Photo" : "Choose Different Photo",
                    systemImage: "photo.on.rectangle"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
    }
}
