import PhotosUI
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: StripArtViewModel
    @State private var showCamera = false
    @FocusState private var focusedField: ResolutionField?

    private enum ResolutionField {
        case height
        case width
    }

    // Shared brand gradient: light blue → deep blue.
    private var brandGradient: LinearGradient { BrandStyle.blue }

    var body: some View {
        ZStack {
            background

            if viewModel.sourceImage != nil {
                photoReview
            } else {
                setupContent
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
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil { viewModel.normalizeResolutionText() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                viewModel.setCapturedImage(image)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Setup (no photo yet)

    private var setupContent: some View {
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
    }

    // MARK: - Photo review (photo selected)

    private var photoReview: some View {
        VStack(spacing: 24) {
            logo
                .padding(.top, 8)

            if let image = viewModel.sourceImage {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black)
                    .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 8)
            }

            decisionButtons
        }
        .padding(24)
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
        VStack(spacing: 6) {
            Text("LED Strip Animator")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Resolution

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(number: "1", title: "Set LED bar resolution")

            HStack(spacing: 16) {
                resolutionField(title: "Height", text: $viewModel.heightText, field: .height)
                Text("×")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                resolutionField(title: "Width", text: $viewModel.widthText, field: .width)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func resolutionField(title: String, text: Binding<String>, field: ResolutionField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: field)
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
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(number: "2", title: "Import or take a photo")

            HStack(spacing: 14) {
                PhotosPicker(
                    selection: $viewModel.selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    photoActionLabel(title: "Import Photo", systemImage: "photo.on.rectangle")
                }

                Button {
                    showCamera = true
                } label: {
                    photoActionLabel(title: "Take Photo", systemImage: "camera.fill")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func photoActionLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(gradientButtonBackground)
    }

    private func stepHeader(number: String, title: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(brandGradient))
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Decision (confirm / reject)

    private var decisionButtons: some View {
        HStack(spacing: 28) {
            Button {
                viewModel.clearSelectedPhoto()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(
                CircleIconButtonStyle(
                    gradient: BrandStyle.red,
                    shadowColor: BrandStyle.redShadow,
                    diameter: 72,
                    iconSize: 27
                )
            )

            Button {
                viewModel.goToCrop()
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(
                CircleIconButtonStyle(
                    gradient: BrandStyle.green,
                    shadowColor: BrandStyle.greenShadow,
                    diameter: 72,
                    iconSize: 27
                )
            )
            .opacity(viewModel.canProceedFromMain ? 1 : 0.45)
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
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: BrandStyle.blueShadow.opacity(0.4), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Shared white card styling

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
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
}

private extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
