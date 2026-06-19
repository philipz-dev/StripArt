import Photos
import UIKit

enum PhotoLibrarySaver {

    enum SaveError: LocalizedError {
        case unauthorized
        case exportFailed
        case saveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                "Geen toegang tot de fotobibliotheek."
            case .exportFailed:
                "GIF kon niet worden aangemaakt."
            case .saveFailed(let error):
                "Opslaan mislukt: \(error.localizedDescription)"
            }
        }
    }

    static func saveGIF(_ data: Data) async throws {
        let status = await requestAddAuthorization()
        guard status == .authorized || status == .limited else {
            throw SaveError.unauthorized
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: SaveError.saveFailed(error))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SaveError.saveFailed(
                        NSError(domain: "StripArt", code: -1)
                    ))
                }
            }
        }
    }

    private static func requestAddAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current == .notDetermined {
            return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        return current
    }
}
