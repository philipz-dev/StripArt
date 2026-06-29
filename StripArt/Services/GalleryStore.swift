import Foundation

/// Persists saved animations as GIF files in the app's Application Support
/// directory, with a small JSON index of metadata. Newest items are kept first.
@MainActor
final class GalleryStore: ObservableObject {

    @Published private(set) var items: [SavedAnimation] = []

    private let directory: URL
    private let indexURL: URL
    private let fileManager = FileManager.default

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directory = base.appendingPathComponent("Gallery", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        createDirectoryIfNeeded()
        load()
    }

    // MARK: - Derived values

    var isEmpty: Bool { items.isEmpty }

    var totalByteSize: Int {
        items.reduce(0) { $0 + $1.byteSize }
    }

    /// Localized total size, e.g. "2,2 MB" in a Belgian Dutch locale.
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalByteSize), countStyle: .file)
    }

    // MARK: - File access

    func gifURL(for item: SavedAnimation) -> URL {
        directory.appendingPathComponent(item.fileName)
    }

    func data(for item: SavedAnimation) -> Data? {
        try? Data(contentsOf: gifURL(for: item))
    }

    // MARK: - Mutations

    /// Stores a freshly exported GIF and prepends it to the gallery.
    func add(data: Data, resolution: LEDResolution) {
        let id = UUID()
        let fileName = "\(id.uuidString).gif"
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            let item = SavedAnimation(
                id: id,
                createdAt: Date(),
                width: resolution.width,
                height: resolution.height,
                fileName: fileName,
                byteSize: data.count
            )
            items.insert(item, at: 0)
            persistIndex()
        } catch {
            // Gallery is best-effort; a failed write should not interrupt saving.
        }
    }

    /// Removes the animation from the app's gallery only. The copy already saved
    /// to the user's Photo Library is left untouched.
    func remove(_ item: SavedAnimation) {
        try? fileManager.removeItem(at: gifURL(for: item))
        items.removeAll { $0.id == item.id }
        persistIndex()
    }

    #if DEBUG
    func removeAllForTesting() {
        for item in items {
            try? fileManager.removeItem(at: gifURL(for: item))
        }
        items = []
        persistIndex()
    }
    #endif

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([SavedAnimation].self, from: data) else {
            items = []
            return
        }
        items = decoded
            .filter { fileManager.fileExists(atPath: gifURL(for: $0).path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func createDirectoryIfNeeded() {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
