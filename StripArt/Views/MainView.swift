import PhotosUI
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: StripArtViewModel
    @AppStorage("hideTipsOnPhotoAction") private var hideTipsOnPhotoAction = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showTips = false
    @State private var doNotShowTipsAgain = false
    @State private var pendingPhotoAction: PendingPhotoAction?
    @FocusState private var focusedField: ResolutionField?

    private enum ResolutionField {
        case height
        case width
    }

    private enum PendingPhotoAction {
        case importPhoto
        case takePhoto
    }

    // Shared brand gradient: light blue → deep blue.
    private var brandGradient: LinearGradient { BrandStyle.blue }

    var body: some View {
        Group {
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
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $viewModel.selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .overlay {
            if showTips {
                TipsView(
                    doNotShowAgain: $doNotShowTipsAgain,
                    onContinue: continueFromTips,
                    onDismiss: dismissTips
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showTips)
    }

    // MARK: - Setup (no photo yet)

    private var setupContent: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 28) {
                    StripArtLogo()
                        .padding(.top, 8)

                    header

                    resolutionSection

                    photoSection
                }
                .padding(24)
                .padding(.bottom, hideTipsOnPhotoAction ? 56 : 0)
            }

            if hideTipsOnPhotoAction {
                tipsHelpButton
            }
        }
    }

    // MARK: - Photo review (photo selected)

    private var photoReview: some View {
        VStack(spacing: 24) {
            StripArtLogo()
                .padding(.top, 8)

            if let image = viewModel.sourceImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay(Picture3DBorder())
            }

            decisionButtons
        }
        .padding(24)
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
                Button {
                    beginPhotoAction(.importPhoto)
                } label: {
                    photoActionLabel(title: "Import Photo", systemImage: "photo.on.rectangle")
                }

                Button {
                    beginPhotoAction(.takePhoto)
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

    // MARK: - Tips

    private var tipsHelpButton: some View {
        Button {
            pendingPhotoAction = nil
            doNotShowTipsAgain = hideTipsOnPhotoAction
            showTips = true
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BrandStyle.blue)
        }
        .padding(24)
        .accessibilityLabel("Show tips")
    }

    private func beginPhotoAction(_ action: PendingPhotoAction) {
        if hideTipsOnPhotoAction {
            performPhotoAction(action)
        } else {
            pendingPhotoAction = action
            doNotShowTipsAgain = false
            showTips = true
        }
    }

    private func continueFromTips() {
        if doNotShowTipsAgain {
            hideTipsOnPhotoAction = true
        }

        let action = pendingPhotoAction
        pendingPhotoAction = nil
        showTips = false
        doNotShowTipsAgain = false

        if let action {
            performPhotoAction(action)
        }
    }

    private func dismissTips() {
        pendingPhotoAction = nil
        showTips = false
        doNotShowTipsAgain = false
    }

    private func performPhotoAction(_ action: PendingPhotoAction) {
        switch action {
        case .importPhoto:
            showPhotoPicker = true
        case .takePhoto:
            showCamera = true
        }
    }

    // MARK: - Decision (confirm / reject)

    private var decisionButtons: some View {
        DecisionButtons(
            confirmEnabled: viewModel.canProceedFromMain,
            cancel: { viewModel.clearSelectedPhoto() },
            confirm: { viewModel.goToCrop() }
        )
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

