import ImageIO
import SwiftUI
import UIKit

struct GalleryView: View {
    @ObservedObject var gallery: GalleryStore
    @Environment(\.dismiss) private var dismiss

    @State private var selected: SavedAnimation?
    @State private var busyMessage: String?
    @State private var alert: GalleryAlert?

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header

                if gallery.isEmpty {
                    emptyState
                } else {
                    list
                    footer
                }
            }

            if let busyMessage {
                busyOverlay(busyMessage)
            }
        }
        .confirmationDialog(
            selected?.resolutionLabel ?? "",
            isPresented: dialogBinding,
            titleVisibility: .visible
        ) {
            Button("Save to Photo Library") { resaveSelected() }
            if FeatureFlags.ledSimulationExport {
                Button("Save LED Simulation to Photo Library") { saveSimulation() }
            }
            Button("Remove", role: .destructive) { removeSelected() }
            Button("Cancel", role: .cancel) { selected = nil }
        }
        .alert(item: $alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    private func busyOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView(message)
                .tint(.white)
                .foregroundStyle(.white)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        }
        .transition(.opacity)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            ScreenTitle(title: "Gallery")

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BrandStyle.blue)
                        .padding(8)
                }
                .accessibilityLabel("Back")

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(gallery.items) { item in
                    Button {
                        selected = item
                    } label: {
                        GalleryRow(item: item, gallery: gallery)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var footer: some View {
        Text("\(gallery.formattedTotalSize) total · \(gallery.items.count) \(gallery.items.count == 1 ? "animation" : "animations")")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text("No saved animations yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var dialogBinding: Binding<Bool> {
        Binding(
            get: { selected != nil && busyMessage == nil },
            set: { if !$0 { selected = nil } }
        )
    }

    private func resaveSelected() {
        guard let item = selected, let data = gallery.data(for: item) else {
            selected = nil
            alert = GalleryAlert(title: "Save failed", message: "The animation file could not be found.")
            return
        }
        selected = nil
        busyMessage = "Saving…"
        Task {
            do {
                try await PhotoLibrarySaver.saveGIF(data)
                busyMessage = nil
                alert = GalleryAlert(title: "Saved", message: "The animation was saved to your Photo Library.")
            } catch {
                busyMessage = nil
                alert = GalleryAlert(title: "Save failed", message: error.localizedDescription)
            }
        }
    }

    private func saveSimulation() {
        guard let item = selected, let data = gallery.data(for: item) else {
            selected = nil
            alert = GalleryAlert(title: "Save failed", message: "The animation file could not be found.")
            return
        }
        selected = nil
        busyMessage = "Rendering LED simulation…"
        Task {
            let simulation = await Task.detached(priority: .userInitiated) {
                LEDSimulationRenderer.makeSimulationGIF(from: data)
            }.value

            guard let simulation else {
                busyMessage = nil
                alert = GalleryAlert(title: "Save failed", message: "The LED simulation could not be created.")
                return
            }

            do {
                try await PhotoLibrarySaver.saveGIF(simulation)
                busyMessage = nil
                alert = GalleryAlert(title: "Saved", message: "The LED simulation was saved to your Photo Library.")
            } catch {
                busyMessage = nil
                alert = GalleryAlert(title: "Save failed", message: error.localizedDescription)
            }
        }
    }

    private func removeSelected() {
        guard let item = selected else { return }
        selected = nil
        gallery.remove(item)
    }
}

// MARK: - Row

private struct GalleryRow: View {
    let item: SavedAnimation
    @ObservedObject var gallery: GalleryStore

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Color.black

                if let data = gallery.data(for: item) {
                    AnimatedGIFView(data: data, aspectRatio: item.aspectRatio)
                }
            }
            // Apply the aspect ratio to the stack so the black backdrop, the
            // animation, and the border share one exact rectangle.
            .aspectRatio(item.aspectRatio, contentMode: .fit)
            .overlay(Picture3DBorder())
            .frame(maxWidth: .infinity, maxHeight: 240)

            HStack {
                Text(item.resolutionLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(item.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle(padding: 14)
    }
}

// MARK: - Animated GIF player

/// Decodes a GIF into LED grids and plays them as an LED bar, so a saved
/// animation looks identical to the live preview screen.
struct AnimatedGIFView: View {
    let data: Data
    let aspectRatio: Double

    @State private var grids: [LEDPixelGrid] = []
    @State private var delays: [Double] = []
    @State private var totalDuration: Double = 0

    var body: some View {
        Group {
            if grids.isEmpty {
                Color.black
            } else {
                TimelineView(.animation) { context in
                    LEDBarCanvas(grid: grids[frameIndex(at: context.date)])
                }
            }
        }
        .task(id: data) { await decode() }
    }

    private func frameIndex(at date: Date) -> Int {
        guard totalDuration > 0, grids.count > 1 else { return 0 }
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: totalDuration)
        var accumulated = 0.0
        for (index, delay) in delays.enumerated() {
            accumulated += delay
            if t < accumulated { return index }
        }
        return grids.count - 1
    }

    private func decode() async {
        let payload = data
        let decoded = await Task.detached(priority: .userInitiated) { () -> ([LEDPixelGrid], [Double]) in
            guard let source = CGImageSourceCreateWithData(payload as CFData, nil) else { return ([], []) }
            let count = CGImageSourceGetCount(source)
            var ledGrids: [LEDPixelGrid] = []
            var times: [Double] = []
            ledGrids.reserveCapacity(count)
            times.reserveCapacity(count)
            for index in 0..<count {
                guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
                ledGrids.append(LEDPixelGrid(image: image))
                times.append(Self.frameDelay(source: source, index: index))
            }
            return (ledGrids, times)
        }.value

        grids = decoded.0
        delays = decoded.1
        totalDuration = decoded.1.reduce(0, +)
    }

    private static func frameDelay(source: CGImageSource, index: Int) -> Double {
        let fallback = 0.08
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return fallback
        }
        if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
            return unclamped
        }
        if let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double, clamped > 0 {
            return clamped
        }
        return fallback
    }
}

// MARK: - Alert model

private struct GalleryAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
