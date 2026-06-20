import PhotosUI
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: StripArtViewModel

    // Shared brand gradient: light blue → deep blue.
    private var brandGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.36, green: 0.68, blue: 1.0),
                Color(red: 0.05, green: 0.27, blue: 0.78)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 28) {
                        logo
                            .padding(.top, 8)

                        header

                        resolutionSection

                        photoSection
                    }
                    .padding(24)
                }

                if viewModel.sourceImage != nil {
                    decisionButtons
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                        .background(.ultraThinMaterial)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: viewModel.selectedPhotoItem) {
            Task { await viewModel.loadSelectedPhoto() }
        }
        .onChange(of: viewModel.heightText) { viewModel.syncResolutionFromText() }
        .onChange(of: viewModel.widthText) { viewModel.syncResolutionFromText() }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(red: 0.97, green: 0.98, blue: 0.99)

            // Soft diffuse ambient lighting.
            RadialGradient(
                colors: [Color(red: 0.42, green: 0.7, blue: 1.0).opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color(red: 0.55, green: 0.45, blue: 1.0).opacity(0.14), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Logo

    private var logo: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            logoText("Str")
            ZStack(alignment: .top) {
                logoText("i")
                // Refined glowing spark on the dot of the "i".
                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .fill(Color(red: 0.6, green: 0.85, blue: 1.0))
                            .blur(radius: 3)
                    )
                    .shadow(color: Color(red: 0.4, green: 0.75, blue: 1.0), radius: 6)
                    .offset(y: -3)
            }
            logoText("pArt")
        }
        .font(.system(size: 44, weight: .heavy, design: .rounded))
    }

    private func logoText(_ string: String) -> some View {
        Text(string)
            .foregroundStyle(brandGradient)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            ledIcon

            Text("LED Strip Animator")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)

            Text("Set LED bar resolution and pick a photo")
                .font(.subheadline)
                .foregroundStyle(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    // High-fidelity 3D-style icon with a soft LED bar illustration.
    private var ledIcon: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(brandGradient)
            .frame(width: 88, height: 88)
            .overlay(
                // Glossy top highlight for a 3D feel.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            )
            .overlay(ledBarIllustration)
            .shadow(color: Color(red: 0.1, green: 0.3, blue: 0.7).opacity(0.35), radius: 14, x: 0, y: 8)
    }

    private var ledBarIllustration: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color(red: 0.06, green: 0.12, blue: 0.28))
            .frame(width: 60, height: 26)
            .overlay(
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { index in
                        Circle()
                            .fill(.white)
                            .overlay(Circle().fill(.white).blur(radius: 1.5))
                            .opacity(index % 2 == 0 ? 1.0 : 0.55)
                            .shadow(color: .white.opacity(0.8), radius: 2)
                    }
                }
                .padding(.horizontal, 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            )
    }

    // MARK: - Resolution

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resolution (height × width)")
                .font(.system(.headline, design: .rounded))

            HStack(spacing: 16) {
                resolutionField(title: "Height", text: $viewModel.heightText)
                Text("×")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                resolutionField(title: "Width", text: $viewModel.widthText)
            }

            if !viewModel.resolutionIsValid {
                Text("Enter valid values (1–256 height, 1–512 width).")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Aspect ratio  \(viewModel.resolution.simplifiedAspectRatioLabel)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    .white.shadow(.inner(color: .black.opacity(0.06), radius: 4, x: 0, y: 2))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 10)
    }

    private func resolutionField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title3.weight(.semibold))
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.96, blue: 0.98))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
        }
    }

    // MARK: - Photo

    private var photoSection: some View {
        VStack(spacing: 16) {
            if let image = viewModel.sourceImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            }

            PhotosPicker(
                selection: $viewModel.selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(
                    viewModel.sourceImage == nil ? "Choose Photo" : "Choose Different Photo",
                    systemImage: "photo.badge.plus.fill"
                )
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(gradientButtonBackground)
            }
        }
    }

    // MARK: - Decision (confirm / reject)

    private var decisionButtons: some View {
        HStack(spacing: 28) {
            Button {
                viewModel.clearSelectedPhoto()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.95, green: 0.42, blue: 0.42),
                                        Color(red: 0.82, green: 0.18, blue: 0.24)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color(red: 0.7, green: 0.1, blue: 0.15).opacity(0.4), radius: 12, x: 0, y: 6)
                    )
            }

            Button {
                viewModel.goToCrop()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 78)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.30, green: 0.78, blue: 0.50),
                                        Color(red: 0.10, green: 0.55, blue: 0.32)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color(red: 0.1, green: 0.45, blue: 0.25).opacity(0.45), radius: 14, x: 0, y: 7)
                    )
                    .opacity(viewModel.canProceedFromMain ? 1 : 0.45)
            }
            .disabled(!viewModel.canProceedFromMain)
        }
        .frame(maxWidth: .infinity)
    }

    private var gradientButtonBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(brandGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.25), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .shadow(color: Color(red: 0.1, green: 0.3, blue: 0.7).opacity(0.4), radius: 12, x: 0, y: 6)
    }
}
