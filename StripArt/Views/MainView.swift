import PhotosUI
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: StripArtViewModel
    @ObservedObject var gallery: GalleryStore
    var onOpenGallery: () -> Void
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
        setupContent
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
                    VStack(spacing: 8) {
                        StripArtLogo()
                            .padding(.top, 8)

                        header
                    }
                    .padding(.bottom, 8)

                    resolutionSection

                    photoSection
                }
                .padding(24)
                .padding(.bottom, hideTipsOnPhotoAction ? 56 : 0)
            }

            if hideTipsOnPhotoAction {
                tipsHelpButton
            }

            if !gallery.isEmpty {
                galleryButton
            }
        }
    }

    private var galleryButton: some View {
        Button(action: onOpenGallery) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BrandStyle.blue)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .accessibilityLabel("Gallery")
    }

    // MARK: - Header

    private var header: some View {
        Text("LED Strip Animator".uppercased())
            .font(.footnote.weight(.semibold))
            .tracking(2)
            .foregroundStyle(.secondary)
    }

    // MARK: - Resolution

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader(number: "1", title: "Set LED bar resolution")

            HStack(alignment: .center, spacing: 14) {
                resolutionField(title: "Height", text: $viewModel.heightText, field: .height)
                Image(systemName: "multiply")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .offset(y: 11)
                resolutionField(title: "Width", text: $viewModel.widthText, field: .width)
            }

            if !viewModel.resolutionIsValid {
                Text("Enter valid values (1–256 height, 1–512 width).")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Aspect ratio  \(viewModel.resolution.simplifiedAspectRatioLabel)")
                    .font(.caption)
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
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 1)
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
                .font(.title2)
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
            Image(systemName: "\(number).circle.fill")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(brandGradient)
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

    private var gradientButtonBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(brandGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: BrandStyle.blueShadow.opacity(0.18), radius: 5, x: 0, y: 2)
    }
}

