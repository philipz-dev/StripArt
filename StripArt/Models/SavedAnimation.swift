import Foundation

/// Metadata for one animation the user has saved. The GIF itself lives as a
/// separate file in the app's Gallery folder; this record points at it.
struct SavedAnimation: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let width: Int
    let height: Int
    let fileName: String
    let byteSize: Int

    /// LED width : height, matching the preview screen's framing.
    var aspectRatio: Double {
        guard height > 0 else { return 1 }
        return Double(width) / Double(height)
    }

    var resolutionLabel: String {
        "\(height)×\(width) px"
    }
}
